-- Rarity tiers shared by summonable units and traits.
local Rarities = {}

Rarities.Order = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

Rarities.Info = {
	Common = { rank = 1, color = Color3.fromRGB(176, 186, 196), releaseGems = 5 },
	Rare = { rank = 2, color = Color3.fromRGB(70, 150, 255), releaseGems = 15 },
	Epic = { rank = 3, color = Color3.fromRGB(170, 90, 255), releaseGems = 30 },
	Legendary = { rank = 4, color = Color3.fromRGB(255, 190, 40), releaseGems = 60 },
	Mythic = { rank = 5, color = Color3.fromRGB(255, 70, 150), releaseGems = 250 },
}

-- percent chances, must add up to 100
Rarities.SummonRates = { Common = 52, Rare = 28, Epic = 13, Legendary = 5.5, Mythic = 1.5 }

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
