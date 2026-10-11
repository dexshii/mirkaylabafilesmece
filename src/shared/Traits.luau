-- Traits are rolled onto a unit with Trait Crystals (earned from challenges). A unit holds one trait; rolling again
-- replaces it. Every trait has its own chance (`chance`, in percent; they add up to 100), and the rarest ones have
-- pity: after `pity` rolls without it, the next roll gives it.
-- Effect fields (all optional):
--   damage / speed / range: +fraction (speed lowers SPA: the cooldown is multiplied by 1 - speed)
--   crit = { chance, damage }: +fraction crit chance and +fraction crit damage (crits deal 150% + damage)
--   dot: +fraction damage for burns          cost: fraction off placement and upgrade cost
--   farm: +fraction money-farm income        xp: +fraction unit XP from battles
--   single: only one of this unit can be placed
local Traits = {}

export type TraitDef = {
	id: string,
	name: string,
	rarity: string,
	chance: number,
	pity: number?,
	desc: string,
	fx: { [string]: any },
}

local list: { TraitDef } = {
	-- rainbow (Mythic), with pity
	{
		id = "boundless",
		name = "Boundless",
		rarity = "Mythic",
		chance = 0.1,
		pity = 1500,
		desc = "+300% damage, -5% SPA, +10% range. Only one can be placed",
		fx = { damage = 3.0, speed = 0.05, range = 0.10, single = true },
	},
	{
		id = "primeval",
		name = "Primeval",
		rarity = "Mythic",
		chance = 0.2,
		pity = 750,
		desc = "+35% damage, -15% SPA, +20% range",
		fx = { damage = 0.35, speed = 0.15, range = 0.20 },
	},
	{
		id = "forsworn",
		name = "Forsworn",
		rarity = "Mythic",
		chance = 0.3,
		pity = 500,
		desc = "+35% crit damage, +35% crit chance, +10% range",
		fx = { crit = { chance = 0.35, damage = 0.35 }, range = 0.10 },
	},
	{
		id = "wyrmblood",
		name = "Wyrmblood",
		rarity = "Mythic",
		chance = 0.5,
		pity = 300,
		desc = "+20% damage, +120% burn damage, -15% cost",
		fx = { damage = 0.20, dot = 1.2, cost = 0.15 },
	},

	-- gold (Legendary and Epic)
	{ id = "tycoon", name = "Tycoon", rarity = "Legendary", chance = 2, desc = "+25% money-farm income", fx = { farm = 0.25 } },
	{ id = "farsight", name = "Farsight", rarity = "Legendary", chance = 3, desc = "+25% range", fx = { range = 0.25 } },
	{ id = "surge", name = "Surge", rarity = "Legendary", chance = 4, desc = "-15% SPA", fx = { speed = 0.15 } },
	{ id = "accuracy2", name = "Accuracy II", rarity = "Legendary", chance = 4, desc = "+20% crit chance, +10% crit damage", fx = { crit = { chance = 0.20, damage = 0.10 } } },
	{ id = "accuracy1", name = "Accuracy I", rarity = "Epic", chance = 6, desc = "+10% crit chance, +5% crit damage", fx = { crit = { chance = 0.10, damage = 0.05 } } },
	{ id = "overdrive", name = "Overdrive", rarity = "Epic", chance = 6, desc = "+15% damage", fx = { damage = 0.15 } },

	-- blue (Rare and Common)
	{ id = "reach2", name = "Reach II", rarity = "Rare", chance = 7, desc = "+10% range", fx = { range = 0.10 } },
	{ id = "swift2", name = "Swift II", rarity = "Rare", chance = 7, desc = "-10% SPA", fx = { speed = 0.10 } },
	{ id = "power2", name = "Power II", rarity = "Rare", chance = 7, desc = "+10% damage", fx = { damage = 0.10 } },
	{ id = "wisdom", name = "Wisdom", rarity = "Rare", chance = 9, desc = "+50% unit XP", fx = { xp = 0.50 } },
	{ id = "reach1", name = "Reach I", rarity = "Common", chance = 14.63, desc = "+5% range", fx = { range = 0.05 } },
	{ id = "swift1", name = "Swift I", rarity = "Common", chance = 14.63, desc = "-5% SPA", fx = { speed = 0.05 } },
	{ id = "power1", name = "Power I", rarity = "Common", chance = 14.64, desc = "+5% damage", fx = { damage = 0.05 } },
}

Traits.List = list
Traits.ById = {} :: { [string]: TraitDef }
Traits.ByRarity = {} :: { [string]: { TraitDef } }
for _, def in list do
	Traits.ById[def.id] = def
	Traits.ByRarity[def.rarity] = Traits.ByRarity[def.rarity] or {}
	table.insert(Traits.ByRarity[def.rarity], def)
end

-- traits from before this list, as the trait each one becomes
Traits.Legacy = {
	strong1 = "power1",
	quick1 = "swift1",
	keen1 = "reach1",
	thrifty = "power1",
	strong2 = "power2",
	quick2 = "swift2",
	hawkeye = "reach2",
	prospector = "tycoon",
	strong3 = "overdrive",
	quick3 = "surge",
	eagleeye = "farsight",
	bounty = "tycoon",
	titanslayer = "accuracy2",
	frostbite = "overdrive",
	blazing = "accuracy2",
	overclock = "surge",
	superstar = "primeval",
	chainreaction = "forsworn",
	midas = "wyrmblood",
	timestop = "forsworn",
}

Traits.RollCost = 1 -- trait crystals per roll

-- rolls a trait. pity: rolls since each pity trait was last rolled (updated in place)
function Traits.roll(rng: Random, pity: { [string]: number }): TraitDef
	-- a pity trait whose counter is full comes first, the rarest one if several are
	local forced: TraitDef? = nil
	for _, def in list do
		if def.pity and (pity[def.id] or 0) + 1 >= def.pity and (not forced or def.chance < forced.chance) then
			forced = def
		end
	end
	local picked = forced
	if not picked then
		local roll = rng:NextNumber() * 100
		for _, def in list do
			roll -= def.chance
			if roll < 0 then
				picked = def
				break
			end
		end
	end
	local result = picked or list[#list]
	for _, def in list do
		if def.pity then
			pity[def.id] = if def == result then 0 else (pity[def.id] or 0) + 1
		end
	end
	return result
end

return Traits
