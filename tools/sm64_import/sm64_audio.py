#!/usr/bin/env python3
"""Renders Super Mario 64's music and sound effects to audio files, from your own ROM.

    python sm64_audio.py --rom "Super Mario 64 (USA).z64" [--sm64 path/to/sm64] [--out sm64_audio]

It uses the n64decomp/sm64 source (downloaded like sm64_to_roblox.py does) to extract the ROM's sound banks,
samples and sequences, then plays the sequences with a software version of the game's audio engine: sequence,
channel and layer scripts at 48 ticks per beat, instruments and drums from the banks, the envelopes, vibrato,
pitch bends and pan, mixed at 32 kHz with a light reverb. Each track is written as an .ogg file (ffmpeg needed),
or .wav without it. Requires numpy.
"""
import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys

import numpy as np

RATE = 32000
UPDATES_PER_SECOND = 240
SAMPLES_PER_UPDATE = RATE / UPDATES_PER_SECOND

# the tracks the game uses: output name -> (sequence, seconds to render at most)
TRACKS = {
    "music_lobby": ("04_level_inside_castle", 150),
    "music_meadow": ("03_level_grass", 150),
    "music_desert": ("06_level_hot", 150),
    "music_frost": ("08_level_snow", 150),
    "music_magma": ("0C_level_underground", 150),
    "music_starcastle": ("11_level_koopa_road", 150),
    "music_boss": ("07_level_boss_koopa", 120),
    "music_summon": ("0E_event_powerup", 40),
    "jingle_victory": ("01_cutscene_collect_star", 12),
    "jingle_star": ("15_cutscene_star_spawn", 10),
    "jingle_select": ("0D_menu_star_select", 10),
}


def note_freq(k):
    # gNoteFrequencies: 2^((k-39)/12), halved from 117 up
    f = 2.0 ** ((k - 39) / 12.0)
    return f * 0.5 if k >= 117 else f


def read_ext80(b):
    exp, mant = struct.unpack(">HQ", b)
    sign = -1 if exp & 0x8000 else 1
    exp &= 0x7FFF
    if exp == 0 and mant == 0:
        return 0.0
    return sign * mant * 2.0 ** (exp - 16383 - 63)


class Sample:
    def __init__(self, path):
        data = open(path, "rb").read()
        i = 12
        markers = {}
        loop = None
        self.rate = RATE
        pcm = b""
        while i + 8 <= len(data):
            cid = data[i : i + 4]
            n = struct.unpack(">I", data[i + 4 : i + 8])[0]
            body = data[i + 8 : i + 8 + n]
            if cid == b"COMM":
                self.rate = read_ext80(body[8:18])
            elif cid == b"MARK":
                count = struct.unpack(">H", body[:2])[0]
                j = 2
                for _ in range(count):
                    mid, pos, ln = struct.unpack(">HIB", body[j : j + 7])
                    markers[mid] = pos
                    j += 7 + ln
                    if (ln + 1) % 2:
                        j += 1
            elif cid == b"INST":
                mode, a, b = struct.unpack(">hHH", body[8:14])
                if mode != 0:
                    loop = (a, b)
            elif cid == b"SSND":
                offset = struct.unpack(">I", body[:4])[0]
                pcm = body[8 + offset :]
            i += 8 + n + (n & 1)
        self.pcm = np.frombuffer(pcm, dtype=">i2").astype(np.float32) / 32768.0
        self.tuning = self.rate / RATE
        self.loop = None
        if loop and loop[0] in markers and loop[1] in markers:
            s, e = markers[loop[0]], markers[loop[1]]
            if e > s + 1:
                self.loop = (s, min(e, len(self.pcm)))
        # one guard sample for interpolation
        self.pcm = np.append(self.pcm, self.pcm[-1:] if len(self.pcm) else [0.0]).astype(np.float32)


WAVES = None


def synthetic_waves():
    global WAVES
    if WAVES is None:
        t = np.arange(64) / 64.0
        WAVES = [
            (t * 2 - 1).astype(np.float32),  # sawtooth
            (1 - 4 * np.abs(t - 0.5)).astype(np.float32),  # triangle
            np.sin(t * 2 * math.pi).astype(np.float32),  # sine
            np.where(t < 0.5, 1.0, -1.0).astype(np.float32),  # square
        ]
    return WAVES


class Bank:
    def __init__(self, root, name):
        d = json.load(open(os.path.join(root, "sound", "sound_banks", name + ".json")))
        sample_bank = d["sample_bank"]
        if isinstance(sample_bank, dict):
            sample_bank = sample_bank.get("then") if "VERSION_US" in sample_bank.get("ifdef", []) else sample_bank.get("else")
        self.dir = os.path.join(root, "sound", "samples", sample_bank)
        self.envelopes = d["envelopes"]
        self.cache = {}
        insts = d["instruments"]
        self.drums = []
        for drum in insts.get("percussion", []) or []:
            self.drums.append(self.sound_of(drum, drum["sound"]) if drum else None)
        self.instruments = []
        for nm in d.get("instrument_list", []):
            if isinstance(nm, dict):
                nm = nm.get("then") if "VERSION_US" in nm.get("ifdef", []) else nm.get("else")
            inst = insts.get(nm) if nm else None
            if inst and "ifdef" in inst and "VERSION_US" not in inst["ifdef"]:
                inst = None
            if not inst:
                self.instruments.append(None)
                continue
            self.instruments.append(
                {
                    "env": self.envelope(inst["envelope"]),
                    "release": inst["release_rate"],
                    "lo": inst.get("normal_range_lo", 0),
                    "hi": inst.get("normal_range_hi", 127),
                    "sound_lo": self.load(inst.get("sound_lo")),
                    "sound": self.load(inst["sound"]),
                    "sound_hi": self.load(inst.get("sound_hi")),
                }
            )

    def envelope(self, name):
        return self.envelopes[name]

    def load(self, ref):
        if isinstance(ref, dict) and "ifdef" in ref:
            ref = ref.get("then") if "VERSION_US" in ref["ifdef"] else ref.get("else")
        if ref is None:
            return None
        if isinstance(ref, dict):
            sample = self.sample(ref["sample"])
            return (sample, ref.get("tuning", sample.tuning)) if sample else None
        sample = self.sample(ref)
        return (sample, sample.tuning) if sample else None

    def sample(self, name):
        if name not in self.cache:
            path = os.path.join(self.dir, name + ".aiff")
            self.cache[name] = Sample(path) if os.path.exists(path) else None
        return self.cache[name]

    def sound_of(self, drum, ref):
        snd = self.load(ref)
        if not snd:
            return None
        return {"env": self.envelope(drum["envelope"]), "release": drum["release_rate"], "pan": drum["pan"] / 128.0, "sound": snd}


DEFAULT_ENV = [[4, 32000], [1000, 32000], "hang"]


class Note:
    """One playing voice: a sample (or synthetic wave) with an envelope."""

    def __init__(self, sound, wave, freq, env, release, vel, pan, chan, layer):
        self.sound = sound
        self.wave = wave
        self.freq = freq
        self.env = env or DEFAULT_ENV
        self.release = release
        self.vel = vel
        self.pan = pan
        self.chan = chan
        self.layer = layer
        self.pos = 0.0
        self.cur = 0.0  # envelope 0..32767
        self.target = 0.0
        self.velo = 0.0
        self.delay = 0
        self.index = 0
        self.state = "loop"
        self.done = False
        self.prev_amp = 0.0
        self.vib_time = 0
        self.vib_delay = chan.vib_delay

    def release_now(self, rate=None):
        if self.state != "release":
            self.state = "release"
            r = rate if rate is not None else self.release
            self.fade = max(1, (r or 0x20) * 24)

    def adsr(self):
        while self.state == "loop":
            if self.index >= len(self.env):
                self.state = "hang"
                break
            p = self.env[self.index]
            if p == "hang":
                self.state = "hang"
            elif p == "stop":
                self.state = "stop"
            elif p == "restart":
                self.index = 0
                continue
            elif isinstance(p, list) and p[0] == "goto":
                self.index = p[1]
                continue
            else:
                self.delay = max(1, p[0])
                self.target = p[1]
                self.velo = (self.target - self.cur) / self.delay
                self.state = "fade"
                self.index += 1
            break
        if self.state == "fade":
            self.cur += self.velo
            self.delay -= 1
            if self.delay <= 0:
                self.state = "loop"
        elif self.state == "release":
            self.cur -= self.fade
            if self.cur < 100:
                self.cur = 0
                self.done = True
        elif self.state == "stop":
            self.cur = 0
            self.done = True
        return max(0.0, self.cur) / 32767.0

    def render(self, n, freq_mul):
        amp = self.adsr() * self.vel * self.chan.volume()
        step = self.freq * freq_mul
        if self.wave is not None:
            data = self.wave
            positions = self.pos + step * np.arange(n)
            self.pos = (self.pos + step * n) % 64
            idx = positions % 64
            i0 = idx.astype(np.int32)
            frac = idx - i0
            out = data[i0] * (1 - frac) + data[(i0 + 1) % 64] * frac
        else:
            sample = self.sound
            pcm = sample.pcm
            positions = self.pos + step * np.arange(n)
            end = len(pcm) - 1
            if sample.loop:
                ls, le = sample.loop
                over = positions >= le
                if over.any():
                    positions[over] = ls + np.mod(positions[over] - ls, le - ls)
                self.pos = self.pos + step * n
                if self.pos >= le:
                    self.pos = ls + (self.pos - ls) % (le - ls)
            else:
                self.pos += step * n
                if positions[0] >= end:
                    self.done = True
                    return None
                positions = np.minimum(positions, end - 1e-3)
                if self.pos >= end:
                    self.done = True
            i0 = positions.astype(np.int32)
            frac = (positions - i0).astype(np.float32)
            out = pcm[i0] * (1 - frac) + pcm[i0 + 1] * frac
        ramp = np.linspace(self.prev_amp, amp, n, endpoint=False, dtype=np.float32)
        self.prev_amp = amp
        return out * ramp


class Script:
    """A script's position and its stack: calls push a return address, loops push [iterations, start]."""

    def __init__(self, pc):
        self.pc = pc
        self.stack = []

    def ret(self):
        top = self.stack.pop()
        self.pc = top[1]

    def loop(self, n):
        self.stack.append([n or 256, self.pc])

    def loopend(self):
        top = self.stack[-1]
        top[0] -= 1
        if top[0] > 0:
            self.pc = top[1]
        else:
            self.stack.pop()


class Layer:
    def __init__(self, chan, pc):
        self.chan = chan
        self.s = Script(pc)
        self.enabled = True
        self.delay = 0
        self.duration = 0
        self.note_duration = 0x80
        self.play_pct = 0
        self.short_pct = 0
        self.vel2 = 0.0
        self.pan = 0.5
        self.transpose = 0
        self.continuous = False
        self.stop = False
        self.inst = None
        self.adsr = None  # (env, release) from layer setinstr or drum
        self.note = None


class Channel:
    def __init__(self, player, pc):
        self.p = player
        self.s = Script(pc)
        self.enabled = True
        self.stop_script = False
        self.delay = 0
        self.vol = 1.0
        self.vol_scale = 1.0
        self.freq_scale = 1.0
        self.pan = 0.5
        self.pan_weight = 1.0
        self.transpose = 0
        self.large = False
        self.inst = None
        self.inst_or_wave = None  # None: nothing, 0: drums, ("inst"), or wave id >= 0x80
        self.env = DEFAULT_ENV
        self.release = 0x20
        self.reverb = 0
        self.vib_rate = 0x800
        self.vib_extent = 0
        self.vib_delay = 0
        self.layers = [None] * 4
        self.value = 0
        self.io = [-1] * 8
        self.bank = player.banks[0]

    def volume(self):
        return self.vol * self.vol_scale * self.p.vol


class Player:
    def __init__(self, data, banks):
        self.d = bytearray(data)
        self.banks = banks
        self.s = Script(0)
        self.delay = 0
        self.tempo = 120
        self.acc = 0
        self.vol = 1.0
        self.transpose = 0
        self.channels = [None] * 16
        self.value = 0
        self.ended = False
        self.loop_at = None  # time (updates) of the first jump back in the sequence script
        self.updates = 0
        self.notes = []
        self.short_vel = [12, 25, 38, 51, 57, 64, 71, 76, 83, 89, 96, 102, 109, 115, 121, 127]
        self.short_dur = [229, 203, 177, 151, 139, 126, 113, 100, 87, 74, 61, 48, 36, 23, 10, 0]

    # --- byte readers
    def u8(self, s):
        v = self.d[s.pc]
        s.pc += 1
        return v

    def s8(self, s):
        v = self.u8(s)
        return v - 256 if v >= 128 else v

    def u16(self, s):
        v = (self.d[s.pc] << 8) | self.d[s.pc + 1]
        s.pc += 2
        return v

    def var(self, s):
        v = self.u8(s)
        if v & 0x80:
            v = ((v & 0x7F) << 8) | self.u8(s)
        return v

    # --- sequence script
    def seq_tick(self):
        if self.ended:
            return
        if self.delay > 0:
            self.delay -= 1
            if self.delay > 0:
                return
        s = self.s
        for _ in range(1000):
            cmd = self.u8(s)
            if cmd == 0xFF:
                if not s.stack:
                    self.ended = True
                    return
                s.ret()
            elif cmd == 0xFE:
                self.delay = 1
                return
            elif cmd == 0xFD:
                self.delay = self.var(s)
                return
            elif cmd == 0xFC:
                a = self.u16(s)
                s.stack.append([0, s.pc])
                s.pc = a
            elif cmd in (0xFB, 0xFA, 0xF9, 0xF5):
                a = self.u16(s)
                if cmd == 0xFA and self.value != 0:
                    continue
                if cmd == 0xF9 and self.value >= 0:
                    continue
                if cmd == 0xF5 and self.value < 0:
                    continue
                if a < s.pc and self.loop_at is None:
                    self.loop_at = self.updates
                s.pc = a
            elif cmd == 0xF8:
                s.loop(self.u8(s))
            elif cmd == 0xF7:
                s.loopend()
            elif cmd in (0xF2,):
                self.u8(s)
            elif cmd == 0xF1:
                pass
            elif cmd == 0xDF:
                self.transpose = self.s8(s)
            elif cmd == 0xDE:
                self.transpose += self.s8(s)
            elif cmd == 0xDD:
                self.tempo = self.u8(s)
            elif cmd == 0xDC:
                self.tempo += self.s8(s)
            elif cmd == 0xDB:
                self.vol = self.u8(s) / 127.0
            elif cmd == 0xDA:
                self.vol = max(0.0, self.vol + self.s8(s) / 127.0)
            elif cmd == 0xD7:
                mask = self.u16(s)
                for i in range(16):
                    if mask & (1 << i):
                        self.free_layers(self.channels[i])
                        self.channels[i] = Channel(self, 0)
                        self.channels[i].enabled = False
            elif cmd == 0xD6:
                mask = self.u16(s)
                for i in range(16):
                    if mask & (1 << i) and self.channels[i]:
                        self.channels[i].enabled = False
            elif cmd in (0xD5, 0xD3, 0xD0):
                self.u8(s)
            elif cmd == 0xD4:
                pass
            elif cmd in (0xD2, 0xD1):
                a = self.u16(s)
                table = list(self.d[a : a + 16])
                if cmd == 0xD2:
                    self.short_vel = table
                else:
                    self.short_dur = table
            elif cmd == 0xCC:
                self.value = self.u8(s)
            elif cmd == 0xC9:
                self.value &= self.u8(s)
            elif cmd == 0xC8:
                self.value -= self.u8(s)
            else:
                hi, lo = cmd & 0xF0, cmd & 0x0F
                if hi == 0x90:
                    self.start_channel(lo, self.u16(s))
                elif hi == 0x00:
                    ch = self.channels[lo]
                    self.value = 1 if (ch is None or not ch.enabled) else 0
                elif hi in (0x50, 0x70, 0x80):
                    if hi == 0x80:
                        self.value = -1
                else:
                    raise ValueError("unknown seq cmd %02x at %x" % (cmd, s.pc - 1))

    # --- channel script
    def free_layers(self, ch):
        if ch:
            for i, layer in enumerate(ch.layers):
                if layer and layer.note:
                    layer.note.release_now()
                ch.layers[i] = None

    def start_channel(self, index, pc):
        # a channel keeps its settings when restarted; only its script and layers start over
        ch = self.channels[index]
        if ch is None:
            ch = Channel(self, pc)
            self.channels[index] = ch
        self.free_layers(ch)
        ch.enabled = True
        ch.stop_script = False
        ch.s = Script(pc)
        ch.delay = 0

    def set_instrument(self, ch, inst_id):
        if inst_id >= 0x80:
            ch.inst_or_wave = inst_id
            ch.inst = None
        elif inst_id == 0x7F:
            ch.inst_or_wave = 0
        else:
            insts = ch.bank.instruments
            if not insts:
                ch.inst_or_wave = None
                return
            inst = insts[min(inst_id, len(insts) - 1)]
            if inst is None:
                ch.inst_or_wave = None
                return
            ch.inst = inst
            ch.inst_or_wave = "inst"
            ch.env = inst["env"]
            ch.release = inst["release"]

    def chan_tick(self, ch):
        if not ch.enabled:
            return
        if not ch.stop_script:
            if ch.delay > 0:
                ch.delay -= 1
            s = ch.s
            if ch.delay == 0:
                for _ in range(1000):
                    cmd = self.u8(s)
                    if cmd == 0xFF:
                        if not s.stack:
                            ch.enabled = False
                            for layer in ch.layers:
                                if layer and layer.note:
                                    layer.note.release_now()
                            return
                        s.ret()
                    elif cmd == 0xFE:
                        break
                    elif cmd == 0xFD:
                        ch.delay = self.var(s)
                        break
                    elif cmd == 0xF3:
                        ch.stop_script = True
                        break
                    elif cmd > 0xC0:
                        self.chan_cmd(ch, s, cmd)
                    else:
                        self.chan_low(ch, s, cmd)
        for layer in ch.layers:
            if layer and layer.enabled:
                self.layer_tick(ch, layer)

    def chan_cmd(self, ch, s, cmd):
        if cmd == 0xFC:
            a = self.u16(s)
            s.stack.append([0, s.pc])
            s.pc = a
        elif cmd == 0xF8:
            s.loop(self.u8(s))
        elif cmd == 0xF7:
            s.loopend()
        elif cmd == 0xF6:
            if s.stack:
                s.stack.pop()
        elif cmd in (0xFB, 0xFA, 0xF9, 0xF5):
            a = self.u16(s)
            v = ch.value
            if cmd == 0xFA and v != 0:
                return
            if cmd == 0xF9 and v >= 0:
                return
            if cmd == 0xF5 and v < 0:
                return
            s.pc = a
        elif cmd == 0xF2:
            self.u8(s)
        elif cmd == 0xF1:
            pass
        elif cmd == 0xC2:
            ch.dyntable = self.u16(s)
        elif cmd == 0xC5:
            if ch.value != -1:
                t = ch.dyntable + 2 * ch.value
                ch.dyntable = (self.d[t] << 8) | self.d[t + 1]
        elif cmd == 0xE4:
            if ch.value != -1:
                t = ch.dyntable + 2 * ch.value
                s.stack.append([0, s.pc])
                s.pc = (self.d[t] << 8) | self.d[t + 1]
        elif cmd == 0xC1:
            self.set_instrument(ch, self.u8(s))
        elif cmd == 0xC3:
            ch.large = False
        elif cmd == 0xC4:
            ch.large = True
        elif cmd == 0xDF:
            ch.vol = self.u8(s) / 127.0
        elif cmd == 0xE0:
            ch.vol_scale = self.u8(s) / 128.0
        elif cmd == 0xDE:
            ch.freq_scale = self.u16(s) / 32768.0
        elif cmd == 0xD3:
            ch.freq_scale = 2.0 ** (self.s8(s) / 127.0)
        elif cmd == 0xDD:
            ch.pan = self.u8(s) / 128.0
        elif cmd == 0xDC:
            ch.pan_weight = self.u8(s) / 128.0
        elif cmd == 0xDB:
            ch.transpose = self.s8(s)
        elif cmd == 0xDA:
            a = self.u16(s)
            env = []
            while True:
                dl = (self.d[a] << 8) | self.d[a + 1]
                arg = (self.d[a + 2] << 8) | self.d[a + 3]
                a += 4
                if dl == 0:
                    env.append("stop")
                    break
                if dl == 0xFFFF:
                    env.append("hang")
                    break
                if dl == 0xFFFE:
                    env.append(["goto", arg])
                    break
                if dl == 0xFFFD:
                    env.append("restart")
                    break
                env.append([dl, arg])
            ch.env = env
        elif cmd == 0xD9:
            ch.release = self.u8(s)
        elif cmd == 0xD8:
            ch.vib_extent = self.u8(s) * 8
        elif cmd == 0xD7:
            ch.vib_rate = self.u8(s) * 32
        elif cmd == 0xE2:
            self.u8(s)
            ch.vib_extent = self.u8(s) * 8
            self.u8(s)
        elif cmd == 0xE1:
            self.u8(s)
            ch.vib_rate = self.u8(s) * 32
            self.u8(s)
        elif cmd == 0xE3:
            ch.vib_delay = self.u8(s) * 16
        elif cmd in (0xD6, 0xD0, 0xD1, 0xCA):
            self.u8(s)
        elif cmd == 0xD4:
            ch.reverb = self.u8(s)
        elif cmd == 0xD2:
            self.u8(s)
        elif cmd == 0xC6:
            i = self.u8(s)
            if i < len(self.banks):
                ch.bank = self.banks[i]
        elif cmd == 0xC7:
            v = self.u8(s)
            a = self.u16(s)
            self.d[a] = (ch.value + v) & 0xFF
        elif cmd in (0xC8, 0xC9, 0xCC):
            t = self.s8(s) if cmd != 0xC9 else self.u8(s)
            if cmd == 0xC8:
                ch.value -= t
            elif cmd == 0xCC:
                ch.value = t
            else:
                ch.value &= t
        elif cmd == 0xCB:
            a = self.u16(s) + ch.value
            ch.value = self.d[a]
        else:
            raise ValueError("unknown chan cmd %02x at %x" % (cmd, s.pc - 1))

    def chan_low(self, ch, s, cmd):
        hi, lo = cmd & 0xF0, cmd & 0x0F
        if hi == 0x00:
            layer = ch.layers[lo] if lo < 4 else None
            ch.value = 1 if (layer is None or not layer.enabled) else 0
        elif hi == 0x10:
            self.start_channel(lo, self.u16(s))
        elif hi == 0x20:
            if self.channels[lo]:
                self.channels[lo].enabled = False
        elif hi == 0x30:
            self.u8(s)
            self.u8(s)
        elif hi == 0x40:
            self.u8(s)
            ch.value = -1
        elif hi == 0x50:
            ch.value -= ch.io[lo]
        elif hi == 0x60:
            pass
        elif hi == 0x70:
            ch.io[lo] = ch.value
        elif hi == 0x80:
            ch.value = ch.io[lo]
            if lo < 4:
                ch.io[lo] = -1
        elif hi == 0x90:
            a = self.u16(s)
            if lo < 4:
                old = ch.layers[lo]
                if old and old.note:
                    old.note.release_now()
                ch.layers[lo] = Layer(ch, a)
        elif hi == 0xA0:
            if lo < 4 and ch.layers[lo]:
                if ch.layers[lo].note:
                    ch.layers[lo].note.release_now()
                ch.layers[lo] = None
        elif hi == 0xB0:
            if ch.value != -1 and lo < 4:
                t = ch.dyntable + 2 * ch.value
                ch.layers[lo] = Layer(ch, (self.d[t] << 8) | self.d[t + 1])
        else:
            raise ValueError("unknown chan low cmd %02x" % cmd)

    # --- layer script
    def decay(self, layer):
        if layer.note:
            rate = layer.adsr[1] if layer.adsr and layer.adsr[1] else layer.chan.release
            layer.note.release_now(rate)
            layer.note = None

    def layer_tick(self, ch, layer):
        if layer.delay > 1:
            layer.delay -= 1
            if not layer.stop and layer.delay <= layer.duration:
                self.decay(layer)
                layer.stop = True
            return
        if not layer.continuous:
            self.decay(layer)
        s = layer.s
        cmd = 0
        for _ in range(1000):
            cmd = self.u8(s)
            if cmd <= 0xC0:
                break
            if cmd == 0xFF:
                if not s.stack:
                    layer.enabled = False
                    self.decay(layer)
                    return
                s.ret()
            elif cmd == 0xFC:
                a = self.u16(s)
                s.stack.append([0, s.pc])
                s.pc = a
            elif cmd == 0xF8:
                s.loop(self.u8(s))
            elif cmd == 0xF7:
                s.loopend()
            elif cmd == 0xFB:
                s.pc = self.u16(s)
            elif cmd == 0xC1:
                v = self.u8(s)
                layer.vel2 = v * v
            elif cmd == 0xCA:
                layer.pan = self.u8(s) / 128.0
            elif cmd == 0xC2:
                layer.transpose = self.s8(s)
            elif cmd == 0xC9:
                layer.note_duration = self.u8(s)
            elif cmd in (0xC4, 0xC5):
                layer.continuous = cmd == 0xC4
                self.decay(layer)
            elif cmd == 0xC3:
                layer.short_pct = self.var(s)
            elif cmd == 0xC6:
                i = self.u8(s)
                if i < 127:
                    insts = ch.bank.instruments
                    inst = insts[min(i, len(insts) - 1)] if insts else None
                    layer.inst = inst
                    layer.adsr = (inst["env"], inst["release"]) if inst else None
            elif cmd == 0xC7:
                mode = self.u8(s)
                self.u8(s)
                if mode & 0x80:
                    self.u8(s)
                else:
                    self.var(s)
            elif cmd == 0xC8:
                pass
            else:
                hi = cmd & 0xF0
                if hi == 0xD0:
                    v = self.short_vel[cmd & 0xF]
                    layer.vel2 = v * v
                elif hi == 0xE0:
                    layer.note_duration = self.short_dur[cmd & 0xF]
        if cmd == 0xC0:
            layer.delay = self.var(s)
            layer.stop = True
            return
        layer.stop = False
        if ch.large:
            kind = cmd & 0xC0
            if kind == 0x00:
                pct = self.var(s)
                vel = self.u8(s)
                layer.note_duration = self.u8(s)
                layer.play_pct = pct
            elif kind == 0x40:
                pct = self.var(s)
                vel = self.u8(s)
                layer.note_duration = 0
                layer.play_pct = pct
            else:
                pct = layer.play_pct
                vel = self.u8(s)
                layer.note_duration = self.u8(s)
            layer.vel2 = vel * vel
        else:
            kind = cmd & 0xC0
            if kind == 0x00:
                pct = self.var(s)
                layer.play_pct = pct
            elif kind == 0x40:
                pct = layer.short_pct
            else:
                pct = layer.play_pct
        semitone = cmd & 0x3F
        layer.delay = pct
        layer.duration = layer.note_duration * pct // 256
        if ch.inst_or_wave is None:
            layer.stop = True
            return
        sound = None
        wave = None
        env, release, pan = ch.env, ch.release, layer.pan
        if ch.inst_or_wave == 0:
            k = semitone + ch.transpose + layer.transpose
            drums = ch.bank.drums
            if not drums:
                layer.stop = True
                return
            drum = drums[min(max(k, 0), len(drums) - 1)]
            if drum is None:
                layer.stop = True
                return
            sound, tuning = drum["sound"]
            freq = tuning
            env, release, pan = drum["env"], drum["release"], drum["pan"]
            layer.adsr = (env, release)
        else:
            k = semitone + self.transpose + ch.transpose + layer.transpose
            if k >= 0x80 or k < 0:
                layer.stop = True
                return
            if isinstance(ch.inst_or_wave, int) and ch.inst_or_wave >= 0x80:
                wave = synthetic_waves()[(ch.inst_or_wave - 0x80) % 4]
                freq = note_freq(k) * 1.0465 * 64 * 500 / RATE / 64 * 64 / 64
                freq = 523.25 * note_freq(k) * 64 / RATE
            else:
                inst = layer.inst or ch.inst
                if inst is None:
                    layer.stop = True
                    return
                snd = inst["sound_lo"] if k < inst["lo"] and inst["sound_lo"] else inst["sound_hi"] if k > inst["hi"] and inst["sound_hi"] else inst["sound"]
                if snd is None:
                    layer.stop = True
                    return
                sound, tuning = snd
                freq = note_freq(k) * tuning
                if layer.adsr:
                    env, release = layer.adsr
        vel = layer.vel2 / (127.0 * 127.0)
        final_pan = layer.pan * (1 - ch.pan_weight) + ch.pan * ch.pan_weight
        if ch.inst_or_wave == 0:
            final_pan = pan * (1 - ch.pan_weight) + ch.pan * ch.pan_weight
        if layer.continuous and layer.note and not layer.note.done:
            layer.note.freq = freq
            layer.note.vel = vel
            return
        self.decay(layer)
        note = Note(sound, wave, freq, env, release, vel, final_pan, ch, layer)
        layer.note = note
        self.notes.append(note)

    def update(self):
        self.updates += 1
        self.acc += self.tempo
        if self.acc >= 300:
            self.acc -= 300
            self.seq_tick()
            for ch in self.channels:
                if ch:
                    self.chan_tick(ch)

    def active(self):
        if not self.ended:
            return True
        return any(not n.done for n in self.notes)


# sound effects: output name -> (sound bank / player channel, sound id), as in the decomp's include/sounds.h
SFX = {
    "ui_hover": (7, 0x00),  # SOUND_MENU_CHANGE_SELECT
    "ui_open": (7, 0x02),  # SOUND_MENU_PAUSE
    "ui_close": (7, 0x01),  # SOUND_MENU_REVERSE_PAUSE
    "ui_click": (7, 0x11),  # SOUND_MENU_CLICK_FILE_SELECT
    "ui_message": (7, 0x04),  # SOUND_MENU_MESSAGE_APPEAR
    "coin": (3, 0x11),  # SOUND_GENERAL_COIN
    "coin_spurt": (3, 0x30),  # SOUND_GENERAL_COIN_SPURT
    "red_coin": (7, 0x28),  # SOUND_MENU_COLLECT_RED_COIN
    "one_up": (3, 0x58),  # SOUND_GENERAL_COLLECT_1UP
    "star_appears": (3, 0x57),  # SOUND_GENERAL_STAR_APPEARS
    "right_answer": (8, 0x6A),  # SOUND_GENERAL2_RIGHT_ANSWER
    "power_meter": (7, 0x0D),  # SOUND_MENU_POWER_METER
    "enter_pipe": (7, 0x16),  # SOUND_MENU_ENTER_PIPE
    "exit_pipe": (7, 0x17),  # SOUND_MENU_EXIT_PIPE
    "pound": (3, 0x44),  # SOUND_GENERAL_BIG_POUND
    "boing": (3, 0x6C),  # SOUND_GENERAL_BOING1
    "cannon_up": (3, 0x47),  # SOUND_GENERAL_CANNON_UP
    "swish": (3, 0x5C),  # SOUND_GENERAL_SWISH_AIR
    "hit": (0, 0x44),  # SOUND_ACTION_HIT
    "spin": (0, 0x37),  # SOUND_ACTION_SPIN
    "throw": (0, 0x35),  # SOUND_ACTION_THROW
    "explosion": (8, 0x2E),  # SOUND_GENERAL2_BOBOMB_EXPLOSION
    "big_explosion": (3, 0x2F),  # SOUND_GENERAL_BOWSER_BOMB_EXPLOSION
    "flame": (5, 0x55),  # SOUND_OBJ_FLAME_BLOWN
    "enemy_die": (5, 0x2C),  # SOUND_OBJ_DEFAULT_DEATH
    "enemy_shrink": (5, 0x74),  # SOUND_OBJ_ENEMY_DEFEAT_SHRINK
    "stomped": (5, 0x30),  # SOUND_OBJ_STOMPED
    "goomba_alert": (5, 0x2F),  # SOUND_OBJ_GOOMBA_ALERT
    "boo_laugh": (5, 0x0B),  # SOUND_OBJ_BOO_LAUGH_SHORT
    "thwomp": (5, 0x0C),  # SOUND_OBJ_THWOMP
    "king_bobomb": (5, 0x16),  # SOUND_OBJ_KING_BOBOMB
    "bowser_laugh": (5, 0x38),  # SOUND_OBJ_BOWSER_LAUGH
    "bowser_roar": (9, 0x04),  # SOUND_OBJ2_BOWSER_ROAR
}

# voice clips played straight from their samples: output name -> (sample bank, sample)
VOICES = {
    "voice_here_we_go": ("sfx_mario", "0C_mario_here_we_go"),
    "voice_yahoo": ("sfx_mario", "04_mario_yahoo"),
    "voice_lets_a_go": ("sfx_mario", "1A_mario_lets_a_go"),
    "voice_yippee": ("sfx_mario", "19_mario_yippee"),
    "voice_waha": ("sfx_mario", "18_mario_waha"),
    "voice_game_over": ("sfx_mario", "11_mario_game_over"),
    "voice_so_longa_bowser": ("sfx_mario", "16_mario_so_longa_bowser"),
    "voice_mama_mia": ("sfx_mario_peach", "0A_mario_mama_mia"),
    "voice_okey_dokey": ("sfx_mario_peach", "0B_mario_okey_dokey"),
    "voice_its_a_me": ("sfx_mario_peach", "07_mario_its_a_me_mario"),
    "voice_thank_you": ("sfx_mario_peach", "0D_mario_thank_you_playing_my_game"),
    "voice_power_of_the_stars": ("sfx_mario_peach", "10_peach_power_of_the_stars"),
}

SOUND_PLAYER_BANKS = ["00", "01_terrain", "02_water", "03", "04", "05", "06", "07", "08_mario", "09", "0A_mario_peach"]


def sound_player_data(rom):
    """The sound player sequence (sequence 0), found in the ROM by its opening commands."""
    i = rom.find(b"\xd3\x60\xd5\x00\xdb\x7f\xdd\x78\xd7\x03\xff")
    if i < 0:
        raise RuntimeError("sound player not found in the ROM")
    return rom[i : i + 0x4000]


def render_sfx(data, banks, channel, sound_id, max_seconds=4.0):
    """Plays one sound effect the way the game asks for it: io port 4 = sound id, io port 0 = play."""
    player = Player(data, banks)
    for _ in range(8):
        player.update()
    ch = player.channels[channel]
    ch.io[4] = sound_id
    ch.io[0] = 1
    n_updates = int(max_seconds * UPDATES_PER_SECOND)
    out = np.zeros(int(n_updates * SAMPLES_PER_UPDATE) + 1024, np.float32)
    t = 0.0
    started = False
    quiet = 0
    for _ in range(n_updates):
        player.update()
        start = int(t)
        t += SAMPLES_PER_UPDATE
        n = int(t) - start
        alive = []
        for note in player.notes:
            if note.done:
                continue
            o = note.render(n, note.chan.freq_scale)
            if o is not None:
                out[start : start + n] += o
            if not note.done:
                alive.append(note)
        player.notes = alive
        started = started or bool(alive)
        quiet = quiet + 1 if started and not alive else 0
        if quiet > 24:
            break
    end = int(t)
    out = out[:end]
    nz = np.nonzero(np.abs(out) > 1e-4)[0]
    if len(nz) == 0:
        return None
    out = out[nz[0] : nz[-1] + 1]
    return out


def reverb(left, right, amount=0.22):
    out_l, out_r = left.copy(), right.copy()
    for delay, gain in ((1557, 0.5), (1617, 0.48), (1491, 0.46), (1422, 0.44)):
        for src, dst in ((left, out_l), (right, out_r)):
            buf = np.zeros_like(src)
            buf[delay:] = src[:-delay] * gain
            # a few echoes of each comb filter
            echo = buf.copy()
            acc = buf.copy()
            for _ in range(5):
                echo = np.concatenate([np.zeros(delay, np.float32), echo[:-delay]]) * gain
                acc += echo
            dst += acc * amount * 0.5
    return out_l, out_r


def render(seq_path, banks, seconds):
    data = open(seq_path, "rb").read()
    player = Player(data, banks)
    total = int(seconds * UPDATES_PER_SECOND)
    n_samples = int(total * SAMPLES_PER_UPDATE) + RATE
    left = np.zeros(n_samples, np.float32)
    right = np.zeros(n_samples, np.float32)
    wet = np.zeros(n_samples, np.float32)
    t = 0.0
    stop_at = total
    for u in range(total):
        if u >= stop_at:
            break
        player.update()
        if player.loop_at is not None and stop_at == total:
            # one full pass, then let the notes ring out briefly
            stop_at = min(total, player.loop_at + UPDATES_PER_SECOND // 2)
        start = int(t)
        t += SAMPLES_PER_UPDATE
        n = int(t) - start
        alive = []
        for note in player.notes:
            if note.done:
                continue
            ch = note.chan
            vib = 1.0
            if ch.vib_extent:
                if note.vib_delay > 0:
                    note.vib_delay -= 1
                else:
                    note.vib_time += ch.vib_rate
                    pc = 127 * math.sin(2 * math.pi * ((note.vib_time >> 10) & 63) / 64)
                    vib = 1.0 + ch.vib_extent / 4096.0 * (2.0 ** (pc / 127.0) - 1.0)
            out = note.render(n, ch.freq_scale * vib)
            if out is not None:
                pan = min(max(note.pan, 0.0), 1.0)
                left[start : start + n] += out * math.cos(pan * math.pi / 2)
                right[start : start + n] += out * math.sin(pan * math.pi / 2)
                if ch.reverb:
                    wet[start : start + n] += out * (ch.reverb / 127.0)
            if not note.done:
                alive.append(note)
        player.notes = alive
        if not player.active():
            break
    end = int(t) + RATE // 4
    left, right, wet = left[:end], right[:end], wet[:end]
    wl, wr = reverb(wet, wet)
    left += (wl - wet) * 0.6
    right += (wr - wet) * 0.6
    loop = player.loop_at is not None
    return left, right, loop


def normalize(left, right, fade=False):
    peak = max(np.abs(left).max(), np.abs(right).max(), 1e-6)
    gain = 0.89 / peak
    left, right = left * gain, right * gain
    if fade:
        n = min(len(left), RATE * 2)
        ramp = np.linspace(1, 0, n, dtype=np.float32)
        left[-n:] *= ramp
        right[-n:] *= ramp
    return left, right


def write_audio(path_base, left, right):
    pcm = (np.clip(np.stack([left, right], axis=1), -1, 1) * 32767).astype("<i2")
    wav = path_base + ".wav"
    with open(wav, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + pcm.nbytes) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 2, RATE, RATE * 4, 4, 16))
        f.write(b"data" + struct.pack("<I", pcm.nbytes) + pcm.tobytes())
    if shutil.which("ffmpeg"):
        ogg = path_base + ".ogg"
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", ogg], check=True)
        os.remove(wav)
        return ogg
    return wav


# Roblox limits how many audio files an account can upload, so the clips are packed into a few long files that
# the game plays a region of. Each music file stays under Roblox's 7 minute limit.
SHEETS = {
    "sm64_music_1": ["music_lobby", "music_meadow", "music_desert", "music_frost"],
    "sm64_music_2": ["music_magma", "music_starcastle", "music_boss", "music_summon"],
    "sm64_sfx": None,  # everything else
}
GAP = 0.3


def write_sheets(out_dir, clips, luau_dir):
    index = {}
    used = set()
    for sheet, names in SHEETS.items():
        if names is None:
            names = [n for n in clips if n not in used]
        names = [n for n in names if n in clips]
        if not names:
            continue
        parts_l, parts_r = [], []
        t = 0
        for n in names:
            used.add(n)
            left, right = clips[n]
            index[n] = (sheet, t / RATE, len(left) / RATE)
            gap = np.zeros(int(GAP * RATE), np.float32)
            parts_l += [left, gap]
            parts_r += [right, gap]
            t += len(left) + len(gap)
        path = write_audio(os.path.join(out_dir, sheet), np.concatenate(parts_l), np.concatenate(parts_r))
        print("%-14s %6.1fs  %s" % (sheet, t / RATE, path))
    if luau_dir:
        os.makedirs(luau_dir, exist_ok=True)
        with open(os.path.join(luau_dir, "Audio.luau"), "w") as f:
            f.write("-- generated by tools/sm64_import/sm64_audio.py from your own ROM; do not share\n")
            f.write("-- Upload the files named below (from the audio output folder) to Roblox and put their ids here.\n")
            f.write("return {\n\tids = {\n")
            for sheet in SHEETS:
                if any(v[0] == sheet for v in index.values()):
                    f.write("\t\t%s = 0,\n" % sheet)
            f.write("\t},\n\t-- clip name = { file, start second, length in seconds }\n\tclips = {\n")
            for n, (sheet, start, length) in index.items():
                f.write('\t\t%s = { "%s", %.4f, %.4f },\n' % (n, sheet, start, length))
            f.write("\t},\n}\n")
    return index


def main():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", required=True)
    ap.add_argument("--sm64", help="n64decomp/sm64 source folder (downloaded if omitted)")
    ap.add_argument("--out", default="sm64_audio")
    ap.add_argument("--luau", help="also write the clip index for the game (Audio.luau) into this folder")
    ap.add_argument("--separate", action="store_true", help="also write every clip as its own file")
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()
    from sm64_to_roblox import find_sm64

    root = os.path.abspath(find_sm64(args.sm64))
    if not os.path.isdir(os.path.join(root, "sound", "sequences", "us")):
        print("Extracting the ROM's sound data with the decomp's extract_assets.py ...")
        shutil.copy(args.rom, os.path.join(root, "baserom.us.z64"))
        subprocess.run([sys.executable, "extract_assets.py", "us"], cwd=root, check=True)
    rom = open(args.rom, "rb").read()
    if rom[:4] == b"\x37\x80\x40\x12":  # .v64 byte order
        rom = b"".join(rom[i + 1 : i + 2] + rom[i : i + 1] for i in range(0, len(rom), 2))
    seq_banks = json.load(open(os.path.join(root, "sound", "sequences.json")))
    os.makedirs(args.out, exist_ok=True)
    bank_cache = {}
    clips = {}

    def bank(b):
        if b not in bank_cache:
            bank_cache[b] = Bank(root, b)
        return bank_cache[b]

    for name, (seq, seconds) in TRACKS.items():
        if args.only and name not in args.only:
            continue
        entry = seq_banks[seq]
        names = entry["banks"] if isinstance(entry, dict) else entry
        left, right, looped = render(os.path.join(root, "sound", "sequences", "us", seq + ".m64"), [bank(b) for b in names], seconds)
        clips[name] = normalize(left, right, fade=not looped and len(left) >= seconds * RATE)
        print("%-24s %-28s %6.2fs" % (name, seq, len(left) / RATE))

    data = sound_player_data(rom)
    sp_banks = [bank(b) for b in SOUND_PLAYER_BANKS]
    for name, (channel, sound_id) in SFX.items():
        if args.only and name not in args.only:
            continue
        mono = render_sfx(data, sp_banks, channel, sound_id)
        if mono is None:
            print("%-24s (silent, skipped)" % name)
            continue
        clips[name] = normalize(mono, mono.copy())
        print("%-24s sound %d/%02X %18s %6.2fs" % (name, channel, sound_id, "", len(mono) / RATE))
    for name, (sbank, sample_name) in VOICES.items():
        if args.only and name not in args.only:
            continue
        sample = Sample(os.path.join(root, "sound", "samples", sbank, sample_name + ".aiff"))
        # resample from the sample's own rate to 32 kHz
        n = int(len(sample.pcm) / sample.tuning)
        mono = np.interp(np.arange(n) * sample.tuning, np.arange(len(sample.pcm)), sample.pcm).astype(np.float32)
        clips[name] = normalize(mono, mono.copy())
        print("%-24s %-28s %6.2fs" % (name, sample_name, len(mono) / RATE))

    if args.separate:
        for name, (left, right) in clips.items():
            write_audio(os.path.join(args.out, name), left, right)
    write_sheets(args.out, clips, args.luau)


if __name__ == "__main__":
    main()
