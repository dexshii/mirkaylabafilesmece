-- Builds every unit and enemy model out of plain parts, so the game needs no uploaded meshes.
-- Models face -Z (Roblox's forward). Each model's PrimaryPart "Root" is an invisible part at its feet; the other
-- parts are welded to it, so moving Root moves the model.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Units = require(script.Parent.Units)

local ModelFactory = {}

local WHITE = Color3.fromRGB(250, 250, 250)
local BLACK = Color3.fromRGB(25, 25, 30)
local SKIN = Color3.fromRGB(255, 205, 160)
local GOLD = Color3.fromRGB(255, 205, 40)

type Spec = { any }

-- spec: { shape, size, pos, color, extras? } ; extras: { r = rotation degrees, m = material, t = transparency }
local function P(shape: string, size: Vector3, pos: Vector3, color: Color3, extras: { [string]: any }?): Spec
	return { shape, size, pos, color, extras or {} }
end

local function eyes(y: number, z: number, spacing: number, size: number, color: Color3?): { Spec }
	return {
		P("Ball", Vector3.new(size, size * 1.4, size * 0.6), Vector3.new(-spacing, y, z), WHITE),
		P("Ball", Vector3.new(size, size * 1.4, size * 0.6), Vector3.new(spacing, y, z), WHITE),
		P("Ball", Vector3.new(size * 0.5, size * 0.8, size * 0.4), Vector3.new(-spacing, y, z - size * 0.22), color or BLACK),
		P("Ball", Vector3.new(size * 0.5, size * 0.8, size * 0.4), Vector3.new(spacing, y, z - size * 0.22), color or BLACK),
	}
end

local function angryBrows(y: number, z: number, spacing: number, w: number): { Spec }
	return {
		P("Block", Vector3.new(w, w * 0.25, 0.2), Vector3.new(-spacing, y, z), BLACK, { r = Vector3.new(0, 0, -20) }),
		P("Block", Vector3.new(w, w * 0.25, 0.2), Vector3.new(spacing, y, z), BLACK, { r = Vector3.new(0, 0, 20) }),
	}
end

local function feet(color: Color3, spacing: number, size: number): { Spec }
	return {
		P("Ball", Vector3.new(size, size * 0.6, size * 1.3), Vector3.new(-spacing, size * 0.3, -size * 0.2), color),
		P("Ball", Vector3.new(size, size * 0.6, size * 1.3), Vector3.new(spacing, size * 0.3, -size * 0.2), color),
	}
end

local function concat(...: { Spec }): { Spec }
	local out = {}
	for _, list in { ... } do
		for _, s in list do
			table.insert(out, s)
		end
	end
	return out
end

local function mushroom(capColor: Color3, spotColor: Color3, stemColor: Color3, footColor: Color3, angry: boolean): { Spec }
	local specs = {
		P("Ball", Vector3.new(2.2, 2.0, 2.2), Vector3.new(0, 1.3, 0), stemColor),
		P("Ball", Vector3.new(3.6, 2.1, 3.6), Vector3.new(0, 2.7, 0), capColor),
		P("Ball", Vector3.new(0.9, 0.5, 0.9), Vector3.new(0, 3.65, 0), spotColor),
		P("Ball", Vector3.new(0.8, 0.6, 0.5), Vector3.new(-1.2, 2.9, -1.2), spotColor),
		P("Ball", Vector3.new(0.8, 0.6, 0.5), Vector3.new(1.2, 2.9, -1.2), spotColor),
		P("Ball", Vector3.new(0.8, 0.6, 0.5), Vector3.new(0, 2.8, 1.65), spotColor),
	}
	specs = concat(specs, eyes(1.5, -1.0, 0.4, 0.45), feet(footColor, 0.6, 1.0))
	if angry then
		specs = concat(specs, angryBrows(2.0, -1.12, 0.42, 0.6))
	end
	return specs
end

local function ghost(color: Color3, transparency: number, angry: boolean): { Spec }
	local specs = {
		P("Ball", Vector3.new(3.2, 3.2, 3.2), Vector3.new(0, 2.6, 0), color, { t = transparency }),
		P("Ball", Vector3.new(1.2, 1.2, 1.4), Vector3.new(0, 1.3, 1.3), color, { t = transparency }),
		P("Ball", Vector3.new(0.9, 0.7, 0.7), Vector3.new(-1.7, 2.4, -0.3), color, { t = transparency }),
		P("Ball", Vector3.new(0.9, 0.7, 0.7), Vector3.new(1.7, 2.4, -0.3), color, { t = transparency }),
		P("Ball", Vector3.new(0.4, 0.8, 0.3), Vector3.new(-0.5, 3.0, -1.5), BLACK),
		P("Ball", Vector3.new(0.4, 0.8, 0.3), Vector3.new(0.5, 3.0, -1.5), BLACK),
		P("Ball", Vector3.new(1.0, 0.5, 0.3), Vector3.new(0, 2.2, -1.55), Color3.fromRGB(200, 40, 60)),
	}
	if angry then
		specs = concat(specs, angryBrows(3.55, -1.5, 0.5, 0.6))
	end
	return specs
end

local function bomb(body: Color3, footColor: Color3, angry: boolean): { Spec }
	local specs = {
		P("Ball", Vector3.new(3, 3, 3), Vector3.new(0, 2, 0), body),
		P("Cylinder", Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 3.55, 0), Color3.fromRGB(160, 160, 160), { r = Vector3.new(0, 0, 90) }),
		P("Cylinder", Vector3.new(0.8, 0.15, 0.15), Vector3.new(0, 4.0, 0), Color3.fromRGB(230, 220, 190), { r = Vector3.new(0, 0, 90) }),
		P("Ball", Vector3.new(0.4, 0.4, 0.4), Vector3.new(0, 4.45, 0), Color3.fromRGB(255, 170, 40), { m = Enum.Material.Neon }),
		P("Block", Vector3.new(0.3, 1.2, 0.3), Vector3.new(0, 2.1, 1.6), GOLD),
		P("Block", Vector3.new(1.4, 0.7, 0.2), Vector3.new(0, 2.5, 1.8), GOLD),
	}
	return concat(specs, eyes(2.3, -1.3, 0.45, 0.5), feet(footColor, 0.7, 1.0), angry and angryBrows(2.9, -1.35, 0.45, 0.6) or {})
end

local function turtle(shell: Color3, skin: Color3, spikes: boolean): { Spec }
	local specs = {
		P("Ball", Vector3.new(3.2, 2.6, 3.4), Vector3.new(0, 2.0, 0.3), shell),
		P("Cylinder", Vector3.new(0.5, 3.4, 3.6), Vector3.new(0, 1.0, 0.3), WHITE, { r = Vector3.new(0, 0, 90) }),
		P("Ball", Vector3.new(1.7, 1.8, 1.7), Vector3.new(0, 3.1, -1.6), skin),
	}
	if spikes then
		for i = -1, 1 do
			table.insert(specs, P("Ball", Vector3.new(0.6, 0.9, 0.6), Vector3.new(i * 0.9, 3.25, 0.4), WHITE))
		end
	end
	return concat(specs, eyes(3.35, -2.35, 0.32, 0.45), feet(skin, 0.8, 0.9))
end

local designs: { [string]: () -> { Spec } } = {}

-- ===== units =====
designs.mushling = function()
	return mushroom(Color3.fromRGB(230, 40, 40), WHITE, Color3.fromRGB(255, 240, 210), Color3.fromRGB(120, 70, 40), false)
end
designs.fusebuddy = function()
	return bomb(Color3.fromRGB(255, 140, 175), GOLD, false)
end
designs.shellback = function()
	return turtle(Color3.fromRGB(60, 190, 70), Color3.fromRGB(255, 220, 80), false)
end
designs.buzzwing = function()
	return concat({
		P("Cylinder", Vector3.new(2.2, 0.4, 0.4), Vector3.new(0, 1.1, 0), Color3.fromRGB(110, 80, 50), { r = Vector3.new(0, 0, 90) }),
		P("Ball", Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 3.0, 0), Color3.fromRGB(255, 210, 40)),
		P("Ball", Vector3.new(1.6, 1.6, 0.6), Vector3.new(0, 3.0, -1.0), WHITE),
		P("Cylinder", Vector3.new(0.8, 0.3, 0.3), Vector3.new(0, 4.3, 0), BLACK, { r = Vector3.new(0, 0, 90) }),
		P("Block", Vector3.new(3.6, 0.1, 0.5), Vector3.new(0, 4.7, 0), Color3.fromRGB(240, 240, 240)),
		P("Block", Vector3.new(0.5, 0.1, 3.6), Vector3.new(0, 4.72, 0), Color3.fromRGB(240, 240, 240)),
		P("Ball", Vector3.new(0.3, 0.5, 0.2), Vector3.new(-0.3, 3.15, -1.3), BLACK),
		P("Ball", Vector3.new(0.3, 0.5, 0.2), Vector3.new(0.3, 3.15, -1.3), BLACK),
	})
end
designs.spooky = function()
	return ghost(Color3.fromRGB(245, 245, 255), 0.15, false)
end
designs.cloudrider = function()
	return concat({
		P("Ball", Vector3.new(2.6, 1.8, 2.6), Vector3.new(-1.1, 1.4, 0), WHITE),
		P("Ball", Vector3.new(2.6, 1.8, 2.6), Vector3.new(1.1, 1.4, 0), WHITE),
		P("Ball", Vector3.new(3.0, 2.2, 3.0), Vector3.new(0, 1.7, 0.2), WHITE),
		P("Ball", Vector3.new(1.8, 2.0, 1.8), Vector3.new(0, 3.3, 0.2), Color3.fromRGB(80, 190, 90)),
		P("Ball", Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 4.6, -0.3), Color3.fromRGB(255, 220, 80)),
		P("Block", Vector3.new(1.8, 0.4, 0.4), Vector3.new(0, 4.9, -1.0), BLACK, { m = Enum.Material.Glass, t = 0.2 }),
		P("Ball", Vector3.new(1.1, 1.1, 1.1), Vector3.new(1.3, 3.8, -0.6), Color3.fromRGB(230, 50, 50)),
	})
end
designs.shroombanker = function()
	return concat(mushroom(Color3.fromRGB(40, 110, 230), WHITE, Color3.fromRGB(255, 240, 210), Color3.fromRGB(90, 60, 40), false), {
		P("Cylinder", Vector3.new(1.4, 1.2, 1.2), Vector3.new(-1.9, 0.7, -0.6), GOLD, { r = Vector3.new(0, 0, 90), m = Enum.Material.Metal }),
		P("Cylinder", Vector3.new(0.9, 1.2, 1.2), Vector3.new(1.9, 0.45, -0.6), GOLD, { r = Vector3.new(0, 0, 90), m = Enum.Material.Metal }),
		P("Cylinder", Vector3.new(0.9, 1.6, 1.6), Vector3.new(0, 4.1, 0), BLACK, { r = Vector3.new(0, 0, 90) }),
	})
end
designs.flamebloom = function()
	return concat({
		P("Cylinder", Vector3.new(2.0, 2.6, 2.6), Vector3.new(0, 1.0, 0), Color3.fromRGB(40, 170, 60), { r = Vector3.new(0, 0, 90) }),
		P("Cylinder", Vector3.new(0.5, 3.0, 3.0), Vector3.new(0, 2.1, 0), Color3.fromRGB(50, 200, 70), { r = Vector3.new(0, 0, 90) }),
		P("Cylinder", Vector3.new(1.4, 0.5, 0.5), Vector3.new(0, 2.9, 0), Color3.fromRGB(60, 160, 60), { r = Vector3.new(0, 0, 90) }),
		P("Ball", Vector3.new(2.4, 2.2, 2.4), Vector3.new(0, 4.3, 0), Color3.fromRGB(240, 60, 40)),
		P("Ball", Vector3.new(1.8, 0.6, 0.6), Vector3.new(0, 4.1, -1.05), WHITE),
		P("Ball", Vector3.new(0.5, 0.5, 0.3), Vector3.new(-0.6, 4.9, -0.9), WHITE),
		P("Ball", Vector3.new(0.5, 0.5, 0.3), Vector3.new(0.7, 4.7, -0.95), WHITE),
		P("Ball", Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 4.1, -1.3), Color3.fromRGB(255, 140, 20), { m = Enum.Material.Neon }),
	})
end
designs.stoneslammer = function()
	local stone = Color3.fromRGB(160, 160, 170)
	return concat({
		P("Block", Vector3.new(5, 6.4, 1.8), Vector3.new(0, 3.9, 0), stone, { m = Enum.Material.Slate }),
		P("Block", Vector3.new(1.0, 2.6, 1.0), Vector3.new(-3.0, 3.6, 0), stone, { m = Enum.Material.Slate }),
		P("Block", Vector3.new(1.0, 2.6, 1.0), Vector3.new(3.0, 3.6, 0), stone, { m = Enum.Material.Slate }),
		P("Block", Vector3.new(1.4, 0.7, 2.0), Vector3.new(-1.3, 0.35, -0.2), stone, { m = Enum.Material.Slate }),
		P("Block", Vector3.new(1.4, 0.7, 2.0), Vector3.new(1.3, 0.35, -0.2), stone, { m = Enum.Material.Slate }),
		P("Block", Vector3.new(1.2, 0.3, 0.2), Vector3.new(0, 3.6, -0.95), BLACK),
	}, eyes(5.0, -0.95, 0.9, 0.8), angryBrows(5.8, -1.0, 0.9, 1.0))
end
designs.chainchomper = function()
	local specs = {
		P("Ball", Vector3.new(4.2, 4.2, 4.2), Vector3.new(0, 2.8, 0), BLACK, { m = Enum.Material.Metal }),
		P("Block", Vector3.new(2.8, 1.0, 0.4), Vector3.new(0, 2.2, -1.9), Color3.fromRGB(200, 30, 40)),
		P("Cylinder", Vector3.new(1.6, 0.8, 0.8), Vector3.new(0, 0.8, 2.6), Color3.fromRGB(130, 90, 50), { r = Vector3.new(0, 0, 90) }),
	}
	for i = -2, 2 do
		table.insert(specs, P("Wedge", Vector3.new(0.4, 0.5, 0.3), Vector3.new(i * 0.5, 2.55, -2.05), WHITE, { r = Vector3.new(180, 0, 0) }))
	end
	for i = 1, 3 do
		table.insert(specs, P("Ball", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 1.0 + i * 0.1, 1.6 + i * 0.3), Color3.fromRGB(120, 120, 130), { m = Enum.Material.Metal }))
	end
	return concat(specs, eyes(3.3, -1.75, 0.7, 0.8))
end
designs.starsage = function()
	return concat({
		P("Cylinder", Vector3.new(1.4, 0.6, 0.6), Vector3.new(0, 0.7, 0), Color3.fromRGB(110, 70, 40), { r = Vector3.new(0, 0, 90) }),
		P("Ball", Vector3.new(3.0, 3.4, 3.0), Vector3.new(0, 3.0, 0), Color3.fromRGB(150, 100, 60)),
		P("Ball", Vector3.new(2.0, 2.4, 1.0), Vector3.new(0, 2.7, -1.1), Color3.fromRGB(240, 220, 180)),
		P("Ball", Vector3.new(0.8, 2.2, 1.8), Vector3.new(-1.6, 3.0, 0.2), Color3.fromRGB(120, 80, 50)),
		P("Ball", Vector3.new(0.8, 2.2, 1.8), Vector3.new(1.6, 3.0, 0.2), Color3.fromRGB(120, 80, 50)),
		P("Wedge", Vector3.new(0.4, 0.5, 0.5), Vector3.new(0, 3.4, -1.5), Color3.fromRGB(255, 160, 40), { r = Vector3.new(180, 0, 0) }),
		P("Block", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 5.0, 0), GOLD, { r = Vector3.new(0, 45, 45), m = Enum.Material.Neon }),
	}, eyes(3.9, -1.25, 0.55, 0.8, Color3.fromRGB(255, 160, 0)))
end
designs.captaincomet = function()
	local suit = Color3.fromRGB(40, 70, 200)
	return concat({
		P("Cylinder", Vector3.new(1.6, 0.8, 0.8), Vector3.new(-0.5, 0.8, 0), suit, { r = Vector3.new(0, 0, 90) }),
		P("Cylinder", Vector3.new(1.6, 0.8, 0.8), Vector3.new(0.5, 0.8, 0), suit, { r = Vector3.new(0, 0, 90) }),
		P("Ball", Vector3.new(1.0, 0.6, 1.3), Vector3.new(-0.5, 0.2, -0.2), Color3.fromRGB(120, 70, 40)),
		P("Ball", Vector3.new(1.0, 0.6, 1.3), Vector3.new(0.5, 0.2, -0.2), Color3.fromRGB(120, 70, 40)),
		P("Ball", Vector3.new(2.2, 2.2, 1.8), Vector3.new(0, 2.4, 0), WHITE),
		P("Block", Vector3.new(0.8, 0.8, 0.2), Vector3.new(0, 2.6, -0.9), GOLD, { r = Vector3.new(0, 0, 45), m = Enum.Material.Neon }),
		P("Ball", Vector3.new(0.7, 1.6, 0.7), Vector3.new(-1.3, 2.4, 0), WHITE),
		P("Ball", Vector3.new(0.7, 1.6, 0.7), Vector3.new(1.3, 2.4, 0), WHITE),
		P("Ball", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, 4.0, 0), SKIN),
		P("Ball", Vector3.new(2.0, 1.0, 2.0), Vector3.new(0, 4.6, 0.1), suit),
		P("Block", Vector3.new(2.0, 0.2, 0.9), Vector3.new(0, 4.4, -0.9), suit),
		P("Block", Vector3.new(0.5, 0.5, 0.15), Vector3.new(0, 4.75, -0.95), GOLD, { r = Vector3.new(0, 0, 45), m = Enum.Material.Neon }),
		P("Block", Vector3.new(2.6, 3.2, 0.2), Vector3.new(0, 2.4, 1.0), Color3.fromRGB(230, 40, 50), { r = Vector3.new(-8, 0, 0) }),
	}, eyes(4.1, -0.85, 0.3, 0.4, Color3.fromRGB(40, 90, 220)))
end
designs.infernodrake = function()
	local skin = Color3.fromRGB(240, 190, 60)
	local specs = {
		P("Ball", Vector3.new(4.6, 4.0, 4.6), Vector3.new(0, 3.4, 0.6), Color3.fromRGB(40, 130, 60)),
		P("Ball", Vector3.new(3.6, 3.6, 3.0), Vector3.new(0, 3.0, -0.9), skin),
		P("Ball", Vector3.new(2.6, 2.4, 2.6), Vector3.new(0, 5.7, -1.4), skin),
		P("Ball", Vector3.new(1.8, 1.2, 1.6), Vector3.new(0, 5.2, -2.6), Color3.fromRGB(250, 220, 150)),
		P("Ball", Vector3.new(2.6, 1.4, 2.0), Vector3.new(0, 6.9, -0.7), Color3.fromRGB(230, 70, 30)),
		P("Wedge", Vector3.new(0.4, 1.2, 0.6), Vector3.new(-0.9, 7.2, -1.6), WHITE),
		P("Wedge", Vector3.new(0.4, 1.2, 0.6), Vector3.new(0.9, 7.2, -1.6), WHITE),
		P("Ball", Vector3.new(1.3, 1.2, 1.8), Vector3.new(-1.2, 0.6, -0.5), skin),
		P("Ball", Vector3.new(1.3, 1.2, 1.8), Vector3.new(1.2, 0.6, -0.5), skin),
	}
	for _, p in { Vector3.new(-1.2, 5.1, 1.4), Vector3.new(1.2, 5.1, 1.4), Vector3.new(0, 5.4, 1.8), Vector3.new(-1.8, 3.6, 2.4), Vector3.new(1.8, 3.6, 2.4) } do
		table.insert(specs, P("Ball", Vector3.new(0.7, 0.9, 0.7), p, WHITE))
	end
	return concat(specs, eyes(6.1, -2.5, 0.55, 0.6, Color3.fromRGB(200, 30, 30)), angryBrows(6.6, -2.6, 0.55, 0.8))
end
designs.starprincess = function()
	local pink = Color3.fromRGB(255, 150, 200)
	return concat({
		P("Cylinder", Vector3.new(1.0, 3.6, 3.6), Vector3.new(0, 0.5, 0), pink, { r = Vector3.new(0, 0, 90) }),
		P("Cylinder", Vector3.new(1.2, 3.0, 3.0), Vector3.new(0, 1.5, 0), pink, { r = Vector3.new(0, 0, 90) }),
		P("Cylinder", Vector3.new(1.2, 2.3, 2.3), Vector3.new(0, 2.6, 0), pink, { r = Vector3.new(0, 0, 90) }),
		P("Ball", Vector3.new(1.8, 1.4, 1.4), Vector3.new(0, 3.6, 0), Color3.fromRGB(255, 120, 180)),
		P("Ball", Vector3.new(1.7, 1.8, 1.7), Vector3.new(0, 4.8, 0), SKIN),
		P("Ball", Vector3.new(2.0, 2.2, 1.9), Vector3.new(0, 5.1, 0.35), GOLD),
		P("Cylinder", Vector3.new(0.6, 1.0, 1.0), Vector3.new(0, 6.0, 0), GOLD, { r = Vector3.new(0, 0, 90), m = Enum.Material.Metal }),
		P("Ball", Vector3.new(0.35, 0.35, 0.35), Vector3.new(0, 6.0, -0.5), Color3.fromRGB(80, 160, 255), { m = Enum.Material.Neon }),
		P("Cylinder", Vector3.new(2.4, 0.2, 0.2), Vector3.new(1.4, 3.4, -0.6), WHITE, { r = Vector3.new(0, 0, 70) }),
		P("Block", Vector3.new(0.8, 0.8, 0.2), Vector3.new(1.8, 4.6, -0.6), GOLD, { r = Vector3.new(0, 0, 45), m = Enum.Material.Neon }),
	}, eyes(4.9, -0.8, 0.3, 0.4, Color3.fromRGB(40, 90, 220)))
end

-- ===== enemies =====
designs.grumble = function()
	return mushroom(Color3.fromRGB(140, 80, 40), Color3.fromRGB(170, 110, 60), Color3.fromRGB(240, 210, 170), BLACK, true)
end
designs.sprinter = function()
	return concat(mushroom(Color3.fromRGB(200, 140, 70), Color3.fromRGB(220, 170, 100), Color3.fromRGB(240, 210, 170), BLACK, true), {
		P("Cylinder", Vector3.new(0.4, 3.5, 3.5), Vector3.new(0, 2.25, 0), Color3.fromRGB(230, 30, 30), { r = Vector3.new(0, 0, 90) }),
	})
end
designs.shellguard = function()
	return turtle(Color3.fromRGB(210, 40, 40), Color3.fromRGB(255, 220, 80), true)
end
designs.splitter = function()
	return bomb(Color3.fromRGB(40, 40, 50), Color3.fromRGB(255, 170, 40), true)
end
designs.minibomb = designs.splitter
designs.flutter = function()
	return concat({
		P("Ball", Vector3.new(2.6, 2.8, 2.6), Vector3.new(0, 1.6, 0), Color3.fromRGB(220, 40, 60)),
		P("Ball", Vector3.new(1.9, 1.9, 0.8), Vector3.new(0, 2.0, -1.0), WHITE),
		P("Ball", Vector3.new(0.35, 0.55, 0.2), Vector3.new(-0.35, 2.3, -1.4), BLACK),
		P("Ball", Vector3.new(0.35, 0.55, 0.2), Vector3.new(0.35, 2.3, -1.4), BLACK),
		P("Ball", Vector3.new(0.4, 0.4, 0.2), Vector3.new(0, 1.7, -1.4), BLACK),
		P("Cylinder", Vector3.new(0.8, 0.3, 0.3), Vector3.new(0, 3.3, 0), Color3.fromRGB(80, 80, 90), { r = Vector3.new(0, 0, 90) }),
		P("Block", Vector3.new(3.4, 0.1, 0.5), Vector3.new(0, 3.7, 0), Color3.fromRGB(255, 220, 60)),
		P("Ball", Vector3.new(0.8, 0.6, 1.0), Vector3.new(-0.6, 0.3, 0), Color3.fromRGB(60, 60, 200)),
		P("Ball", Vector3.new(0.8, 0.6, 1.0), Vector3.new(0.6, 0.3, 0), Color3.fromRGB(60, 60, 200)),
	})
end
designs.phantom = function()
	return ghost(Color3.fromRGB(235, 225, 255), 0.3, true)
end
designs.skyray = function()
	return concat({
		P("Ball", Vector3.new(5.0, 0.9, 3.2), Vector3.new(0, 1.2, 0), Color3.fromRGB(130, 60, 200)),
		P("Ball", Vector3.new(2.0, 1.1, 1.8), Vector3.new(0, 1.4, -0.9), Color3.fromRGB(160, 90, 230)),
		P("Cylinder", Vector3.new(3.0, 0.25, 0.25), Vector3.new(0, 1.2, 2.8), Color3.fromRGB(100, 40, 160), { r = Vector3.new(0, 90, 0) }),
	}, eyes(1.7, -1.75, 0.5, 0.4, Color3.fromRGB(255, 220, 0)))
end
designs.kinggrumble = function()
	return concat(designs.grumble(), {
		P("Cylinder", Vector3.new(0.9, 1.6, 1.6), Vector3.new(0, 4.1, 0), GOLD, { r = Vector3.new(0, 0, 90), m = Enum.Material.Metal }),
		P("Ball", Vector3.new(0.35, 0.35, 0.35), Vector3.new(0, 4.3, -0.8), Color3.fromRGB(255, 40, 40), { m = Enum.Material.Neon }),
		P("Ball", Vector3.new(1.4, 0.4, 0.4), Vector3.new(0, 1.1, -1.05), BLACK),
	})
end
designs.sandwyvern = function()
	local body = Color3.fromRGB(230, 150, 60)
	return concat({
		P("Ball", Vector3.new(2.4, 2.0, 3.6), Vector3.new(0, 2.0, 0), body),
		P("Ball", Vector3.new(1.6, 1.4, 1.8), Vector3.new(0, 2.8, -2.2), body),
		P("Wedge", Vector3.new(0.3, 1.5, 3.6), Vector3.new(-2.6, 2.4, 0), Color3.fromRGB(200, 110, 40), { r = Vector3.new(0, 0, 70) }),
		P("Wedge", Vector3.new(0.3, 1.5, 3.6), Vector3.new(2.6, 2.4, 0), Color3.fromRGB(200, 110, 40), { r = Vector3.new(0, 0, -70) }),
		P("Cylinder", Vector3.new(2.6, 0.5, 0.5), Vector3.new(0, 1.8, 2.8), body, { r = Vector3.new(0, 90, 0) }),
		P("Wedge", Vector3.new(0.3, 0.7, 0.6), Vector3.new(-0.5, 3.6, -2.0), WHITE),
		P("Wedge", Vector3.new(0.3, 0.7, 0.6), Vector3.new(0.5, 3.6, -2.0), WHITE),
	}, eyes(3.0, -3.0, 0.4, 0.4, Color3.fromRGB(255, 60, 0)))
end
designs.frostgolem = function()
	local ice = Color3.fromRGB(150, 210, 255)
	return concat({
		P("Block", Vector3.new(2.8, 2.6, 2.2), Vector3.new(0, 2.6, 0), ice, { m = Enum.Material.Ice }),
		P("Block", Vector3.new(1.8, 1.6, 1.6), Vector3.new(0, 4.6, 0), ice, { m = Enum.Material.Ice }),
		P("Block", Vector3.new(1.0, 2.4, 1.0), Vector3.new(-2.0, 2.4, 0), ice, { m = Enum.Material.Ice }),
		P("Block", Vector3.new(1.0, 2.4, 1.0), Vector3.new(2.0, 2.4, 0), ice, { m = Enum.Material.Ice }),
		P("Block", Vector3.new(1.0, 1.4, 1.2), Vector3.new(-0.8, 0.7, 0), ice, { m = Enum.Material.Ice }),
		P("Block", Vector3.new(1.0, 1.4, 1.2), Vector3.new(0.8, 0.7, 0), ice, { m = Enum.Material.Ice }),
		P("Ball", Vector3.new(0.4, 0.4, 0.2), Vector3.new(-0.4, 4.8, -0.82), Color3.fromRGB(40, 120, 255), { m = Enum.Material.Neon }),
		P("Ball", Vector3.new(0.4, 0.4, 0.2), Vector3.new(0.4, 4.8, -0.82), Color3.fromRGB(40, 120, 255), { m = Enum.Material.Neon }),
	})
end
designs.lavatitan = function()
	local rock = Color3.fromRGB(60, 45, 45)
	local lava = Color3.fromRGB(255, 90, 20)
	return {
		P("Ball", Vector3.new(3.4, 3.0, 2.8), Vector3.new(0, 2.8, 0), rock, { m = Enum.Material.Basalt }),
		P("Ball", Vector3.new(1.8, 1.7, 1.7), Vector3.new(0, 4.7, -0.3), rock, { m = Enum.Material.Basalt }),
		P("Ball", Vector3.new(1.2, 2.6, 1.2), Vector3.new(-2.1, 2.6, 0), rock, { m = Enum.Material.Basalt }),
		P("Ball", Vector3.new(1.2, 2.6, 1.2), Vector3.new(2.1, 2.6, 0), rock, { m = Enum.Material.Basalt }),
		P("Ball", Vector3.new(1.2, 1.6, 1.3), Vector3.new(-0.8, 0.8, 0), rock, { m = Enum.Material.Basalt }),
		P("Ball", Vector3.new(1.2, 1.6, 1.3), Vector3.new(0.8, 0.8, 0), rock, { m = Enum.Material.Basalt }),
		P("Block", Vector3.new(2.2, 0.25, 0.3), Vector3.new(0, 3.0, -1.35), lava, { m = Enum.Material.Neon, r = Vector3.new(0, 0, 25) }),
		P("Block", Vector3.new(1.6, 0.25, 0.3), Vector3.new(0.3, 2.2, -1.3), lava, { m = Enum.Material.Neon, r = Vector3.new(0, 0, -30) }),
		P("Ball", Vector3.new(0.45, 0.35, 0.2), Vector3.new(-0.4, 4.9, -1.1), lava, { m = Enum.Material.Neon }),
		P("Ball", Vector3.new(0.45, 0.35, 0.2), Vector3.new(0.4, 4.9, -1.1), lava, { m = Enum.Material.Neon }),
	}
end
designs.shadowmonarch = function()
	local armor = Color3.fromRGB(50, 30, 80)
	local glow = Color3.fromRGB(190, 80, 255)
	return {
		P("Block", Vector3.new(3.2, 0.4, 0.2), Vector3.new(0, 2.6, 1.1), Color3.fromRGB(120, 20, 40), { r = Vector3.new(-10, 0, 0) }),
		P("Block", Vector3.new(3.0, 3.6, 0.2), Vector3.new(0, 2.6, 1.15), Color3.fromRGB(120, 20, 40), { r = Vector3.new(-10, 0, 0) }),
		P("Block", Vector3.new(2.4, 2.6, 1.6), Vector3.new(0, 2.8, 0), armor, { m = Enum.Material.Metal }),
		P("Block", Vector3.new(0.8, 1.8, 0.9), Vector3.new(-0.6, 0.9, 0), armor, { m = Enum.Material.Metal }),
		P("Block", Vector3.new(0.8, 1.8, 0.9), Vector3.new(0.6, 0.9, 0), armor, { m = Enum.Material.Metal }),
		P("Ball", Vector3.new(1.2, 1.2, 1.2), Vector3.new(-1.6, 3.8, 0), armor, { m = Enum.Material.Metal }),
		P("Ball", Vector3.new(1.2, 1.2, 1.2), Vector3.new(1.6, 3.8, 0), armor, { m = Enum.Material.Metal }),
		P("Ball", Vector3.new(1.6, 1.7, 1.6), Vector3.new(0, 4.8, 0), armor, { m = Enum.Material.Metal }),
		P("Cylinder", Vector3.new(0.7, 1.7, 1.7), Vector3.new(0, 5.8, 0), Color3.fromRGB(140, 60, 220), { r = Vector3.new(0, 0, 90), m = Enum.Material.Metal }),
		P("Ball", Vector3.new(0.4, 0.25, 0.2), Vector3.new(-0.35, 4.9, -0.78), glow, { m = Enum.Material.Neon }),
		P("Ball", Vector3.new(0.4, 0.25, 0.2), Vector3.new(0.35, 4.9, -0.78), glow, { m = Enum.Material.Neon }),
		P("Block", Vector3.new(0.6, 0.6, 0.2), Vector3.new(0, 3.1, -0.85), glow, { m = Enum.Material.Neon, r = Vector3.new(0, 0, 45) }),
	}
end

function ModelFactory.has(key: string): boolean
	return designs[key] ~= nil
end

-- ============================================================ custom models
-- A Model in ReplicatedStorage.CustomModels named after a unit or enemy id (e.g. "captaincomet", "grumble")
-- replaces the built-in model: it is scaled to the unit's height, stood on its feet and welded to a Root. Models are
-- expected to face -Z (Roblox's front; a "FaceYaw" attribute in degrees turns one that doesn't). A "DisplayName"
-- attribute on it renames the unit or enemy in the UI. tools/sm64_import makes these from your own SM64 ROM.

local function customModel(key: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("CustomModels")
	local m = folder and folder:FindFirstChild(key)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

-- the height a model is built at (scale 1)
function ModelFactory.height(key: string): number
	local unit = Units.ById[key]
	if unit then
		return unit.height
	end
	return 4.5
end

function ModelFactory.displayName(key: string, fallback: string): string
	local m = customModel(key)
	local name = m and m:GetAttribute("DisplayName")
	return type(name) == "string" and name ~= "" and name or fallback
end

local function buildCustom(source: Model, key: string, scale: number, anchored: boolean?): Model
	local model = source:Clone()
	model.Name = key
	for _, d in model:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Humanoid") or d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		end
	end
	local _, size = model:GetBoundingBox()
	local target = ModelFactory.height(key) * scale
	if size.Y > 0 then
		model:ScaleTo(model:GetScale() * target / size.Y)
	end
	local cf, newSize = model:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1) * scale
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new(cf.Position.X, cf.Position.Y - newSize.Y / 2, cf.Position.Z)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
			if anchored then
				d.Anchored = true
			else
				d.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
	root.Parent = model
	model.PrimaryPart = root
	-- the model's origin is its feet, at the world origin like the built-in models. A "FaceYaw" attribute (degrees)
	-- turns a model that was imported facing the wrong way.
	local yaw = source:GetAttribute("FaceYaw")
	model:PivotTo(CFrame.Angles(0, math.rad(type(yaw) == "number" and yaw or 0), 0))
	return model
end

-- ============================================================ build

-- anchored = true anchors every part (viewports, previews); otherwise only Root is anchored and the rest is welded.
function ModelFactory.build(key: string, scale: number?, anchored: boolean?): Model
	local custom = customModel(key)
	if custom then
		return buildCustom(custom, key, scale or 1, anchored)
	end
	local design = designs[key] or designs.grumble
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = key

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1) * s
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	for i, spec in design() do
		local shape, size, pos, color, extras = spec[1], spec[2], spec[3], spec[4], spec[5]
		local part: BasePart
		if shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			if shape == "Ball" then
				-- Ball parts are always perfect spheres; a sphere mesh stretches to the part's size (ellipsoids)
				local mesh = Instance.new("SpecialMesh")
				mesh.MeshType = Enum.MeshType.Sphere
				mesh.Parent = p
			elseif shape == "Cylinder" then
				p.Shape = Enum.PartType.Cylinder
			end
			part = p
		end
		part.Name = "P" .. i
		part.Size = size * s
		local rot = extras.r or Vector3.zero
		part.CFrame = CFrame.new(pos * s) * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		part.Color = color
		part.Material = extras.m or Enum.Material.SmoothPlastic
		part.Transparency = extras.t or 0
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = s >= 1
		if anchored then
			part.Anchored = true
		else
			part.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
		part.Parent = model
	end
	return model
end

return ModelFactory
