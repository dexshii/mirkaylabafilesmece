-- Rarity tiers shared by summonable units and traits.
local Rarities = {}

Rarities.Order = { "Common", "Rare", "Legendary", "Mythic" }

Rarities.Info = {
	Common = { rank = 1, color = Color3.fromRGB(176, 186, 196), releaseGems = 5 },
	Rare = { rank = 2, color = Color3.fromRGB(70, 150, 255), releaseGems = 15 },
	Legendary = { rank = 3, color = Color3.fromRGB(255, 190, 40), releaseGems = 60 },
	Mythic = { rank = 4, color = Color3.fromRGB(255, 70, 150), releaseGems = 250 },
}

-- percent chances, must add up to 100
Rarities.SummonRates = { Common = 60, Rare = 30, Legendary = 8.5, Mythic = 1.5 }
Rarities.TraitRates = { Common = 55, Rare = 32, Legendary = 11, Mythic = 2 }

-- summons without a Legendary-or-better / Mythic before one is guaranteed
Rarities.LegendaryPity = 50
Rarities.MythicPity = 120

function Rarities.roll(rates: { [string]: number }, rng: Random): string
	local roll = rng:NextNumber() * 100
	local acc = 0
	for i = #Rarities.Order, 1, -1 do
		local name = Rarities.Order[i]
		acc += rates[name]
		if roll < acc then
			return name
		end
	end
	return "Common"
end

return Rarities
