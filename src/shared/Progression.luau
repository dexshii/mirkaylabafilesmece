-- Per-unit progression that is kept on each owned unit:
--   level (1-50) from battle XP: +1.2% damage per level above 1
--   stat grades (C to SSS) for damage, attack speed (SPA) and range, rolled once when the unit is summoned
local Progression = {}

Progression.MaxLevel = 50

-- XP needed to go from `level` to `level + 1`
function Progression.xpToNext(level: number): number
	return 40 + level * 15
end

-- adds xp to a unit entry ({l, x}); returns how many levels it gained
function Progression.addXp(entry: { [string]: any }, xp: number): number
	local before = entry.l or 1
	entry.l = before
	entry.x = (entry.x or 0) + xp
	while entry.l < Progression.MaxLevel and entry.x >= Progression.xpToNext(entry.l) do
		entry.x -= Progression.xpToNext(entry.l)
		entry.l += 1
	end
	if entry.l >= Progression.MaxLevel then
		entry.x = 0
	end
	return entry.l - before
end

function Progression.levelDamage(level: number?): number
	return 1 + 0.012 * ((level or 1) - 1)
end

Progression.GradeOrder = { "C", "B", "A", "S", "SS", "SSS" }
-- chance weights when a unit is summoned
Progression.GradeWeights = { C = 22, B = 28, A = 24, S = 15, SS = 8, SSS = 3 }
-- multiplier on the stat (for SPA it divides the attack cooldown)
Progression.GradeMult = { C = 0.90, B = 0.95, A = 1.00, S = 1.05, SS = 1.10, SSS = 1.16 }
Progression.GradeColor = {
	C = Color3.fromRGB(170, 170, 170),
	B = Color3.fromRGB(90, 200, 90),
	A = Color3.fromRGB(80, 160, 255),
	S = Color3.fromRGB(190, 110, 255),
	SS = Color3.fromRGB(255, 120, 60),
	SSS = Color3.fromRGB(255, 210, 40),
}

function Progression.rollGrade(rng: Random): string
	local total = 0
	for _, g in Progression.GradeOrder do
		total += Progression.GradeWeights[g]
	end
	local roll = rng:NextNumber() * total
	for _, g in Progression.GradeOrder do
		roll -= Progression.GradeWeights[g]
		if roll < 0 then
			return g
		end
	end
	return "A"
end

function Progression.rollGrades(rng: Random): { d: string, s: string, r: string }
	return { d = Progression.rollGrade(rng), s = Progression.rollGrade(rng), r = Progression.rollGrade(rng) }
end

Progression.DefaultGrades = { d = "A", s = "A", r = "A" }

-- the player's own level, from battle XP; team slots 4-6 unlock at these levels
Progression.SlotUnlock = { 1, 1, 1, 5, 10, 15 }

function Progression.playerXpToNext(level: number): number
	return 150 + 50 * (level - 1)
end

function Progression.slotUnlocked(level: number?, slot: number): boolean
	return (level or 1) >= (Progression.SlotUnlock[slot] or 1)
end

return Progression
