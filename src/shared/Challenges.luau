-- Challenges: harder runs of a campaign stage with modifiers. Clearing one awards Trait Crystals.
-- Each challenge pays its full reward once per day (UTC); replays the same day pay `repeatGems` only.
-- Modifiers (see Battle.luau): enemyHp, enemySpeed (multipliers), extraFlying, bossRush, startCash and killCash
-- (multipliers), onlyRarity (only units of that rarity can be placed), maxUnits (total units on the map).
local Challenges = {}

export type ChallengeDef = {
	id: string,
	name: string,
	desc: string,
	map: string,
	stage: number,
	modifiers: { [string]: any },
	crystals: number,
	gems: number,
	repeatGems: number,
}

local list: { ChallengeDef } = {
	{
		id = "skyswarm",
		name = "Sky Swarm",
		desc = "Every wave brings extra flyers. Bring anti-air!",
		map = "meadow",
		stage = 3,
		modifiers = { extraFlying = true },
		crystals = 3,
		gems = 60,
		repeatGems = 15,
	},
	{
		id = "speeddemons",
		name = "Speed Demons",
		desc = "Enemies move 50% faster.",
		map = "meadow",
		stage = 4,
		modifiers = { enemySpeed = 1.5 },
		crystals = 3,
		gems = 60,
		repeatGems = 15,
	},
	{
		id = "commonfolk",
		name = "Common Folk",
		desc = "Only Common units can be placed.",
		map = "desert",
		stage = 2,
		modifiers = { onlyRarity = "Common" },
		crystals = 4,
		gems = 80,
		repeatGems = 20,
	},
	{
		id = "budgetcuts",
		name = "Budget Cuts",
		desc = "Half the starting cash and 40% less cash from kills.",
		map = "desert",
		stage = 4,
		modifiers = { startCash = 0.5, killCash = 0.6 },
		crystals = 4,
		gems = 80,
		repeatGems = 20,
	},
	{
		id = "ironhide",
		name = "Iron Hide",
		desc = "Enemies have double health.",
		map = "frost",
		stage = 3,
		modifiers = { enemyHp = 2 },
		crystals = 5,
		gems = 100,
		repeatGems = 25,
	},
	{
		id = "smallsquad",
		name = "Small Squad",
		desc = "At most 6 units on the map at once.",
		map = "magma",
		stage = 3,
		modifiers = { maxUnits = 6 },
		crystals = 6,
		gems = 120,
		repeatGems = 30,
	},
	{
		id = "bossrush",
		name = "Boss Rush",
		desc = "Every boss in the kingdom, one after another.",
		map = "starcastle",
		stage = 1,
		modifiers = { bossRush = true },
		crystals = 10,
		gems = 200,
		repeatGems = 40,
	},
}

Challenges.List = list
Challenges.ById = {} :: { [string]: ChallengeDef }
for _, def in list do
	Challenges.ById[def.id] = def
end

function Challenges.today(): number
	return math.floor(os.time() / 86400)
end

return Challenges
