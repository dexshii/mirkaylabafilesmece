#!/usr/bin/env python3
"""Turn Super Mario 64 characters into 3D model files for Roblox Studio's 3D Importer.

Runs on your own computer with your own ROM; nothing from the game is stored in this repository.

    python sm64_to_roblox.py --rom "Super Mario 64 (USA).z64"

It needs:
  * a Super Mario 64 (USA) ROM (.z64, big-endian; the sha1 is checked)
  * the n64decomp/sm64 source (the model geometry is read from its C files). Pass --sm64 <folder>, or let the
    script download it from GitHub once into ./sm64-src.

For every unit and enemy in the game it writes, into ./sm64_models:
  <id>.glb      the model with its texture inside (import this one)
  <id>.obj      the same model as OBJ, with <id>.mtl and <id>.png
  set_names.lua a snippet for Studio's command bar that names the imported models (Mario, Bowser, ...)

Each model is posed on the first frame of one of its animations, with lights and vertex colours baked into a
single texture, and faces -Z like Roblox models do. Only the Python 3 standard library is used.
"""

import argparse
import hashlib
import io
import json
import math
import os
import re
import struct
import sys
import urllib.request
import zipfile
import zlib

US_SHA1 = "9bef1128717f958171a4afac3ed78ee2bb4e86ce"
SM64_ZIP = "https://github.com/n64decomp/sm64/archive/refs/heads/master.zip"

# game id -> (geo layout, animation, display name). The animation is an animation table name or the start of one
# (optionally ":n" for its n-th entry), an animation name (Mario's anim_C3 is his idle), or None.
ACTORS = {
    # units
    "mushling": ("goomba_geo", "goomba_seg8_anims_", "Goomba"),
    "fusebuddy": ("bobomb_buddy_geo", "bobomb_seg8_anims_", "Bob-omb Buddy"),
    "shellback": ("koopa_with_shell_geo", "koopa_seg6_anims_", "Koopa Troopa"),
    "buzzwing": ("flyguy_geo", "flyguy_seg8_anims_", "Fly Guy"),
    "spooky": ("boo_geo", None, "Boo"),
    "cloudrider": ("enemy_lakitu_geo", "lakitu_enemy_seg5_anims_", "Lakitu"),
    "shroombanker": ("toad_geo", "toad_seg6_anims_", "Toad"),
    "flamebloom": ("piranha_plant_geo", "piranha_plant_seg6_anims_", "Piranha Plant"),
    "stoneslammer": ("whomp_geo", "whomp_seg6_anims_", "Whomp"),
    "chainchomper": ("chain_chomp_geo", "chain_chomp_seg6_anims_", "Chain Chomp"),
    "starsage": ("hoot_geo", "hoot_seg5_anims_", "Hoot"),
    "captaincomet": ("mario_geo", "anim_C3", "Mario"),
    "infernodrake": ("bowser_geo", "bowser_seg6_anims_:12", "Bowser"),
    "starprincess": ("peach_geo", "peach_seg5_anims_", "Princess Peach"),
    "webskitter": ("scuttlebug_geo", "scuttlebug_seg6_anims_", "Scuttlebug"),
    "puffshot": ("snufit_geo", None, "Snufit"),
    "crusherblock": ("thwomp_geo", None, "Thwomp"),
    "voltorb": ("dAmpGeo", None, "Amp"),
    "burrowbomber": ("monty_mole_geo", "monty_mole_seg5_anims_", "Monty Mole"),
    "bananabandit": ("ukiki_geo", "ukiki_seg5_anims_", "Ukiki"),
    "grapplebot": ("chuckya_geo", "chuckya_seg8_anims_", "Chuckya"),
    "dinopal": ("yoshi_geo", "yoshi_seg5_anims_", "Yoshi"),
    # enemies
    "grumble": ("goomba_geo", "goomba_seg8_anims_", "Goomba"),
    "sprinter": ("spiny_geo", "spiny_seg5_anims_", "Spiny"),
    "shellguard": ("bully_geo", "bully_seg5_anims_", "Bully"),
    "splitter": ("black_bobomb_geo", "bobomb_seg8_anims_", "Bob-omb"),
    "minibomb": ("black_bobomb_geo", "bobomb_seg8_anims_", "Mini Bob-omb"),
    "flutter": ("flyguy_geo", "flyguy_seg8_anims_", "Fly Guy"),
    "phantom": ("boo_geo", None, "Boo"),
    "skyray": ("swoop_geo", "swoop_seg6_anims_", "Swoop"),
    "kinggrumble": ("king_bobomb_geo", "king_bobomb_seg5_anims_", "King Bob-omb"),
    "sandwyvern": ("klepto_geo", "klepto_seg5_anims_", "Klepto"),
    "frostgolem": ("chilly_chief_big_geo", "chilly_chief_seg6_anims_", "Chill Bully"),
    "lavatitan": ("bully_boss_geo", "bully_seg5_anims_", "Big Bully"),
    "shadowmonarch": ("bowser_geo", "bowser_seg6_anims_:12", "Bowser"),
}

# display lists left out of a model: parts the game hides with code (Mario's wings show only with the Wing Cap)
SKIP_DLS = {"mario_cap_wings"}

# SM64 draws display lists layer by layer (opaque first), keeping traversal order inside a layer
LAYERS = {
    "LAYER_FORCE": 0, "LAYER_OPAQUE": 1, "LAYER_OPAQUE_DECAL": 2, "LAYER_OPAQUE_INTER": 3,
    "LAYER_ALPHA": 4, "LAYER_TRANSPARENT": 5, "LAYER_TRANSPARENT_DECAL": 6, "LAYER_TRANSPARENT_INTER": 7,
}

GBI = {
    "G_ON": 1, "G_OFF": 0, "G_TX_RENDERTILE": 0, "G_TX_LOADTILE": 7,
    "G_TX_WRAP": 0, "G_TX_NOMIRROR": 0, "G_TX_MIRROR": 1, "G_TX_CLAMP": 2, "G_TX_NOMASK": 0, "G_TX_NOLOD": 0,
    "G_IM_FMT_RGBA": 0, "G_IM_FMT_YUV": 1, "G_IM_FMT_CI": 2, "G_IM_FMT_IA": 3, "G_IM_FMT_I": 4,
    "G_IM_SIZ_4b": 0, "G_IM_SIZ_8b": 1, "G_IM_SIZ_16b": 2, "G_IM_SIZ_32b": 3,
    "G_IM_SIZ_4b_BYTES": 0, "G_IM_SIZ_8b_BYTES": 1, "G_IM_SIZ_16b_BYTES": 2, "G_IM_SIZ_32b_BYTES": 4,
    "G_TEXTURE_IMAGE_FRAC": 2, "G_LIGHTING": 0x20000, "G_TEXTURE_GEN": 0x40000, "G_SHADE": 0x4,
    "G_SHADING_SMOOTH": 0x200, "G_CULL_BACK": 0x2000, "G_CULL_FRONT": 0x1000, "G_FOG": 0x10000,
    "G_ZBUFFER": 0x1, "G_TEXTURE_GEN_LINEAR": 0x80000, "G_LOD": 0x100000, "NULL": 0,
}
GBI.update(LAYERS)


# ============================================================ small helpers

class Lookup(dict):
    """Names the C code uses that we don't know evaluate to 0 (macros like CALC_DXT are made callable)."""

    def __missing__(self, key):
        return Zero()


class Zero(int):
    def __new__(cls):
        return int.__new__(cls, 0)

    def __call__(self, *args):
        return 0


def c_eval(expr):
    expr = expr.strip()
    if not expr:
        return 0
    expr = expr.replace("/", "//")
    try:
        return int(eval(expr, {"__builtins__": {}}, Lookup(GBI)))
    except Exception:
        return 0


def split_args(s):
    """Split a C argument list on top-level commas."""
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    tail = "".join(cur).strip()
    if tail:
        out.append(tail)
    return out


def calls(body):
    """Yield (name, args) for each top-level macro call like gsSPVertex(...) in an initializer body."""
    i, n = 0, len(body)
    pat = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(")
    while i < n:
        m = pat.search(body, i)
        if not m:
            return
        depth, j = 1, m.end()
        while j < n and depth:
            if body[j] == "(":
                depth += 1
            elif body[j] == ")":
                depth -= 1
            j += 1
        yield m.group(1), split_args(body[m.end():j - 1])
        i = j


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


# ============================================================ the decomp's C data

class Source:
    def __init__(self, root):
        self.root = root
        self.lights, self.textures, self.vtx, self.gfx, self.geo = {}, {}, {}, {}, {}
        self.anims, self.anim_tables, self.s16, self.u16 = {}, {}, {}, {}
        files = []
        for base in ("actors", os.path.join("assets", "anims")):
            for dirpath, _, names in os.walk(os.path.join(root, base)):
                for name in names:
                    if name.endswith(".c"):
                        files.append(os.path.join(dirpath, name))
        for path in files:
            with open(path, encoding="utf-8", errors="replace") as f:
                self.parse(strip_comments(f.read()))

    def parse(self, text):
        for m in re.finditer(r"Lights1\s+(\w+)\s*=\s*gdSPDefLights1\(([^)]*)\)", text):
            self.lights[m.group(1)] = [c_eval(a) for a in split_args(m.group(2))]
        for m in re.finditer(r"Texture\s+(\w+)\s*\[\]\s*=\s*\{\s*#include\s*\"([^\"]+)\"", text):
            self.textures[m.group(1)] = m.group(2).replace(".inc.c", ".png")
        for m in re.finditer(r"Vtx\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\n\};", text, re.S):
            verts = []
            for v in re.finditer(r"\{\{\{([^}]*)\},([^,]*),\{([^}]*)\},\{([^}]*)\}\}\}", m.group(2).replace(" ", "").replace("\n", "")):
                pos = [c_eval(a) for a in v.group(1).split(",")]
                st = [c_eval(a) for a in v.group(3).split(",")]
                col = [c_eval(a) for a in v.group(4).split(",")]
                verts.append((pos, st, col))
            self.vtx[m.group(1)] = verts
        for m in re.finditer(r"Gfx\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\n\};", text, re.S):
            self.gfx[m.group(1)] = list(calls(m.group(2)))
        for m in re.finditer(r"GeoLayout\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\n\};", text, re.S):
            self.geo[m.group(1)] = list(calls(m.group(2)))
        for m in re.finditer(r"struct\s+Animation\s+(\w+)\s*(\[\])?\s*=\s*\{(.*?)\};", text, re.S):
            self.anims[m.group(1)] = split_args(m.group(3))
        for m in re.finditer(r"struct\s+Animation\s*\*\s*const\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\};", text, re.S):
            self.anim_tables[m.group(1)] = [a.strip().lstrip("&") for a in split_args(m.group(2))]
        for m in re.finditer(r"s16\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\};", text, re.S):
            self.s16[m.group(1)] = [to_s16(c_eval(a)) for a in split_args(m.group(2))]
        for m in re.finditer(r"u16\s+(\w+)\s*\[\]\s*=\s*\{(.*?)\};", text, re.S):
            self.u16[m.group(1)] = [c_eval(a) & 0xFFFF for a in split_args(m.group(2))]

    def animation(self, name):
        """(flags, values, index) of an animation, given its own name or an animation table's name."""
        if name is None:
            return None
        pick = 0
        if ":" in name:  # "table:3" = the fourth animation of a table
            name, n = name.split(":")
            pick = int(n)
        if name not in self.anim_tables and name not in self.anims:
            # accept a unique prefix of a table name (the exact suffix varies between decomp versions)
            matches = sorted(k for k in self.anim_tables if k.startswith(name))
            if matches:
                name = matches[0]
        if name in self.anim_tables:
            entries = [a for a in self.anim_tables[name] if a and a != "NULL"]
            if not entries:
                return None
            name = entries[min(pick, len(entries) - 1)]
        fields = self.anims.get(name)
        if not fields:
            return None
        flags = c_eval(fields[0])
        values = self.s16.get(fields[6].strip(), [])
        index = self.u16.get(fields[7].strip(), [])
        return flags, values, index


def to_s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v >= 0x8000 else v


# ============================================================ ROM textures

def mio0_decode(data, offset):
    if data[offset:offset + 4] != b"MIO0":
        raise ValueError("not an MIO0 block at %#x" % offset)
    size, comp, raw = struct.unpack(">III", data[offset + 4:offset + 16])
    out = bytearray()
    bits_pos = offset + 16
    comp_pos = offset + comp
    raw_pos = offset + raw
    bit_word, bits_left = 0, 0
    while len(out) < size:
        if bits_left == 0:
            bit_word = struct.unpack(">I", data[bits_pos:bits_pos + 4])[0]
            bits_pos += 4
            bits_left = 32
        bit = bit_word & 0x80000000
        bit_word = (bit_word << 1) & 0xFFFFFFFF
        bits_left -= 1
        if bit:
            out.append(data[raw_pos])
            raw_pos += 1
        else:
            pair = struct.unpack(">H", data[comp_pos:comp_pos + 2])[0]
            comp_pos += 2
            length = (pair >> 12) + 3
            back = (pair & 0xFFF) + 1
            for _ in range(length):
                out.append(out[-back])
    return bytes(out)


def decode_texture(raw, fmt, w, h):
    """N64 texture bytes -> list of rows of (r, g, b, a)."""
    px = []
    if fmt == "rgba16":
        for i in range(w * h):
            v = (raw[i * 2] << 8) | raw[i * 2 + 1]
            px.append((((v >> 11) & 31) * 255 // 31, ((v >> 6) & 31) * 255 // 31, ((v >> 1) & 31) * 255 // 31, 255 if v & 1 else 0))
    elif fmt == "rgba32":
        for i in range(w * h):
            px.append(tuple(raw[i * 4:i * 4 + 4]))
    elif fmt == "ia16":
        for i in range(w * h):
            px.append((raw[i * 2],) * 3 + (raw[i * 2 + 1],))
    elif fmt == "ia8":
        for i in range(w * h):
            v = raw[i]
            px.append(((v >> 4) * 17,) * 3 + ((v & 15) * 17,))
    elif fmt == "ia4":
        for i in range(w * h):
            v = (raw[i // 2] >> (4 if i % 2 == 0 else 0)) & 15
            px.append(((v >> 1) * 255 // 7,) * 3 + (255 if v & 1 else 0,))
    elif fmt == "i8":
        for i in range(w * h):
            px.append((raw[i],) * 3 + (255,))
    elif fmt == "i4":
        for i in range(w * h):
            v = (raw[i // 2] >> (4 if i % 2 == 0 else 0)) & 15
            px.append((v * 17,) * 3 + (255,))
    else:
        px = [(255, 0, 255, 255)] * (w * h)
    return [px[r * w:(r + 1) * w] for r in range(h)]


class Textures:
    def __init__(self, rom, assets):
        self.rom = rom
        self.assets = assets
        self.mio0 = {}
        self.cache = {}

    def get(self, path):
        """(width, height, rows) of a texture by its asset path, or a magenta square if unknown."""
        if path in self.cache:
            return self.cache[path]
        entry = self.assets.get(path)
        result = (4, 4, [[(255, 0, 255, 255)] * 4 for _ in range(4)])
        if entry and len(entry) >= 4:
            w, h, size, places = entry[0], entry[1], entry[2], entry[3]
            pos = places.get("us")
            if pos:
                if len(pos) == 2:
                    block = self.mio0.get(pos[0])
                    if block is None:
                        block = self.mio0[pos[0]] = mio0_decode(self.rom, pos[0])
                    raw = block[pos[1]:pos[1] + size]
                else:
                    raw = self.rom[pos[0]:pos[0] + size]
                fmt = path.split(".")[-2]
                result = (w, h, decode_texture(raw, fmt, w, h))
        self.cache[path] = result
        return result


# ============================================================ matrices (SM64 row-vector convention: v' = v * M)

def mat_identity():
    return [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def angle(units):
    return units * math.pi / 32768.0


def rot_xyz_translate(t, r):
    sx, cx = math.sin(angle(r[0])), math.cos(angle(r[0]))
    sy, cy = math.sin(angle(r[1])), math.cos(angle(r[1]))
    sz, cz = math.sin(angle(r[2])), math.cos(angle(r[2]))
    return [
        [cy * cz, cy * sz, -sy, 0],
        [sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy, 0],
        [cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy, 0],
        [t[0], t[1], t[2], 1],
    ]


def rot_zxy_translate(t, r):
    sx, cx = math.sin(angle(r[0])), math.cos(angle(r[0]))
    sy, cy = math.sin(angle(r[1])), math.cos(angle(r[1]))
    sz, cz = math.sin(angle(r[2])), math.cos(angle(r[2]))
    return [
        [cy * cz + sx * sy * sz, cx * sz, -sy * cz + sx * cy * sz, 0],
        [-cy * sz + sx * sy * cz, cx * cz, sy * sz + sx * cy * cz, 0],
        [cx * sy, -sx, cx * cy, 0],
        [t[0], t[1], t[2], 1],
    ]


def transform(v, m):
    return [v[0] * m[0][j] + v[1] * m[1][j] + v[2] * m[2][j] + m[3][j] for j in range(3)]


def degrees_to_units(d):
    return d * 32768.0 / 180.0


# ============================================================ geo layouts

class Node:
    def __init__(self, cmd, args):
        self.cmd, self.args, self.children = cmd, args, []


def build_tree(src, name, depth=0):
    """A geo layout as a list of top-level nodes; branches are inlined."""
    if depth > 16:
        return []
    cmds = src.geo.get(name)
    if cmds is None:
        raise KeyError("geo layout %s not found" % name)
    root = Node("ROOT", [])
    # like geo_layout.c: OPEN_NODE makes the last node created at the current depth the parent, even after a
    # CLOSE_NODE (a layout can reopen the same node twice)
    stack = [root]
    last_at = {}
    for cmd, args in cmds:
        if cmd == "GEO_OPEN_NODE":
            stack.append(last_at.get(len(stack), stack[-1]))
        elif cmd == "GEO_CLOSE_NODE":
            if len(stack) > 1:
                last_at.pop(len(stack), None)
                stack.pop()
        elif cmd in ("GEO_RETURN", "GEO_END"):
            break
        elif cmd in ("GEO_BRANCH", "GEO_BRANCH_AND_LINK"):
            target = args[-1].strip()
            for n in build_tree(src, target, depth + 1):
                stack[-1].children.append(n)
                last_at[len(stack)] = n
            if cmd == "GEO_BRANCH" and c_eval(args[0]) == 0:
                break
        else:
            node = Node(cmd, args)
            stack[-1].children.append(node)
            last_at[len(stack)] = node
    return root.children


class Walker:
    """Walks a geo tree like SM64's renderer, collecting (layer, display list, matrix, billboard)."""

    def __init__(self, src, anim):
        self.src = src
        self.draws = []
        self.anim = anim
        self.attr = 0  # position in the animation index list
        self.anim_type = None
        if anim:
            flags = anim[0]
            # as in geo_set_animation_globals: ANIM_FLAG_HOR_TRANS (1 << 3) keeps only the vertical translation,
            # ANIM_FLAG_VERT_TRANS (1 << 4) only the lateral one, ANIM_FLAG_6 none
            if flags & (1 << 3):
                self.anim_type = "vertical"
            elif flags & (1 << 4):
                self.anim_type = "lateral"
            elif flags & (1 << 6):
                self.anim_type = "none"
            else:
                self.anim_type = "translation"

    def channel(self):
        _, values, index = self.anim
        if self.attr + 1 >= len(index):
            return 0
        count, offset = index[self.attr], index[self.attr + 1]
        self.attr += 2
        i = offset  # frame 0
        if count == 0:
            return 0
        return values[i] if i < len(values) else 0

    def add_dl(self, layer, dl, m, billboard=False):
        if dl and dl not in ("NULL", "0") and dl not in SKIP_DLS:
            self.draws.append((layer, dl, m, billboard))

    def walk(self, nodes, m):
        # render range: keep only the closest level of detail
        ranges = [n for n in nodes if n.cmd == "GEO_RENDER_RANGE"]
        best = None
        if ranges:
            best = min(ranges, key=lambda n: c_eval(n.args[0]))
        for n in nodes:
            if n.cmd == "GEO_RENDER_RANGE" and n is not best:
                continue
            self.visit(n, m)

    def visit(self, n, m):
        cmd, a = n.cmd, n.args
        if cmd == "GEO_SWITCH_CASE":
            if n.children:
                self.visit(n.children[0], m)
            return
        if cmd in ("GEO_ASM", "GEO_HELD_OBJECT", "GEO_RENDER_OBJ", "GEO_BACKGROUND", "GEO_CAMERA"):
            self.walk(n.children, m)
            return
        if cmd == "GEO_ANIMATED_PART":
            layer = c_eval(a[0])
            t = [c_eval(a[1]), c_eval(a[2]), c_eval(a[3])]
            r = [0, 0, 0]
            if self.anim:
                if self.anim_type == "translation":
                    for i in range(3):
                        self.channel()  # root motion is ignored: the model stays at the origin
                    self.anim_type = "rotation"
                elif self.anim_type == "lateral":
                    self.channel()
                    self.attr += 2
                    self.channel()
                    self.anim_type = "rotation"
                elif self.anim_type == "vertical":
                    self.attr += 2
                    self.channel()
                    self.attr += 2
                    self.anim_type = "rotation"
                elif self.anim_type == "none":
                    self.attr += 6
                    self.anim_type = "rotation"
                if self.anim_type == "rotation":
                    r = [self.channel(), self.channel(), self.channel()]
            mm = mat_mul(rot_xyz_translate(t, r), m)
            self.add_dl(layer, a[4].strip(), mm)
            self.walk(n.children, mm)
            return
        if cmd in ("GEO_SCALE", "GEO_SCALE_WITH_DL"):
            s = c_eval(a[1]) / 65536.0
            sm = [[s, 0, 0, 0], [0, s, 0, 0], [0, 0, s, 0], [0, 0, 0, 1]]
            mm = mat_mul(sm, m)
            if cmd == "GEO_SCALE_WITH_DL":
                self.add_dl(c_eval(a[0]), a[2].strip(), mm)
            self.walk(n.children, mm)
            return
        if cmd in ("GEO_TRANSLATE_ROTATE", "GEO_TRANSLATE_ROTATE_WITH_DL"):
            t = [c_eval(a[1]), c_eval(a[2]), c_eval(a[3])]
            r = [degrees_to_units(c_eval(a[i])) for i in (4, 5, 6)]
            mm = mat_mul(rot_zxy_translate(t, r), m)
            if cmd.endswith("WITH_DL"):
                self.add_dl(c_eval(a[0]), a[7].strip(), mm)
            self.walk(n.children, mm)
            return
        if cmd in ("GEO_TRANSLATE_NODE", "GEO_TRANSLATE_NODE_WITH_DL", "GEO_TRANSLATE", "GEO_TRANSLATE_WITH_DL"):
            t = [c_eval(a[1]), c_eval(a[2]), c_eval(a[3])]
            mm = mat_mul(rot_xyz_translate(t, [0, 0, 0]), m)
            if cmd.endswith("WITH_DL"):
                self.add_dl(c_eval(a[0]), a[4].strip(), mm)
            self.walk(n.children, mm)
            return
        if cmd in ("GEO_ROTATION_NODE", "GEO_ROTATION_NODE_WITH_DL", "GEO_ROTATE", "GEO_ROTATE_WITH_DL"):
            r = [degrees_to_units(c_eval(a[i])) for i in (1, 2, 3)]
            mm = mat_mul(rot_zxy_translate([0, 0, 0], r), m)
            if cmd.endswith("WITH_DL"):
                self.add_dl(c_eval(a[0]), a[4].strip(), mm)
            self.walk(n.children, mm)
            return
        if cmd in ("GEO_BILLBOARD", "GEO_BILLBOARD_WITH_PARAMS", "GEO_BILLBOARD_WITH_PARAMS_AND_DL"):
            # billboards face the camera at unit scale; for a still model: face front, keep the parent's position
            t = [0, 0, 0]
            if cmd != "GEO_BILLBOARD":
                t = [c_eval(a[1]), c_eval(a[2]), c_eval(a[3])]
            pos = transform(t, m)
            mm = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [pos[0], pos[1], pos[2], 1]]
            if cmd.endswith("AND_DL"):
                self.add_dl(c_eval(a[0]), a[4].strip(), mm, True)
            self.walk(n.children, mm)
            return
        if cmd == "GEO_DISPLAY_LIST":
            self.add_dl(c_eval(a[0]), a[1].strip(), m)
            self.walk(n.children, m)
            return
        # GEO_NODE_START, GEO_SHADOW, GEO_CULLING_RADIUS, GEO_ZBUFFER, GEO_RENDER_RANGE, ... : just children
        self.walk(n.children, m)


# ============================================================ display lists

class Tri:
    __slots__ = ("pos", "st", "key", "tex")

    def __init__(self, pos, st, key, tex):
        self.pos, self.st, self.key, self.tex = pos, st, key, tex


class RSP:
    """Runs display lists, producing triangles with a material key each."""

    def __init__(self, src):
        self.src = src
        self.tris = []
        self.verts = [None] * 64
        self.reset()

    def reset(self):
        self.lighting = True
        self.texgen = False
        self.tex_on = False
        self.tex_scale = (1.0, 1.0)
        self.pending_tex = None
        self.tex = None
        self.cms = self.cmt = 0
        self.combine = "G_CC_SHADE"
        self.diffuse = (255, 255, 255)
        self.ambient = (0, 0, 0)
        self.env = (255, 255, 255, 255)
        self.prim = (255, 255, 255, 255)

    def light_color(self):
        return tuple(min(255, self.diffuse[i] + self.ambient[i] // 2) for i in range(3))

    def run(self, name, m, depth=0):
        if depth > 32:
            return True
        cmds = self.src.gfx.get(name)
        if cmds is None:
            return True
        for cmd, a in cmds:
            if cmd == "gsSPVertex":
                ref = a[0].replace(" ", "")
                base, off = ref, 0
                if "+" in ref:
                    base, o = ref.split("+", 1)
                    off = c_eval(o)
                verts = self.src.vtx.get(base, [])
                count, start = c_eval(a[1]), c_eval(a[2])
                for i in range(count):
                    if off + i >= len(verts):
                        break
                    pos, st, col = verts[off + i]
                    world = transform(pos, m)
                    if self.lighting:
                        color = self.light_color()
                    else:
                        color = tuple(col[:3])
                    self.verts[start + i] = (world, st, color, col[3])
            elif cmd == "gsSP1Triangle":
                self.tri(c_eval(a[0]), c_eval(a[1]), c_eval(a[2]))
            elif cmd == "gsSP2Triangles":
                self.tri(c_eval(a[0]), c_eval(a[1]), c_eval(a[2]))
                self.tri(c_eval(a[4]), c_eval(a[5]), c_eval(a[6]))
            elif cmd == "gsSPDisplayList":
                self.run(a[0].strip(), m, depth + 1)
            elif cmd == "gsSPBranchList":
                self.run(a[0].strip(), m, depth + 1)
                return True
            elif cmd == "gsSPEndDisplayList":
                return True
            elif cmd == "gsSPLight":
                ref = a[0].replace(" ", "").lstrip("&")
                name_l = ref.split(".")[0]
                lights = self.src.lights.get(name_l)
                if lights and len(lights) >= 6:
                    if ".a" in ref:
                        self.ambient = tuple(lights[0:3])
                    else:
                        self.diffuse = tuple(lights[3:6])
                        self.ambient = tuple(lights[0:3])
            elif cmd == "gsSPSetLights1":
                lights = self.src.lights.get(a[0].strip())
                if lights and len(lights) >= 6:
                    self.ambient, self.diffuse = tuple(lights[0:3]), tuple(lights[3:6])
            elif cmd == "gsSPTexture":
                self.tex_scale = (c_eval(a[0]) / 65536.0, c_eval(a[1]) / 65536.0)
                self.tex_on = c_eval(a[4]) != 0
            elif cmd == "gsDPSetTextureImage":
                self.pending_tex = a[3].strip()
            elif cmd in ("gsDPLoadBlock", "gsDPLoadTile", "gsDPLoadTLUTCmd"):
                if self.pending_tex:
                    self.tex = self.pending_tex
            elif cmd == "gsDPLoadTextureBlock":
                self.tex = a[0].strip()
                self.cms, self.cmt = c_eval(a[6]), c_eval(a[7])
            elif cmd == "gsDPSetTile":
                if c_eval(a[4]) == 0:
                    self.cmt, self.cms = c_eval(a[6]), c_eval(a[9])
            elif cmd == "gsSPSetGeometryMode":
                mode = c_eval(a[0])
                if mode & GBI["G_LIGHTING"]:
                    self.lighting = True
                if mode & GBI["G_TEXTURE_GEN"]:
                    self.texgen = True
            elif cmd == "gsSPClearGeometryMode":
                mode = c_eval(a[0])
                if mode & GBI["G_LIGHTING"]:
                    self.lighting = False
                if mode & GBI["G_TEXTURE_GEN"]:
                    self.texgen = False
            elif cmd == "gsSPGeometryMode":
                clear, set_ = c_eval(a[0]), c_eval(a[1])
                if clear & GBI["G_LIGHTING"]:
                    self.lighting = False
                if set_ & GBI["G_LIGHTING"]:
                    self.lighting = True
            elif cmd == "gsDPSetCombineMode":
                self.combine = a[0].strip()
            elif cmd == "gsDPSetEnvColor":
                self.env = tuple(c_eval(x) for x in a[:4])
            elif cmd == "gsDPSetPrimColor":
                self.prim = tuple(c_eval(x) for x in a[2:6])
        return False

    def mode(self):
        c = self.combine
        if not self.tex_on or self.texgen or self.tex is None:
            if "PRIMITIVE" in c:
                return "prim"
            return "shade"
        if "DECAL" in c:
            return "decal"
        if "BLEND" in c:
            return "blend"
        if "MODULATE" in c or "TEXEL" in c:
            return "modulate"
        if "SHADE" in c:
            return "shade"
        return "modulate"

    def tri(self, i0, i1, i2):
        vs = [self.verts[i] if 0 <= i < len(self.verts) else None for i in (i0, i1, i2)]
        if any(v is None for v in vs):
            return
        mode = self.mode()
        color = tuple(sum(v[2][k] for v in vs) // 3 for k in range(3))
        alpha = sum(v[3] for v in vs) // 3 if not self.lighting else 255
        if mode == "prim":
            color, alpha = self.prim[:3], self.prim[3]
            mode = "shade"
        if "FADE" in self.combine:
            alpha = self.env[3] if self.env[3] < 255 else alpha
        tex = None
        if mode != "shade":
            path = self.src.textures.get(self.tex)
            if path:
                tex = (path, self.cms, self.cmt, self.tex_scale)
            else:
                mode = "shade"
        q = lambda c: tuple((x // 8) * 8 for x in c)
        key = (mode, tex[0] if tex else None, tex[1] if tex else 0, tex[2] if tex else 0, q(color), alpha // 16 * 16)
        st = [(v[1][0] / 32.0, v[1][1] / 32.0) for v in vs]
        self.tris.append(Tri([v[0] for v in vs], st, key, tex))


# ============================================================ atlas, PNG, OBJ, GLB

def png_bytes(w, h, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for p in row:
            raw.extend(p)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def build_atlas(tris, textures):
    """Packs one tile per material key; returns (atlas rows, size, uv function)."""
    GUT = 2
    # uv range per key
    ranges = {}
    for t in tris:
        if t.tex is None:
            continue
        path, cms, cmt, scale = t.tex
        w, h, _ = textures.get(path)
        r = ranges.setdefault(t.key, [1e9, 1e9, -1e9, -1e9, w, h, cms, cmt])
        for s, tt in t.st:
            u, v = s * scale[0] / w, tt * scale[1] / h
            r[0], r[1], r[2], r[3] = min(r[0], u), min(r[1], v), max(r[2], u), max(r[3], v)
    tiles = {}
    for key in {t.key for t in tris}:
        if key[1] is None:
            tiles[key] = {"w": 4, "h": 4, "rx": 1, "ry": 1, "u0": 0, "v0": 0}
            continue
        r = ranges[key]
        w, h, cms, cmt = r[4], r[5], r[6], r[7]
        def span(lo, hi, clamp):
            if clamp & 2:
                return 0, 1
            a, b = math.floor(lo + 1e-4), math.ceil(hi - 1e-4)
            return a, max(1, min(4, b - a))
        u0, rx = span(r[0], r[2], cms)
        v0, ry = span(r[1], r[3], cmt)
        tiles[key] = {"w": w * rx, "h": h * ry, "rx": rx, "ry": ry, "u0": u0, "v0": v0, "tw": w, "th": h}
    # shelf packing
    width = 64
    while True:
        x = y = shelf = 0
        ok = True
        for key in sorted(tiles, key=lambda k: -tiles[k]["h"]):
            t = tiles[key]
            tw, th = t["w"] + GUT * 2, t["h"] + GUT * 2
            if tw > width:
                ok = False
                break
            if x + tw > width:
                x, y, shelf = 0, y + shelf, 0
            t["x"], t["y"] = x + GUT, y + GUT
            x += tw
            shelf = max(shelf, th)
        height = y + shelf
        if ok and height <= width:
            break
        width *= 2
    size = width
    rows_used = 1
    while rows_used < height:
        rows_used *= 2
    atlas = [[(0, 0, 0, 0)] * size for _ in range(rows_used)]

    def mixed(mode, texel, color, alpha):
        r, g, b, a = texel
        cr, cg, cb = color
        if mode == "decal":
            return (r, g, b, a)
        if mode == "blend":
            k = a / 255.0
            return (int(cr + (r - cr) * k), int(cg + (g - cg) * k), int(cb + (b - cb) * k), 255)
        # modulate
        return (r * cr // 255, g * cg // 255, b * cb // 255, a * alpha // 255)

    for key, t in tiles.items():
        mode, path, cms, cmt, color, alpha = key
        if path is None:
            px = (color[0], color[1], color[2], max(alpha, 1))
            for yy in range(-GUT, t["h"] + GUT):
                for xx in range(-GUT, t["w"] + GUT):
                    atlas[t["y"] + yy][t["x"] + xx] = px
            continue
        w, h, rows = textures.get(path)
        for yy in range(-GUT, t["h"] + GUT):
            for xx in range(-GUT, t["w"] + GUT):
                cx = min(max(xx, 0), t["w"] - 1)
                cy = min(max(yy, 0), t["h"] - 1)
                tx_i, ty_i = cx // w, cy // h
                sx, sy = cx % w, cy % h
                if cms & 1 and (t["u0"] + tx_i) % 2:
                    sx = w - 1 - sx
                if cmt & 1 and (t["v0"] + ty_i) % 2:
                    sy = h - 1 - sy
                atlas[t["y"] + yy][t["x"] + xx] = mixed(mode, rows[sy][sx], color, alpha)

    def uv(tri, i):
        t = tiles[tri.key]
        if tri.tex is None:
            px, py = t["x"] + 2, t["y"] + 2
        else:
            s, tt = tri.st[i]
            u = s * tri.tex[3][0] / t["tw"] - t["u0"]
            v = tt * tri.tex[3][1] / t["th"] - t["v0"]
            u = min(max(u, 0), t["rx"])
            v = min(max(v, 0), t["ry"])
            px, py = t["x"] + u * t["tw"], t["y"] + v * t["th"]
        return px / size, py / rows_used

    return atlas, (size, rows_used), uv


def write_outputs(out_dir, key, tris, textures, target_height=6.0):
    atlas, (size, rows_used), uv = build_atlas(tris, textures)
    # SM64 models face +Z; Roblox models face -Z: turn half a circle around Y. Then scale and stand on the ground.
    pts = [(-p[0], p[1], -p[2]) for t in tris for p in t.pos]
    ys = [p[1] for p in pts]
    xs = [p[0] for p in pts]
    zs = [p[2] for p in pts]
    height = max(ys) - min(ys) or 1
    k = target_height / height
    ox, oy, oz = (max(xs) + min(xs)) / 2, min(ys), (max(zs) + min(zs)) / 2
    positions = [((x - ox) * k, (y - oy) * k, (z - oz) * k) for x, y, z in pts]
    uvs = [uv(t, i) for t in tris for i in range(3)]
    png = png_bytes(size, rows_used, atlas)

    with open(os.path.join(out_dir, key + ".png"), "wb") as f:
        f.write(png)
    with open(os.path.join(out_dir, key + ".mtl"), "w") as f:
        f.write("newmtl atlas\nKd 1 1 1\nmap_Kd %s.png\n" % key)
    with open(os.path.join(out_dir, key + ".obj"), "w") as f:
        f.write("mtllib %s.mtl\no %s\n" % (key, key))
        for x, y, z in positions:
            f.write("v %.4f %.4f %.4f\n" % (x, y, z))
        for u, v in uvs:
            f.write("vt %.5f %.5f\n" % (u, 1 - v))
        f.write("usemtl atlas\n")
        for i in range(len(tris)):
            a, b, c = i * 3 + 1, i * 3 + 2, i * 3 + 3
            f.write("f %d/%d %d/%d %d/%d\n" % (a, a, b, b, c, c))

    # glTF binary with the texture embedded
    pos_bytes = b"".join(struct.pack("<3f", *p) for p in positions)
    uv_bytes = b"".join(struct.pack("<2f", u, v) for u, v in uvs)
    idx_bytes = b"".join(struct.pack("<I", i) for i in range(len(positions)))
    def pad(b):
        return b + b"\x00" * ((4 - len(b) % 4) % 4)
    blobs = [pad(pos_bytes), pad(uv_bytes), pad(idx_bytes), pad(png)]
    offsets, total = [], 0
    for b in blobs:
        offsets.append(total)
        total += len(b)
    mins = [min(p[i] for p in positions) for i in range(3)]
    maxs = [max(p[i] for p in positions) for i in range(3)]
    gltf = {
        "asset": {"version": "2.0", "generator": "sm64_to_roblox"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": key}],
        "meshes": [{"name": key, "primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "indices": 2, "material": 0}]}],
        "materials": [{"name": key, "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 1}, "alphaMode": "MASK", "doubleSided": True}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "images": [{"bufferView": 3, "mimeType": "image/png"}],
        "buffers": [{"byteLength": total}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": offsets[0], "byteLength": len(pos_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offsets[1], "byteLength": len(uv_bytes), "target": 34962},
            {"buffer": 0, "byteOffset": offsets[2], "byteLength": len(idx_bytes), "target": 34963},
            {"buffer": 0, "byteOffset": offsets[3], "byteLength": len(png)},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(positions), "type": "VEC3", "min": mins, "max": maxs},
            {"bufferView": 1, "componentType": 5126, "count": len(uvs), "type": "VEC2"},
            {"bufferView": 2, "componentType": 5125, "count": len(positions), "type": "SCALAR"},
        ],
    }
    js = json.dumps(gltf).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    body = b"".join(blobs)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(body))
    glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(body), 0x004E4942) + body
    with open(os.path.join(out_dir, key + ".glb"), "wb") as f:
        f.write(glb)
    return len(tris), (size, rows_used), positions, uvs, atlas


def write_luau(out_dir, key, positions, uvs, atlas):
    """A ModuleScript with the mesh and texture as base64 data, built in game with EditableMesh."""
    import base64
    w, h = len(atlas[0]), len(atlas)
    pos = b"".join(struct.pack("<3f", *p) for p in positions)
    uv = b"".join(struct.pack("<2f", u, v) for u, v in uvs)
    img = bytes(c for row in atlas for p in row for c in p)
    def lit(b):
        return '"' + base64.b64encode(b).decode() + '"'
    with open(os.path.join(out_dir, key + ".luau"), "w") as f:
        f.write("-- generated by tools/sm64_import from your own ROM; do not share\n")
        f.write("return {\n\twidth = %d,\n\theight = %d,\n\tpositions = %s,\n\tuvs = %s,\n\timage = %s,\n}\n" % (w, h, lit(pos), lit(uv), lit(img)))


def write_alias(out_dir, key, target, display):
    with open(os.path.join(out_dir, key + ".luau"), "w") as f:
        f.write("return { alias = %s }\n" % json.dumps(target))


# ============================================================ main

def convert(src, textures, key, geo, anim_name):
    anim = src.animation(anim_name)
    walker = Walker(src, anim)
    walker.walk(build_tree(src, geo), mat_identity())
    rsp = RSP(src)
    for layer in sorted({d[0] for d in walker.draws}):
        for d in walker.draws:
            if d[0] == layer:
                rsp.reset()
                rsp.run(d[1], d[2])
    return rsp.tris


def find_sm64(path):
    if path:
        return path
    here = os.path.join(os.getcwd(), "sm64-src")
    marker = os.path.join(here, "assets.json")
    if os.path.exists(marker):
        return here
    for name in os.listdir(here) if os.path.isdir(here) else []:
        if os.path.exists(os.path.join(here, name, "assets.json")):
            return os.path.join(here, name)
    print("Downloading the SM64 decompilation source (about 30 MB) from GitHub ...")
    data = urllib.request.urlopen(SM64_ZIP).read()
    os.makedirs(here, exist_ok=True)
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        members = [m for m in z.namelist() if m.split("/", 1)[-1].startswith(("actors/", "assets/", "assets.json"))]
        z.extractall(here, members)
    return find_sm64(None)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", required=True, help="your Super Mario 64 (USA) .z64 ROM")
    ap.add_argument("--sm64", help="folder with the n64decomp/sm64 source (downloaded if omitted)")
    ap.add_argument("--out", default="sm64_models", help="output folder (default: sm64_models)")
    ap.add_argument("--only", nargs="*", help="only these ids (e.g. captaincomet grumble)")
    ap.add_argument("--luau", help="also write ModuleScripts for the in-game mesh builder into this folder")
    args = ap.parse_args()

    with open(args.rom, "rb") as f:
        rom = f.read()
    if rom[:4] == b"\x37\x80\x40\x12":  # .v64 byte-swapped
        rom = bytes(b for i in range(0, len(rom), 2) for b in (rom[i + 1], rom[i]))
    digest = hashlib.sha1(rom).hexdigest()
    if digest != US_SHA1:
        print("This doesn't look like the Super Mario 64 (USA) ROM (sha1 %s). Continuing anyway." % digest)

    root = find_sm64(args.sm64)
    with open(os.path.join(root, "assets.json")) as f:
        assets = json.load(f)
    print("Reading the SM64 source in", root)
    src = Source(root)
    textures = Textures(rom, assets)
    os.makedirs(args.out, exist_ok=True)

    names = []
    done, display_names = {}, {}
    for key, (geo, anim, display) in ACTORS.items():
        if args.only and key not in args.only:
            continue
        try:
            tris = convert(src, textures, key, geo, anim)
            if not tris:
                print("  %-14s no triangles (skipped)" % key)
                continue
            count, size, positions, uvs, atlas = write_outputs(args.out, key, tris, textures)
            print("  %-14s %-16s %5d triangles, %dx%d texture" % (key, display, count, size[0], size[1]))
            if args.luau:
                os.makedirs(args.luau, exist_ok=True)
                same = next((k for k, g in done.items() if g == (geo, anim)), None)
                if same:
                    write_alias(args.luau, key, same, display)
                else:
                    write_luau(args.luau, key, positions, uvs, atlas)
                    done[key] = (geo, anim)
                display_names[key] = display
            names.append((key, display))
        except Exception as e:  # keep going with the other models
            print("  %-14s failed: %s" % (key, e))

    lua = [
        "-- Paste this into Roblox Studio's Command Bar (View > Command Bar) after importing the .glb files.",
        "-- It moves every imported SM64 model into ReplicatedStorage.CustomModels and names it for the game.",
        "local RS = game:GetService(\"ReplicatedStorage\")",
        "local folder = RS:FindFirstChild(\"CustomModels\") or Instance.new(\"Folder\")",
        "folder.Name = \"CustomModels\"",
        "folder.Parent = RS",
        "local names = {",
    ]
    for key, display in names:
        lua.append("\t%s = %s," % (key, json.dumps(display)))
    lua += [
        "}",
        "local moved = 0",
        "for _, place in { workspace, RS, folder } do",
        "\tfor _, m in place:GetChildren() do",
        "\t\tlocal id = m.Name:gsub(\"%.glb$\", \"\"):gsub(\"%.obj$\", \"\")",
        "\t\tif names[id] and (m:IsA(\"Model\") or m:IsA(\"BasePart\")) then",
        "\t\t\tlocal model = m",
        "\t\t\tif m:IsA(\"BasePart\") then -- a single mesh: wrap it in a Model",
        "\t\t\t\tmodel = Instance.new(\"Model\")",
        "\t\t\t\tm.Parent = model",
        "\t\t\tend",
        "\t\t\tmodel.Name = id",
        "\t\t\tmodel:SetAttribute(\"DisplayName\", names[id])",
        "\t\t\tmodel.Parent = folder",
        "\t\t\tmoved += 1",
        "\t\tend",
        "\tend",
        "end",
        "print(\"SM64 models ready: \" .. moved)",
    ]
    with open(os.path.join(args.out, "set_names.lua"), "w") as f:
        f.write("\n".join(lua) + "\n")
    if args.luau:
        with open(os.path.join(args.luau, "Names.luau"), "w") as f:
            f.write("return " + "{\n" + "".join("\t%s = %s,\n" % (k, json.dumps(v)) for k, v in display_names.items()) + "}\n")
    print("Done: %d models in %s" % (len(names), os.path.abspath(args.out)))


if __name__ == "__main__":
    main()
