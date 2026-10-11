-- Traits are rolled onto a unit with Trait Crystals (earned from challenges). A unit holds one trait; rolling again
-- replaces it. Effect fields (all optional):
--   damage / speed / range: +fraction (speed = attack speed, so cooldown is divided by 1 + speed)
--   cost: fraction off placement and upgrade cost        cash: +fraction cash from this unit's kills
--   bossDamage: +fraction vs bosses                      hitsAir: can target flying enemies
--   slow = {pct, dur}   burn = {dps (fraction of hit damage per second), dur}   stun = {chance, dur}
--   chain: extra enemies each attack jumps to (at 60% damage)   waveCash: cash paid at the end of each wave
local Traits = {}

export type TraitDef = {
	id: string,
	name: string,
	rarity: string,
	desc: string,
	fx: { [string]: any },
}

local list: { TraitDef } = {
	-- Common
	{ id = "strong1", name = "Strong I", rarity = "Common", desc = "+8% damage", fx = { damage = 0.08 } },
	{ id = "quick1", name = "Quick I", rarity = "Common", desc = "+8% attack speed", fx = { speed = 0.08 } },
	{ id = "keen1", name = "Keen I", rarity = "Common", desc = "+8% range", fx = { range = 0.08 } },
	{ id = "thrifty", name = "Thrifty", rarity = "Common", desc = "-10% placement and upgrade cost", fx = { cost = 0.10 } },

	-- Rare
	{ id = "strong2", name = "Strong II", rarity = "Rare", desc = "+18% damage", fx = { damage = 0.18 } },
	{ id = "quick2", name = "Quick II", rarity = "Rare", desc = "+18% attack speed", fx = { speed = 0.18 } },
	{ id = "hawkeye", name = "Hawkeye", rarity = "Rare", desc = "+20% range and can hit flying enemies", fx = { range = 0.20, hitsAir = true } },
	{ id = "prospector", name = "Prospector", rarity = "Rare", desc = "+25% cash from this unit's kills", fx = { cash = 0.25 } },

	-- Legendary
	{ id = "titanslayer", name = "Titan Slayer", rarity = "Legendary", desc = "+60% damage to bosses", fx = { bossDamage = 0.60 } },
	{ id = "frostbite", name = "Frostbite", rarity = "Legendary", desc = "Attacks slow enemies by 25% for 1.5s", fx = { slow = { pct = 0.25, dur = 1.5 } } },
	{ id = "blazing", name = "Blazing", rarity = "Legendary", desc = "Attacks burn for 3s (30% of hit damage per second)", fx = { burn = { dps = 0.30, dur = 3 } } },
	{ id = "overclock", name = "Overclock", rarity = "Legendary", desc = "+30% attack speed and +10% damage", fx = { speed = 0.30, damage = 0.10 } },

	-- Mythic
	{
		id = "superstar",
		name = "Superstar",
		rarity = "Mythic",
		desc = "+50% damage, +25% attack speed, +15% range",
		fx = { damage = 0.50, speed = 0.25, range = 0.15 },
	},
	{ id = "chainreaction", name = "Chain Reaction", rarity = "Mythic", desc = "Every attack chains to 2 more enemies", fx = { chain = 2 } },
	{ id = "midas", name = "Midas Touch", rarity = "Mythic", desc = "+100% cash from kills and +100 cash every wave", fx = { cash = 1.0, waveCash = 100 } },
	{
		id = "timestop",
		name = "Time Stop",
		rarity = "Mythic",
		desc = "+20% damage, 12% chance per hit to stun for 1.5s",
		fx = { damage = 0.20, stun = { chance = 0.12, dur = 1.5 } },
	},
}

Traits.List = list
Traits.ById = {} :: { [string]: TraitDef }
Traits.ByRarity = {} :: { [string]: { TraitDef } }
for _, def in list do
	Traits.ById[def.id] = def
	Traits.ByRarity[def.rarity] = Traits.ByRarity[def.rarity] or {}
	table.insert(Traits.ByRarity[def.rarity], def)
end

Traits.RollCost = 1 -- trait crystals per roll

return Traits
