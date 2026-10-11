-- Music and sound effects. With ReplicatedStorage.SM64Models.Audio (made by tools/sm64_import/sm64_audio.py from
-- your own ROM) and its files uploaded to Roblox, the game plays SM64's music and sounds: each upload holds many
-- clips, and a Sound plays one clip as its PlaybackRegion. Upload ids come from that module's `ids`, or from
-- attributes of the same names on SoundService (set those in Studio so a rebuild doesn't clear them). Without
-- them a few built-in Roblox sounds stand in and there is no music. M mutes or unmutes the music.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Audio = {}

Audio.musicVolume = 0.35
Audio.sfxVolume = 0.6
Audio.musicMuted = false

type Clip = { sheet: string, start: number, length: number }

local clips: { [string]: Clip } = {}
local sheets: { [string]: Sound } = {} -- a loaded Sound per uploaded file, cloned to play
local lastPlayed: { [string]: number } = {}
local playing: { [string]: number } = {}

-- built-in sounds for when there's no SM64 audio
local FALLBACK: { [string]: { id: string, pitch: number, volume: number } } = {
	ui_click = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.6, volume = 0.25 },
	ui_open = { id = "rbxasset://sounds/swoosh.wav", pitch = 1.3, volume = 0.3 },
	ui_close = { id = "rbxasset://sounds/swoosh.wav", pitch = 1.0, volume = 0.25 },
	coin = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 2.0, volume = 0.3 },
	star_appears = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.2, volume = 0.6 },
	power_meter = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.9, volume = 0.4 },
	swish = { id = "rbxasset://sounds/swoosh.wav", pitch = 1.4, volume = 0.3 },
	throw = { id = "rbxasset://sounds/swoosh.wav", pitch = 1.8, volume = 0.35 },
	stomped = { id = "rbxasset://sounds/swoosh.wav", pitch = 0.7, volume = 0.4 },
	spin = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 2.4, volume = 0.25 },
	flame = { id = "rbxasset://sounds/swoosh.wav", pitch = 0.5, volume = 0.35 },
	explosion = { id = "rbxasset://sounds/swoosh.wav", pitch = 0.4, volume = 0.5 },
	pound = { id = "rbxasset://sounds/swoosh.wav", pitch = 0.6, volume = 0.5 },
	enemy_die = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 0.7, volume = 0.3 },
	right_answer = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.3, volume = 0.4 },
	coin_spurt = { id = "rbxasset://sounds/electronicpingshort.wav", pitch = 1.8, volume = 0.3 },
}

local function load()
	local folder = ReplicatedStorage:FindFirstChild("SM64Models")
	local module = folder and folder:FindFirstChild("Audio")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, data = pcall(require, module)
	if not ok or type(data) ~= "table" then
		return
	end
	local ids = data.ids or {}
	local toLoad = {}
	for _, old in sheets do
		old:Destroy()
	end
	table.clear(sheets)
	table.clear(clips)
	for sheet in ids do
		local id = SoundService:GetAttribute(sheet) or ids[sheet]
		if type(id) == "string" then
			id = tonumber(id:match("%d+"))
		end
		if type(id) == "number" and id > 0 then
			local sound = Instance.new("Sound")
			sound.Name = sheet
			sound.SoundId = "rbxassetid://" .. id
			sound.PlaybackRegionsEnabled = true
			sound.Volume = 0
			sound.Parent = SoundService
			sheets[sheet] = sound
			table.insert(toLoad, sound)
		end
	end
	for name, c in data.clips or {} do
		if sheets[c[1]] then
			clips[name] = { sheet = c[1], start = c[2], length = c[3] }
		end
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(toLoad)
		end)
	end)
	print(string.format("[SM64] audio: %d clips from %d uploads", (function()
		local n = 0
		for _ in clips do
			n += 1
		end
		return n
	end)(), #toLoad))
end

-- how many clips and uploaded files are in use (for the admin panel)
function Audio.status(): string
	local n, s = 0, 0
	for _ in clips do
		n += 1
	end
	for _ in sheets do
		s += 1
	end
	return string.format("SM64 audio: %d clips from %d uploaded files", n, s)
end

function Audio.has(name: string): boolean
	return clips[name] ~= nil
end

-- plays a sound effect. opts: volume (0..1, times the sfx volume), pitch, gap (seconds before it may play again),
-- max (how many may play at once)
function Audio.play(name: string, opts: { volume: number?, pitch: number?, gap: number?, max: number? }?)
	local o = opts or {}
	local now = os.clock()
	if now - (lastPlayed[name] or 0) < (o.gap or 0.04) then
		return
	end
	if (playing[name] or 0) >= (o.max or 4) then
		return
	end
	local clip = clips[name]
	local sound: Sound
	local length
	if clip then
		sound = sheets[clip.sheet]:Clone()
		sound.PlaybackRegion = NumberRange.new(clip.start, clip.start + clip.length)
		sound.Volume = Audio.sfxVolume * (o.volume or 1)
		length = clip.length
	else
		local fb = FALLBACK[name]
		if not fb then
			return
		end
		sound = Instance.new("Sound")
		sound.SoundId = fb.id
		sound.Volume = Audio.sfxVolume * fb.volume * (o.volume or 1)
		sound.PlaybackSpeed = fb.pitch
		length = 2
	end
	lastPlayed[name] = now
	playing[name] = (playing[name] or 0) + 1
	if o.pitch then
		sound.PlaybackSpeed *= o.pitch
	end
	sound.Parent = SoundService
	sound:Play()
	task.delay(length / sound.PlaybackSpeed + 0.2, function()
		playing[name] = math.max(0, (playing[name] or 1) - 1)
		sound:Destroy()
	end)
end

-- ============================================================ music

local current: Sound? = nil
local currentName: string? = nil

local function fadeOut(sound: Sound, t: number)
	TweenService:Create(sound, TweenInfo.new(t), { Volume = 0 }):Play()
	task.delay(t, function()
		sound:Destroy()
	end)
end

-- switches the background music (nil stops it), crossfading over `fade` seconds
function Audio.music(name: string?, fade: number?)
	if name == currentName then
		return
	end
	currentName = name
	local t = fade or 1.2
	if current then
		fadeOut(current, t)
		current = nil
	end
	local clip = name and clips[name]
	if not clip then
		return
	end
	local sound = sheets[clip.sheet]:Clone()
	sound.Name = "Music"
	sound.Looped = true
	sound.PlaybackRegion = NumberRange.new(clip.start, clip.start + clip.length)
	sound.LoopRegion = NumberRange.new(clip.start, clip.start + clip.length)
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(t), { Volume = Audio.musicMuted and 0 or Audio.musicVolume }):Play()
	current = sound
end

-- plays a jingle over the music, which dips meanwhile
function Audio.jingle(name: string)
	local clip = clips[name]
	if not clip then
		return
	end
	Audio.play(name, { volume = 1.2, gap = 0.5, max = 1 })
	if current and not Audio.musicMuted then
		local music = current
		TweenService:Create(music, TweenInfo.new(0.3), { Volume = Audio.musicVolume * 0.2 }):Play()
		task.delay(clip.length, function()
			if music.Parent and music == current then
				TweenService:Create(music, TweenInfo.new(1), { Volume = Audio.musicVolume }):Play()
			end
		end)
	end
end

function Audio.setMusicMuted(muted: boolean)
	Audio.musicMuted = muted
	if current then
		TweenService:Create(current, TweenInfo.new(0.4), { Volume = muted and 0 or Audio.musicVolume }):Play()
	end
end

-- ============================================================ start

function Audio.start()
	load()
	-- ids set from the admin panel arrive as SoundService attributes: load again and restart the music
	SoundService.AttributeChanged:Connect(function()
		task.defer(function()
			load()
			local name = currentName
			currentName = nil
			if current then
				current:Destroy()
				current = nil
			end
			Audio.music(name)
		end)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.M then
			Audio.setMusicMuted(not Audio.musicMuted)
		end
	end)
end

-- picks the music for what's on screen: the lobby, a map's theme, or the boss theme while a boss is alive
local wasActive = false
function Audio.followBattle(state: any)
	if not state.active then
		wasActive = false
		Audio.music(if workspace:GetAttribute("BattleServer") then nil else "music_lobby")
		return
	end
	if state.state == "won" or state.state == "lost" then
		return -- the end screen's jingle plays instead
	end
	if not wasActive then
		wasActive = true
		Audio.play("voice_here_we_go", { gap = 2 })
	end
	if state.boss and state.boss.hp > 0 then
		if currentName ~= "music_boss" then
			Audio.play("bowser_roar", { volume = 1, gap = 3, max = 1 })
		end
		Audio.music("music_boss", 0.8)
	elseif state.mapId then
		Audio.music("music_" .. state.mapId)
	end
end

return Audio
