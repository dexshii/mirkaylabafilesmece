-- Builds the lobby around the spawn (the floor and spawn pad are in the place file): the castle with the battle gate,
-- the Summon Hall with its pedestal (summoned units appear there), statues of every unit and some decoration.
-- Walking up to the gate or the pedestal shows a prompt that opens the matching window.
local Shared = game.ReplicatedStorage.Shared
local ModelFactory = require(Shared.ModelFactory)
local Units = require(Shared.Units)
local Rarities = require(Shared.Rarities)

local Lobby = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

function Lobby.spawnCFrame(): CFrame
	return CFrame.new(0, 5, 0)
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif shape == "Sphere" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = parent
	return p
end

-- a vertical cylinder standing on `base`
local function pillar(parent: Instance, height: number, diameter: number, base: Vector3, color: Color3, material: Enum.Material?): BasePart
	return part(parent, Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, "Cylinder")
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = parent
end

local function sparkles(parent: Instance, color: Color3, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(1, 2)
	e.Speed = NumberRange.new(1, 4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(1, 0)
	e.Parent = parent
end

local function sign(p: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
end

local function prompt(parent: BasePart, action: string, window: string)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = ""
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.HoldDuration = 0
	p.MaxActivationDistance = 16
	p.RequiresLineOfSight = false
	p:SetAttribute("OpensWindow", window)
	p.Parent = parent
end

local function buildCastle(lobby: Instance)
	local wall = Color3.fromRGB(245, 238, 225)
	local roof = Color3.fromRGB(220, 50, 55)
	local gold = Color3.fromRGB(255, 205, 50)
	part(lobby, Vector3.new(64, 28, 22), CFrame.new(0, 14, 70), wall, Enum.Material.Brick)
	for x = -28, 28, 6 do
		part(lobby, Vector3.new(3, 3, 22), CFrame.new(x, 29.5, 70), wall, Enum.Material.Brick)
	end
	for _, x in { -36, 36 } do
		pillar(lobby, 40, 16, Vector3.new(x, 0, 70), wall, Enum.Material.Brick)
		for i = 0, 4 do
			local w = 18 - i * 3.6
			part(lobby, Vector3.new(w, 3, w), CFrame.new(x, 41.5 + i * 2.9, 70) * CFrame.Angles(0, math.rad(45), 0), roof)
		end
	end
	-- the keep and its star
	part(lobby, Vector3.new(26, 18, 18), CFrame.new(0, 37, 74), wall, Enum.Material.Brick)
	for i = 0, 5 do
		local w = 28 - i * 4.6
		part(lobby, Vector3.new(w, 3.4, w), CFrame.new(0, 47.7 + i * 3.2, 74) * CFrame.Angles(0, math.rad(45), 0), roof)
	end
	local star = part(lobby, Vector3.new(8, 8, 1.5), CFrame.new(0, 70, 74) * CFrame.Angles(0, 0, math.rad(45)), gold, Enum.Material.Neon)
	light(star, gold, 50, 3)
	sparkles(star, gold, 10)
	-- stained-glass windows
	for _, x in { -18, -9, 9, 18 } do
		part(lobby, Vector3.new(4, 7, 0.6), CFrame.new(x, 17, 58.8), Color3.fromRGB(90, 170, 255), Enum.Material.Neon)
	end
	-- the battle gate: a glowing portal in the castle door
	part(lobby, Vector3.new(18, 20, 1), CFrame.new(0, 10, 58.6), Color3.fromRGB(110, 65, 35), Enum.Material.Wood)
	local gate = part(lobby, Vector3.new(14, 17, 0.6), CFrame.new(0, 8.5, 58), Color3.fromRGB(150, 70, 255), Enum.Material.Neon)
	gate.Transparency = 0.15
	gate.Name = "BattleGate"
	light(gate, Color3.fromRGB(170, 100, 255), 30, 3)
	sparkles(gate, Color3.fromRGB(220, 170, 255), 20)
	prompt(gate, "Battle", "Play")
	local banner = part(lobby, Vector3.new(30, 6, 1), CFrame.new(0, 23, 58.4), Color3.fromRGB(60, 40, 120))
	sign(banner, Enum.NormalId.Front, "⚔ BATTLE ⚔", Color3.fromRGB(255, 225, 90))
	local title = part(lobby, Vector3.new(44, 9, 1), CFrame.new(0, 34, 58.2), Color3.fromRGB(60, 40, 120))
	sign(title, Enum.NormalId.Front, "STAR KINGDOM DEFENSE", Color3.fromRGB(255, 225, 90))
end

local function buildSummonHall(lobby: Instance)
	local hall = Instance.new("Model")
	hall.Name = "SummonHall"
	hall.Parent = lobby
	local center = Vector3.new(0, 0, -62)
	local marble = Color3.fromRGB(240, 236, 250)
	local gold = Color3.fromRGB(255, 205, 50)
	local pink = Color3.fromRGB(255, 90, 180)
	pillar(hall, 1.4, 54, center, Color3.fromRGB(200, 190, 230), Enum.Material.Marble)
	pillar(hall, 1.6, 46, center, marble, Enum.Material.Marble)
	local ring = pillar(hall, 1.7, 30, center, pink, Enum.Material.Neon)
	ring.Transparency = 0.3
	pillar(hall, 1.8, 26, center, marble, Enum.Material.Marble)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local base = center + Vector3.new(math.cos(a) * 21, 1.6, math.sin(a) * 21)
		pillar(hall, 1.4, 4.4, base, gold, Enum.Material.Metal)
		pillar(hall, 22, 3, base + Vector3.new(0, 1.4, 0), marble, Enum.Material.Marble)
		pillar(hall, 1.4, 4.4, base + Vector3.new(0, 23.4, 0), gold, Enum.Material.Metal)
		local orb = part(hall, Vector3.new(2.6, 2.6, 2.6), CFrame.new(base + Vector3.new(0, 26.4, 0)), pink, Enum.Material.Neon, "Sphere")
		light(orb, pink, 18, 1.5)
	end
	-- a floating ring above the pedestal
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		part(hall, Vector3.new(3.4, 1, 1.4), CFrame.new(center + Vector3.new(math.cos(a) * 12, 30, math.sin(a) * 12)) * CFrame.Angles(0, math.pi / 2 - a, 0), gold, Enum.Material.Metal)
	end
	local pedestal = pillar(hall, 4, 9, center + Vector3.new(0, 1.8, 0), gold, Enum.Material.Metal)
	pedestal.Name = "Pedestal"
	local top = pillar(hall, 0.6, 7.6, center + Vector3.new(0, 5.8, 0), pink, Enum.Material.Neon)
	light(top, pink, 24, 2.5)
	sparkles(top, Color3.fromRGB(255, 200, 240), 14)
	prompt(pedestal, "Summon", "Summon")
	local sign1 = part(hall, Vector3.new(26, 6, 1), CFrame.new(center + Vector3.new(0, 34, 0)) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(80, 30, 120))
	sign(sign1, Enum.NormalId.Front, "✨ SUMMON ✨", Color3.fromRGB(255, 225, 90))
	sign(sign1, Enum.NormalId.Back, "✨ SUMMON ✨", Color3.fromRGB(255, 225, 90))

	-- the Mythic units on display around the pedestal
	local mythics = Units.ByRarity.Mythic
	for i, def in mythics do
		local a = math.pi / 2 + (i - (#mythics + 1) / 2) * 0.55
		local pos = center + Vector3.new(math.cos(a) * 15, 1.8, math.sin(a) * 15)
		pillar(hall, 1.2, 6, pos, Rarities.Info.Mythic.color, Enum.Material.Neon)
		local model = ModelFactory.build(def.id, 1.1, true)
		model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 1.2, 0), Vector3.new(0, pos.Y + 1.2, 0)))
		model.Parent = hall
	end
end

local function buildStatues(lobby: Instance)
	-- every unit on a plinth along the two sides of the plaza, best rarity nearest the castle
	local list = table.clone(Units.List)
	table.sort(list, function(a, b)
		return Rarities.Info[a.rarity].rank > Rarities.Info[b.rarity].rank
	end)
	for i, def in list do
		local side = (i % 2 == 0) and 1 or -1
		local row = math.ceil(i / 2)
		local pos = Vector3.new(side * 44, 0, 48 - row * 13)
		local color = Rarities.Info[def.rarity].color
		part(lobby, Vector3.new(7, 2.4, 7), CFrame.new(pos + Vector3.new(0, 1.2, 0)), Color3.fromRGB(225, 220, 235), Enum.Material.Marble)
		local trim = part(lobby, Vector3.new(7.4, 0.5, 7.4), CFrame.new(pos + Vector3.new(0, 2.5, 0)), color, Enum.Material.Neon)
		trim.Transparency = 0.2
		local model = ModelFactory.build(def.id, 1.25, true)
		model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 2.7, 0), Vector3.new(0, 2.7, pos.Z)))
		model.Parent = lobby
	end
end

local function buildDecor(lobby: Instance)
	-- a stone plaza and paths
	part(lobby, Vector3.new(60, 0.3, 60), CFrame.new(0, 0.15, 0), Color3.fromRGB(215, 205, 185), Enum.Material.Cobblestone)
	part(lobby, Vector3.new(14, 0.3, 40), CFrame.new(0, 0.15, 40), Color3.fromRGB(215, 205, 185), Enum.Material.Cobblestone)
	part(lobby, Vector3.new(14, 0.3, 20), CFrame.new(0, 0.15, -32), Color3.fromRGB(215, 205, 185), Enum.Material.Cobblestone)
	-- trees and giant mushrooms around the edge
	local rng = Random.new(7)
	for i = 1, 26 do
		local a = i / 26 * math.pi * 2
		local r = rng:NextNumber(86, 102)
		local p = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		if i % 3 == 0 then
			pillar(lobby, 8, 4, p, Color3.fromRGB(250, 238, 210))
			part(lobby, Vector3.new(16, 8, 16), CFrame.new(p + Vector3.new(0, 9, 0)), ({ Color3.fromRGB(230, 50, 50), Color3.fromRGB(60, 130, 235), Color3.fromRGB(250, 170, 40) })[i % 3 + 1], nil, "Sphere")
		else
			pillar(lobby, 9, 2.4, p, Color3.fromRGB(125, 85, 50), Enum.Material.Wood)
			part(lobby, Vector3.new(12, 10, 12), CFrame.new(p + Vector3.new(0, 12, 0)), Color3.fromRGB(60, 170, 70), Enum.Material.Grass, "Sphere")
		end
	end
	-- floating ? blocks
	for _, p in { Vector3.new(-24, 14, 20), Vector3.new(24, 14, 20), Vector3.new(-30, 16, -24), Vector3.new(30, 16, -24) } do
		local b = part(lobby, Vector3.new(5, 5, 5), CFrame.new(p), Color3.fromRGB(255, 200, 40))
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
			sign(b, face, "?", Color3.new(1, 1, 1))
		end
		light(b, Color3.fromRGB(255, 220, 120), 12, 1)
	end
end

function Lobby.build()
	local lobby = workspace:FindFirstChild("Lobby") or Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.Parent = workspace
	buildDecor(lobby)
	buildCastle(lobby)
	buildSummonHall(lobby)
	buildStatues(lobby)
end

return Lobby
