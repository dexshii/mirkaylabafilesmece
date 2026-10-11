-- Enemies walk (or fly above) the map's path toward your castle.
--   kind: "ground" | "flying"; boss = true for boss enemies (they can be ground or flying)
--   hp / speed (studs per second) / cash (paid on kill) / leak (base damage if it reaches the castle)
--   armor: fraction of damage ignored
--   ability (bosses): see Battle.luau, "summon" | "stun" | "dash" | "shield" | "monarch"
local Enemies = {}

export type EnemyDef = {
	id: string,
	name: string,
	kind: string,
	boss: boolean?,
	hp: number,
	speed: number,
	cash: number,
	leak: number,
	armor: number?,
	splitInto: string?,
	ability: { [string]: any }?,
	scale: number?,
	desc: string,
}

local list: { EnemyDef } = {
	-- ground
	{ id = "grumble", name = "Grumble", kind = "ground", hp = 40, speed = 6, cash = 8, leak = 2, desc = "An angry mushroom. Walks." },
	{ id = "sprinter", name = "Dash Grumble", kind = "ground", hp = 26, speed = 11, cash = 7, leak = 2, desc = "Fast and fragile." },
	{
		id = "shellguard",
		name = "Shellguard",
		kind = "ground",
		hp = 120,
		speed = 4.5,
		cash = 14,
		leak = 4,
		armor = 0.3,
		desc = "Hides in its shell: takes 30% less damage.",
	},
	{
		id = "splitter",
		name = "Fuse Brute",
		kind = "ground",
		hp = 75,
		speed = 5.5,
		cash = 10,
		leak = 3,
		splitInto = "minibomb",
		desc = "Splits into two Mini Fuses when defeated.",
	},
	{ id = "minibomb", name = "Mini Fuse", kind = "ground", hp = 22, speed = 8, cash = 3, leak = 1, scale = 0.6, desc = "Small and quick." },

	-- flying
	{ id = "flutter", name = "Flutter Guy", kind = "flying", hp = 32, speed = 8, cash = 9, leak = 2, desc = "A masked flyer. Only anti-air units can hit it." },
	{
		id = "phantom",
		name = "Phantom",
		kind = "flying",
		hp = 95,
		speed = 5,
		cash = 14,
		leak = 4,
		armor = 0.15,
		desc = "A floating ghost. Tough, and only anti-air units can hit it.",
	},
	{ id = "skyray", name = "Sky Ray", kind = "flying", hp = 60, speed = 10.5, cash = 12, leak = 3, desc = "A fast flying manta." },

	-- bosses
	{
		id = "kinggrumble",
		name = "King Grumble",
		kind = "ground",
		boss = true,
		hp = 1950,
		speed = 3,
		cash = 300,
		leak = 999,
		scale = 3,
		ability = { type = "summon", every = 8, enemy = "grumble", count = 3 },
		desc = "Calls in Grumbles every 8 seconds.",
	},
	{
		id = "sandwyvern",
		name = "Sandstorm Wyvern",
		kind = "flying",
		boss = true,
		hp = 1700,
		speed = 4.5,
		cash = 320,
		leak = 999,
		scale = 2.6,
		ability = { type = "dash", every = 9, mult = 2.5, dur = 2 },
		desc = "A flying boss that dashes forward every 9 seconds.",
	},
	{
		id = "frostgolem",
		name = "Frost Golem",
		kind = "ground",
		boss = true,
		hp = 3150,
		speed = 2.6,
		cash = 360,
		leak = 999,
		armor = 0.1,
		scale = 3,
		ability = { type = "stun", every = 9, radius = 20, dur = 2.5 },
		desc = "Freezes (stuns) your units around it every 9 seconds.",
	},
	{
		id = "lavatitan",
		name = "Magma Titan",
		kind = "ground",
		boss = true,
		hp = 4350,
		speed = 2.4,
		cash = 400,
		leak = 999,
		scale = 3.2,
		ability = { type = "shield", every = 12, dur = 2, heal = 0.05 },
		desc = "Every 12 seconds turns invulnerable for 2 seconds and heals 5%.",
	},
	{
		id = "shadowmonarch",
		name = "Shadow Monarch",
		kind = "ground",
		boss = true,
		hp = 7100,
		speed = 2.5,
		cash = 600,
		leak = 999,
		armor = 0.15,
		scale = 3.4,
		ability = { type = "monarch", every = 10, enemy = "phantom", count = 2, radius = 18, dur = 2 },
		desc = "The final boss. Summons Phantoms and stuns units every 10 seconds.",
	},
}

Enemies.List = list
Enemies.ById = {} :: { [string]: EnemyDef }
for _, def in list do
	Enemies.ById[def.id] = def
end

Enemies.FlyHeight = 9

return Enemies
