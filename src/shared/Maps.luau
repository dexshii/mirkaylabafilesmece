-- Campaign maps. Each map has 5 stages; clearing stage 5 (the boss) unlocks the next map.
-- Waypoints are {x, z} in studs on a 240 x 240 field centred on the arena origin; enemies walk them in order and the
-- castle stands on the last one.
local Maps = {}

export type MapDef = {
	id: string,
	name: string,
	desc: string,
	theme: { [string]: any },
	waypoints: { { number } },
	ground: { string },
	flying: { string },
	boss: string,
	hpMult: number,
}

local list: { MapDef } = {
	{
		id = "meadow",
		name = "Mushroom Meadow",
		desc = "Rolling green hills. A gentle start.",
		theme = {
			ground = Color3.fromRGB(96, 190, 80),
			groundMaterial = Enum.Material.Grass,
			path = Color3.fromRGB(214, 180, 120),
			pathMaterial = Enum.Material.Sand,
			decor = "tree",
			clock = 14,
			ambient = Color3.fromRGB(120, 120, 130),
			fog = Color3.fromRGB(170, 210, 255),
		},
		waypoints = { { -115, -80 }, { -40, -80 }, { -40, 40 }, { 40, 40 }, { 40, -60 }, { 100, -60 }, { 100, 85 } },
		ground = { "grumble", "sprinter", "shellguard" },
		flying = { "flutter" },
		boss = "kinggrumble",
		hpMult = 1,
	},
	{
		id = "desert",
		name = "Dusty Dunes",
		desc = "Scorching sand and skies full of flyers.",
		theme = {
			ground = Color3.fromRGB(232, 200, 120),
			groundMaterial = Enum.Material.Sand,
			path = Color3.fromRGB(180, 130, 80),
			pathMaterial = Enum.Material.Sandstone,
			decor = "cactus",
			clock = 12,
			ambient = Color3.fromRGB(150, 130, 100),
			fog = Color3.fromRGB(255, 225, 170),
		},
		waypoints = { { -115, 0 }, { -60, 0 }, { -60, -90 }, { 0, -90 }, { 0, 90 }, { 60, 90 }, { 60, 0 }, { 110, 0 } },
		ground = { "grumble", "sprinter", "splitter" },
		flying = { "flutter", "skyray" },
		boss = "sandwyvern",
		hpMult = 1.5,
	},
	{
		id = "frost",
		name = "Frosty Peaks",
		desc = "A long zig-zag through the snow.",
		theme = {
			ground = Color3.fromRGB(235, 245, 255),
			groundMaterial = Enum.Material.Snow,
			path = Color3.fromRGB(150, 200, 235),
			pathMaterial = Enum.Material.Ice,
			decor = "pine",
			clock = 9,
			ambient = Color3.fromRGB(140, 150, 180),
			fog = Color3.fromRGB(220, 235, 255),
		},
		waypoints = { { -115, -90 }, { 90, -90 }, { 90, -30 }, { -90, -30 }, { -90, 30 }, { 90, 30 }, { 90, 90 }, { -110, 90 } },
		ground = { "grumble", "shellguard", "splitter" },
		flying = { "phantom", "flutter" },
		boss = "frostgolem",
		hpMult = 2.1,
	},
	{
		id = "magma",
		name = "Magma Fortress",
		desc = "A spiral of stone over boiling lava.",
		theme = {
			ground = Color3.fromRGB(70, 55, 55),
			groundMaterial = Enum.Material.Basalt,
			path = Color3.fromRGB(120, 90, 80),
			pathMaterial = Enum.Material.Cobblestone,
			decor = "lavarock",
			clock = 20,
			ambient = Color3.fromRGB(150, 80, 60),
			fog = Color3.fromRGB(120, 40, 20),
		},
		waypoints = {
			{ -115, -100 },
			{ 100, -100 },
			{ 100, 100 },
			{ -90, 100 },
			{ -90, -60 },
			{ 60, -60 },
			{ 60, 60 },
			{ -50, 60 },
			{ -50, -20 },
			{ 20, -20 },
			{ 20, 20 },
		},
		ground = { "sprinter", "shellguard", "splitter" },
		flying = { "skyray", "phantom" },
		boss = "lavatitan",
		hpMult = 2.8,
	},
	{
		id = "starcastle",
		name = "Star Castle",
		desc = "The Shadow Monarch's throne. The final battle.",
		theme = {
			ground = Color3.fromRGB(90, 70, 140),
			groundMaterial = Enum.Material.Marble,
			path = Color3.fromRGB(240, 220, 120),
			pathMaterial = Enum.Material.SmoothPlastic,
			decor = "pillar",
			clock = 0,
			ambient = Color3.fromRGB(110, 90, 160),
			fog = Color3.fromRGB(40, 30, 80),
		},
		waypoints = { { 0, -115 }, { 0, -70 }, { -90, -70 }, { -90, 0 }, { 90, 0 }, { 90, 70 }, { 0, 70 }, { 0, 110 } },
		ground = { "grumble", "splitter", "shellguard" },
		flying = { "phantom", "skyray" },
		boss = "shadowmonarch",
		hpMult = 3.6,
	},
}

Maps.List = list
Maps.ById = {} :: { [string]: MapDef }
Maps.Index = {} :: { [string]: number }
for i, def in list do
	Maps.ById[def.id] = def
	Maps.Index[def.id] = i
end

Maps.Stages = 5
Maps.FieldHalf = 120
Maps.PathWidth = 9
Maps.StartCash = 800
Maps.StartCashPerMap = 250
Maps.BaseHealth = 100

export type Group = { enemy: string, count: number, interval: number, delay: number }
export type Wave = { groups: { Group }, hpMult: number, bossMult: number }

local function add(groups: { Group }, enemy: string, count: number, interval: number)
	if count > 0 then
		table.insert(groups, { enemy = enemy, count = count, interval = interval, delay = #groups * 2.5 })
	end
end

-- The waves of one campaign stage (or challenge, through modifiers).
function Maps.buildWaves(def: MapDef, stage: number, modifiers: { [string]: any }?): { Wave }
	local mods = modifiers or {}
	local waves: { Wave } = {}
	local base = def.hpMult * (1 + 0.10 * (stage - 1))

	if mods.bossRush then
		-- every map's boss, one per wave, each with escorts, scaled to this map
		for i, m in list do
			local groups = {}
			add(groups, m.ground[1], 4 + i, 0.8)
			add(groups, m.flying[1], 2 + i, 1)
			add(groups, m.boss, 1, 1)
			table.insert(waves, { groups = groups, hpMult = base * (0.55 + 0.15 * i), bossMult = base * (0.55 + 0.15 * i) })
		end
		return waves
	end

	local count = 6 + 2 * stage
	for w = 1, count do
		local groups = {}
		local extra = stage - 1
		add(groups, def.ground[1], 3 + w * 2 + extra, math.max(0.45, 1.1 - w * 0.04))
		if w >= 3 then
			add(groups, def.ground[2], math.floor(w / 2) + extra, 0.7)
		end
		if w >= 4 then
			local flyer = def.flying[(w % #def.flying) + 1]
			add(groups, flyer, math.floor(w / 2) + (mods.extraFlying and w or 0), 0.9)
		elseif mods.extraFlying then
			add(groups, def.flying[1], w + 1, 0.9)
		end
		if w >= 5 then
			add(groups, def.ground[3], math.floor((w - 3) / 2) + math.floor(extra / 2), 1.2)
		end
		if w == count and stage == Maps.Stages then
			add(groups, def.boss, 1, 1)
		elseif w == count and stage >= 3 then
			-- a mini-boss wave: a big push of the toughest regular enemy
			add(groups, def.ground[3], 4 + stage, 0.8)
		end
		-- every stage starts near base health and ramps to the map's full multiplier by its last wave
		local ramp = w / count
		table.insert(waves, { groups = groups, hpMult = (1 + 0.10 * (w - 1)) * (1 + (base - 1) * ramp), bossMult = base })
	end
	return waves
end

return Maps
