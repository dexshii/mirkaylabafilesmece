-- A placed unit's effective stats: its definition, upgrade level, trait and the auras around it.
local Units = require(script.Parent.Units)
local Traits = require(script.Parent.Traits)
local Progression = require(script.Parent.Progression)

local Stats = {}

export type Computed = {
	damage: number,
	range: number,
	cooldown: number,
	hitsGround: boolean,
	hitsAir: boolean,
	airMult: number,
	bossMult: number,
	cashMult: number,
	costMult: number,
	farm: number,
	slow: { pct: number, dur: number }?,
	burn: { dps: number, dur: number }?,
	stun: { chance: number, dur: number }?,
	execute: number,
	critChance: number,
	critDamage: number,
	dotMult: number,
	chain: number,
}

-- level: the in-battle upgrade level (0-4)
-- buffs: { damage = fraction from auras, hitsAir = true when an aura grants it }
-- unit: the owned unit's progression { l = unit level, g = { d, s, r } stat grades }
function Stats.compute(unitId: string, level: number, traitId: string?, buffs: { [string]: any }?, unit: { [string]: any }?): Computed
	local def = Units.ById[unitId]
	local trait = traitId and Traits.ById[traitId]
	local t = trait and trait.fx or {}
	local b = buffs or {}
	local u = unit or {}
	local g = u.g or Progression.DefaultGrades
	local gm = Progression.GradeMult

	local damage = def.damage * (1 + 0.30 * level) * (1 + (t.damage or 0) + (b.damage or 0)) * Progression.levelDamage(u.l) * (gm[g.d] or 1)
	local range = def.range * (1 + 0.06 * level) * (1 + (t.range or 0)) * (gm[g.r] or 1)
	local cooldown = def.cooldown * (1 - 0.05 * level) * (1 - math.min(t.speed or 0, 0.8)) / (gm[g.s] or 1)

	local slow = def.attack.slow
	if t.slow and (not slow or t.slow.pct > slow.pct) then
		slow = t.slow
	end
	local burn = def.attack.burn
	if t.burn and (not burn or t.burn.dps > burn.dps) then
		burn = t.burn
	end
	local stun = def.attack.stun
	if t.stun and not stun then
		stun = t.stun
	end

	local attacks = def.attack.kind ~= "none"
	return {
		damage = damage,
		range = range,
		cooldown = cooldown,
		hitsGround = def.hitsGround,
		hitsAir = attacks and (def.hitsAir or t.hitsAir == true or b.hitsAir == true),
		airMult = def.attack.airMult or 1,
		bossMult = (def.attack.bossMult or 1) * (1 + (t.bossDamage or 0)),
		cashMult = 1 + (t.cash or 0),
		costMult = 1 - (t.cost or 0),
		farm = (def.farm or 0) * (1 + 0.5 * level) * (1 + (t.farm or 0)) + (t.waveCash or 0),
		slow = slow,
		burn = burn,
		stun = stun,
		-- chance per hit to defeat a non-boss enemy outright
		execute = def.attack.execute or 0,
		critChance = t.crit and t.crit.chance or 0,
		critDamage = 1.5 + (t.crit and t.crit.damage or 0),
		dotMult = 1 + (t.dot or 0),
		chain = (def.attack.chain or 0) + (t.chain or 0),
	}
end

-- how many of a unit may be placed (traits like Boundless allow only one)
function Stats.limit(unitId: string, traitId: string?): number
	local trait = traitId and Traits.ById[traitId]
	if trait and trait.fx.single then
		return 1
	end
	return Units.ById[unitId].limit
end

function Stats.placeCost(unitId: string, traitId: string?): number
	local def = Units.ById[unitId]
	local trait = traitId and Traits.ById[traitId]
	local mult = 1 - (trait and trait.fx.cost or 0)
	return math.floor(def.cost * mult + 0.5)
end

function Stats.upgradeCost(unitId: string, level: number, traitId: string?): number
	local def = Units.ById[unitId]
	local trait = traitId and Traits.ById[traitId]
	local mult = 1 - (trait and trait.fx.cost or 0)
	return math.floor(Units.upgradeCost(def, level) * mult + 0.5)
end

-- distance from point (x, z) to the polyline of waypoints {{x, z}, ...}
function Stats.distanceToPath(waypoints: { { number } }, x: number, z: number): number
	local best = math.huge
	for i = 1, #waypoints - 1 do
		local ax, az = waypoints[i][1], waypoints[i][2]
		local bx, bz = waypoints[i + 1][1], waypoints[i + 1][2]
		local dx, dz = bx - ax, bz - az
		local len2 = dx * dx + dz * dz
		local t = 0
		if len2 > 0 then
			t = math.clamp(((x - ax) * dx + (z - az) * dz) / len2, 0, 1)
		end
		local px, pz = ax + dx * t - x, az + dz * t - z
		best = math.min(best, math.sqrt(px * px + pz * pz))
	end
	return best
end

-- the same placement rules the server enforces (positions local to the arena origin)
function Stats.placementProblem(
	waypoints: { { number } },
	half: number,
	pathWidth: number,
	x: number,
	z: number,
	others: { Vector3 }
): string?
	if math.abs(x) > half - 3 or math.abs(z) > half - 3 then
		return "Outside the map"
	end
	if Stats.distanceToPath(waypoints, x, z) < pathWidth / 2 + 2.5 then
		return "Too close to the path"
	end
	for _, p in others do
		local dx, dz = p.X - x, p.Z - z
		if dx * dx + dz * dz < 4.5 * 4.5 then
			return "Too close to another unit"
		end
	end
	return nil
end

return Stats
