-- One player's battle: the map, the waves, the enemies walking the path, and the units the player placed.
-- The simulation runs on the server (scaled by the 1x/2x/3x speed); the client only draws the attack effects it is
-- sent and the UI.
local RunService = game:GetService("RunService")

local Shared = game.ReplicatedStorage.Shared
local Maps = require(Shared.Maps)
local Units = require(Shared.Units)
local Enemies = require(Shared.Enemies)
local Stats = require(Shared.Stats)
local Rarities = require(Shared.Rarities)
local ModelFactory = require(Shared.ModelFactory)
local Net = require(Shared.Net)
local MapBuilder = require(script.Parent.MapBuilder)

local Battle = {}
Battle.__index = Battle

local PREP_SECONDS = 25
local BREAK_SECONDS = 6
local STATE_INTERVAL = 0.2
local CHAIN_JUMP = 14
local TARGETING = { "First", "Last", "Strongest", "Closest" }

local fxEvent: RemoteEvent
local stateEvent: RemoteEvent

function Battle.init()
	fxEvent = Net.ev("Fx")
	stateEvent = Net.ev("BattleState")
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- opts: { mapId, stage, challenge = ChallengeDef?, team = { {uid, unitId, trait} } , slot, onEnd(battle, won) }
function Battle.new(player: Player, opts: { [string]: any })
	local self = setmetatable({}, Battle)
	self.player = player
	self.mapDef = Maps.ById[opts.mapId]
	self.stage = opts.stage
	self.challenge = opts.challenge
	self.mods = opts.challenge and opts.challenge.modifiers or {}
	self.team = opts.team
	self.onEnd = opts.onEnd
	self.slot = opts.slot
	self.origin = Vector3.new(400 * opts.slot, 0, 800)

	self.arena, self.points = MapBuilder.build(self.mapDef, self.origin, opts.slot * 7919 + Maps.Index[opts.mapId])
	self.segLen = {}
	self.totalLen = 0
	for i = 1, #self.points - 1 do
		local len = (self.points[i + 1] - self.points[i]).Magnitude
		self.segLen[i] = len
		self.totalLen += len
	end

	self.enemyFolder = Instance.new("Folder")
	self.enemyFolder.Name = "Enemies"
	self.enemyFolder.Parent = self.arena
	self.towerFolder = Instance.new("Folder")
	self.towerFolder.Name = "Units"
	self.towerFolder.Parent = self.arena

	self.waves = Maps.buildWaves(self.mapDef, self.stage, self.mods)
	self.waveIndex = 0
	self.state = "prep"
	self.timer = PREP_SECONDS
	self.time = 0
	self.speed = 1
	self.cash = math.floor(Maps.StartCash * (self.mods.startCash or 1))
	self.baseHp = Maps.BaseHealth
	self.enemies = {}
	self.spawners = {}
	self.towers = {}
	self.nextId = 1
	self.stateClock = 0
	self.kills = 0

	self.conn = RunService.Heartbeat:Connect(function(dt)
		self:step(math.min(dt, 0.1) * self.speed)
		self.stateClock += dt
		if self.stateClock >= STATE_INTERVAL then
			self.stateClock = 0
			self:sendState()
		end
	end)
	self:sendState()
	return self
end

-- ============================================================ path

function Battle:posAt(dist: number): (Vector3, Vector3)
	local d = math.clamp(dist, 0, self.totalLen)
	for i = 1, #self.segLen do
		local len = self.segLen[i]
		if d <= len or i == #self.segLen then
			local a, b = self.points[i], self.points[i + 1]
			local dir = (b - a).Unit
			return a + dir * math.min(d, len), dir
		end
		d -= len
	end
	return self.points[#self.points], Vector3.new(0, 0, -1)
end

-- ============================================================ enemies

local function healthBar(model: Model, height: number, boss: boolean, name: string)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Health"
	gui.Size = boss and UDim2.fromOffset(160, 26) or UDim2.fromOffset(60, 8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height + 1, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 220
	gui.Adornee = model.PrimaryPart
	local back = Instance.new("Frame")
	back.Size = boss and UDim2.new(1, 0, 0, 10) or UDim2.fromScale(1, 1)
	back.Position = boss and UDim2.new(0, 0, 1, -10) or UDim2.new()
	back.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = boss and Color3.fromRGB(200, 60, 255) or Color3.fromRGB(80, 220, 80)
	fill.BorderSizePixel = 0
	fill.Parent = back
	if boss then
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0, 16)
		label.BackgroundTransparency = 1
		label.Text = name
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Parent = gui
	end
	gui.Parent = model
	return fill
end

function Battle:spawnEnemy(enemyId: string, hpMult: number, bossMult: number, dist: number)
	local def = Enemies.ById[enemyId]
	local scale = def.scale or 1
	local mult = def.boss and bossMult or hpMult
	local hp = def.hp * mult * (self.mods.enemyHp or 1)
	local model = ModelFactory.build(enemyId, scale)
	local fill = healthBar(model, 4.5 * scale, def.boss == true, def.name)
	local pos, dir = self:posAt(dist)
	model:PivotTo(CFrame.lookAt(pos, pos + dir))
	model.Parent = self.enemyFolder
	local enemy = {
		id = self.nextId,
		def = def,
		hp = hp,
		maxHp = hp,
		dist = dist,
		pos = pos,
		model = model,
		root = model.PrimaryPart,
		fill = fill,
		lastFrac = 1,
		flying = def.kind == "flying",
		alive = true,
		slowPct = 0,
		slowUntil = 0,
		stunUntil = 0,
		burnDps = 0,
		burnUntil = 0,
		burnSource = nil,
		immuneUntil = 0,
		dashUntil = 0,
		abilityTimer = def.ability and def.ability.every or 0,
		phase = math.random() * 6,
		-- tougher enemies on later maps and waves pay more, so the economy keeps up
		cashMult = math.sqrt(mult),
	}
	self.nextId += 1
	table.insert(self.enemies, enemy)
	return enemy
end

function Battle:removeEnemy(enemy)
	enemy.alive = false
	if enemy.model then
		enemy.model:Destroy()
		enemy.model = nil
	end
end

function Battle:kill(enemy, tower)
	if not enemy.alive then
		return
	end
	self.kills += 1
	local mult = (self.mods.killCash or 1) * (tower and tower.stats.cashMult or 1)
	self.cash += math.floor(enemy.def.cash * enemy.cashMult * mult + 0.5)
	if enemy.def.splitInto then
		local wave = self.waves[math.max(self.waveIndex, 1)]
		for i = 1, 2 do
			local child = self:spawnEnemy(enemy.def.splitInto, wave.hpMult, wave.bossMult, math.max(0, enemy.dist - i * 2))
			child.pos = enemy.pos
		end
	end
	self:fx({ style = "pop", to = enemy.pos + Vector3.new(0, enemy.flying and Enemies.FlyHeight or 2, 0), color = Color3.fromRGB(255, 220, 80), boss = enemy.def.boss })
	self:removeEnemy(enemy)
end

function Battle:damage(enemy, amount: number, tower, applyEffects: boolean)
	if not enemy.alive then
		return
	end
	if self.time < enemy.immuneUntil then
		return
	end
	local s = tower and tower.stats
	local d = amount
	if s then
		if enemy.flying then
			d *= s.airMult
		end
		if enemy.def.boss then
			d *= s.bossMult
		end
	end
	d *= 1 - (enemy.def.armor or 0)
	enemy.hp -= d

	if applyEffects and s then
		if s.slow then
			local pct = enemy.def.boss and s.slow.pct * 0.5 or s.slow.pct
			if pct >= enemy.slowPct or self.time >= enemy.slowUntil then
				enemy.slowPct = pct
			end
			enemy.slowUntil = math.max(enemy.slowUntil, self.time + s.slow.dur)
		end
		if s.burn then
			enemy.burnDps = math.max(self.time < enemy.burnUntil and enemy.burnDps or 0, amount * s.burn.dps)
			enemy.burnUntil = self.time + s.burn.dur
			enemy.burnSource = tower
		end
		if s.stun and not enemy.def.boss and math.random() < s.stun.chance then
			enemy.stunUntil = math.max(enemy.stunUntil, self.time + s.stun.dur)
		end
	end

	if enemy.hp <= 0 then
		self:kill(enemy, tower)
	end
end

function Battle:useAbility(enemy)
	local ab = enemy.def.ability
	local at = enemy.pos + Vector3.new(0, 2, 0)
	if ab.type == "summon" or ab.type == "monarch" then
		local wave = self.waves[math.max(self.waveIndex, 1)]
		for i = 1, ab.count do
			self:spawnEnemy(ab.enemy, wave.hpMult, wave.bossMult, math.max(0, enemy.dist - 2 - i * 2))
		end
		self:fx({ style = "summon", to = at, color = Color3.fromRGB(170, 80, 255), radius = 8 })
	end
	if ab.type == "stun" or ab.type == "monarch" then
		for _, tower in self.towers do
			if flatDist(tower.pos, enemy.pos) <= ab.radius then
				tower.stunUntil = math.max(tower.stunUntil, self.time + ab.dur)
			end
		end
		self:fx({ style = "shock", to = at, color = Color3.fromRGB(140, 220, 255), radius = ab.radius })
	end
	if ab.type == "dash" then
		enemy.dashUntil = self.time + ab.dur
		self:fx({ style = "summon", to = at, color = Color3.fromRGB(255, 200, 80), radius = 6 })
	end
	if ab.type == "shield" then
		enemy.immuneUntil = self.time + ab.dur
		enemy.hp = math.min(enemy.maxHp, enemy.hp + enemy.maxHp * ab.heal)
		self:fx({ style = "shield", to = at, color = Color3.fromRGB(255, 120, 30), radius = 7 * (enemy.def.scale or 1) / 2, dur = ab.dur / self.speed })
	end
end

function Battle:moveEnemies(dt: number)
	local parts, cframes = {}, {}
	local speedMod = self.mods.enemySpeed or 1
	for _, e in self.enemies do
		if not e.alive then
			continue
		end
		if e.def.ability then
			e.abilityTimer -= dt
			if e.abilityTimer <= 0 then
				e.abilityTimer = e.def.ability.every
				self:useAbility(e)
			end
		end
		if self.time < e.burnUntil then
			self:damage(e, e.burnDps * dt, e.burnSource, false)
			if not e.alive then
				continue
			end
		end
		local speed = e.def.speed * speedMod
		if self.time < e.slowUntil then
			speed *= 1 - e.slowPct
		end
		if self.time < e.dashUntil then
			speed *= e.def.ability.mult
		end
		if self.time < e.stunUntil then
			speed = 0
		end
		e.dist += speed * dt
		if e.dist >= self.totalLen then
			self.baseHp -= e.def.leak
			self:fx({ style = "leak", to = self.points[#self.points] + Vector3.new(0, 4, 0), color = Color3.fromRGB(255, 60, 60) })
			self:removeEnemy(e)
			continue
		end
		local pos, dir = self:posAt(e.dist)
		e.pos = pos
		local bob = math.abs(math.sin(self.time * 8 + e.phase)) * 0.4
		local height = e.flying and (Enemies.FlyHeight + math.sin(self.time * 2 + e.phase)) or bob
		local cf = CFrame.lookAt(pos, pos + dir) + Vector3.new(0, height, 0)
		table.insert(parts, e.root)
		table.insert(cframes, cf)

		local frac = math.clamp(e.hp / e.maxHp, 0, 1)
		if math.abs(frac - e.lastFrac) > 0.01 then
			e.lastFrac = frac
			e.fill.Size = UDim2.fromScale(frac, 1)
		end
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- drop removed enemies
	local alive = {}
	for _, e in self.enemies do
		if e.alive then
			table.insert(alive, e)
		end
	end
	self.enemies = alive

	if self.baseHp <= 0 then
		self.baseHp = 0
		self:finish(false)
	end
end

-- ============================================================ towers

function Battle:canHit(tower, enemy): boolean
	if enemy.flying then
		return tower.stats.hitsAir
	end
	return tower.stats.hitsGround
end

function Battle:pickTarget(tower)
	local best, bestScore = nil, -math.huge
	local range = tower.stats.range
	for _, e in self.enemies do
		if e.alive and self:canHit(tower, e) then
			local d = flatDist(tower.pos, e.pos)
			if d <= range then
				local score
				if tower.targeting == "Last" then
					score = -e.dist
				elseif tower.targeting == "Strongest" then
					score = e.hp
				elseif tower.targeting == "Closest" then
					score = -d
				else
					score = e.dist
				end
				if score > bestScore then
					best, bestScore = e, score
				end
			end
		end
	end
	return best
end

local function aimPoint(enemy): Vector3
	local h = enemy.flying and Enemies.FlyHeight + 1 or 2 * (enemy.def.scale or 1)
	return enemy.pos + Vector3.new(0, h, 0)
end

function Battle:chainFrom(tower, first, count: number, damage: number, falloff: number, hit: { [any]: boolean }, points: { Vector3 })
	local current = first
	local dmg = damage
	for _ = 1, count do
		local nextE, nextD = nil, CHAIN_JUMP
		for _, e in self.enemies do
			if e.alive and not hit[e] and self:canHit(tower, e) then
				local d = flatDist(current.pos, e.pos)
				if d <= nextD then
					nextE, nextD = e, d
				end
			end
		end
		if not nextE then
			break
		end
		dmg *= falloff
		hit[nextE] = true
		table.insert(points, aimPoint(nextE))
		self:damage(nextE, dmg, tower, true)
		current = nextE
	end
end

function Battle:attack(tower, target)
	local s = tower.stats
	local def = tower.def
	local kind = def.attack.kind
	local top = tower.pos + Vector3.new(0, def.height * 0.7, 0)
	local targetPoint = aimPoint(target)
	local hit = {}
	local chainPoints = { targetPoint }
	local radius

	-- turn to face the target
	tower.model:PivotTo(CFrame.lookAt(tower.pos, Vector3.new(target.pos.X, tower.pos.Y, target.pos.Z)))

	if kind == "single" then
		hit[target] = true
		self:damage(target, s.damage, tower, true)
	elseif kind == "splash" then
		radius = def.attack.radius
		local center = target.pos
		for _, e in self.enemies do
			if e.alive and self:canHit(tower, e) and flatDist(e.pos, center) <= radius then
				hit[e] = true
				self:damage(e, s.damage, tower, true)
			end
		end
	elseif kind == "slam" then
		radius = s.range
		for _, e in self.enemies do
			if e.alive and self:canHit(tower, e) and flatDist(e.pos, tower.pos) <= s.range then
				hit[e] = true
				self:damage(e, s.damage, tower, true)
			end
		end
	elseif kind == "cone" then
		radius = s.range
		local aim = Vector3.new(target.pos.X - tower.pos.X, 0, target.pos.Z - tower.pos.Z).Unit
		local cosLimit = math.cos(math.rad(def.attack.angle))
		for _, e in self.enemies do
			if e.alive and self:canHit(tower, e) then
				local off = Vector3.new(e.pos.X - tower.pos.X, 0, e.pos.Z - tower.pos.Z)
				local d = off.Magnitude
				if d <= s.range and (d < 1 or off.Unit:Dot(aim) >= cosLimit) then
					hit[e] = true
					self:damage(e, s.damage, tower, true)
				end
			end
		end
	elseif kind == "chain" then
		hit[target] = true
		self:damage(target, s.damage, tower, true)
		self:chainFrom(tower, target, s.chain, s.damage, def.attack.falloff or 0.75, hit, chainPoints)
	end

	-- the Chain Reaction trait on units that do not already chain
	if kind ~= "chain" and s.chain > 0 then
		self:chainFrom(tower, target, s.chain, s.damage, 0.6, hit, chainPoints)
	end

	self:fx({
		style = def.fx.style,
		color = def.fx.color,
		from = top,
		to = targetPoint,
		radius = radius,
		ground = tower.pos,
		chain = #chainPoints > 1 and chainPoints or nil,
		tower = tower.id,
	})
end

function Battle:updateTowers(dt: number)
	for _, tower in self.towers do
		if self.time < tower.stunUntil then
			continue
		end
		if tower.def.attack.kind == "none" then
			continue
		end
		tower.cooldownLeft -= dt
		if tower.cooldownLeft <= 0 then
			local target = self:pickTarget(tower)
			if target then
				self:attack(tower, target)
				tower.cooldownLeft += tower.stats.cooldown
				if tower.cooldownLeft < 0 then
					tower.cooldownLeft = 0
				end
			else
				tower.cooldownLeft = 0
			end
		end
	end
end

-- auras: Star Sage (+damage, sees flyers) and Starlight Princess (+damage to every unit)
function Battle:recalcTowers()
	for _, tower in self.towers do
		local buffs = { damage = 0, hitsAir = false }
		for _, other in self.towers do
			local aura = other.def.aura
			if other ~= tower and aura and flatDist(other.pos, tower.pos) <= aura.range then
				buffs.damage += aura.damage
				if aura.grantsAir then
					buffs.hitsAir = true
				end
			end
		end
		tower.stats = Stats.compute(tower.unitId, tower.level, tower.trait, buffs)
		tower.model:SetAttribute("Level", tower.level)
		tower.model:SetAttribute("Targeting", tower.targeting)
		tower.model:SetAttribute("Spent", tower.spent)
		tower.model:SetAttribute("DamageBuff", buffs.damage)
		tower.model:SetAttribute("AirBuff", buffs.hitsAir)
		if tower.badge then
			tower.badge.Text = string.rep("★", tower.level)
		end
	end
end

-- ============================================================ player actions

local function rarityOk(self, unitId: string): boolean
	local only = self.mods.onlyRarity
	return not only or Units.ById[unitId].rarity == only
end

function Battle:towerCount(unitId: string?): number
	local n = 0
	for _, t in self.towers do
		if not unitId or t.unitId == unitId then
			n += 1
		end
	end
	return n
end

function Battle:place(slot: number, position: Vector3): (boolean, string?)
	if self.state == "won" or self.state == "lost" then
		return false, "The battle is over"
	end
	local member = self.team[slot]
	if not member then
		return false, "No unit in that slot"
	end
	local def = Units.ById[member.unitId]
	if not rarityOk(self, member.unitId) then
		return false, "Only " .. self.mods.onlyRarity .. " units are allowed in this challenge"
	end
	if def.limit and self:towerCount(member.unitId) >= def.limit then
		return false, def.name .. " limit reached (" .. def.limit .. ")"
	end
	if self.mods.maxUnits and self:towerCount() >= self.mods.maxUnits then
		return false, "Unit limit reached (" .. self.mods.maxUnits .. ")"
	end
	local cost = Stats.placeCost(member.unitId, member.trait)
	if self.cash < cost then
		return false, "Not enough cash"
	end
	local x, z = position.X - self.origin.X, position.Z - self.origin.Z
	local others = {}
	for _, t in self.towers do
		table.insert(others, t.pos - self.origin)
	end
	local problem = Stats.placementProblem(self.mapDef.waypoints, Maps.FieldHalf, Maps.PathWidth, x, z, others)
	if problem then
		return false, problem
	end

	self.cash -= cost
	local pos = self.origin + Vector3.new(x, 0, z)
	local model = ModelFactory.build(member.unitId)
	-- face the nearest point of the path
	local closest, closestD = pos + Vector3.new(0, 0, -1), math.huge
	for _, p in self.points do
		local d = flatDist(p, pos)
		if d < closestD then
			closest, closestD = p, d
		end
	end
	model:PivotTo(CFrame.lookAt(pos, Vector3.new(closest.X, pos.Y, closest.Z)))
	local id = self.nextId
	self.nextId += 1
	model.Name = "Unit_" .. id
	model:SetAttribute("TowerId", id)
	model:SetAttribute("UnitId", member.unitId)
	model:SetAttribute("Trait", member.trait or "")
	model:SetAttribute("Owner", self.player.UserId)

	local gui = Instance.new("BillboardGui")
	gui.Name = "Badge"
	gui.Size = UDim2.fromOffset(80, 22)
	gui.StudsOffsetWorldSpace = Vector3.new(0, def.height + 1.2, 0)
	gui.MaxDistance = 120
	gui.Adornee = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Rarities.Info[def.rarity].color
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = gui
	gui.Parent = model

	-- a rarity-coloured ring under the unit
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 4.5, 4.5)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = Rarities.Info[def.rarity].color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Parent = model

	model.Parent = self.towerFolder

	local tower = {
		id = id,
		uid = member.uid,
		unitId = member.unitId,
		def = def,
		trait = member.trait,
		level = 0,
		pos = pos,
		model = model,
		badge = label,
		cooldownLeft = 0,
		targeting = "First",
		spent = cost,
		stunUntil = 0,
		stats = nil,
	}
	self.towers[id] = tower
	self:recalcTowers()
	self:fx({ style = "placed", to = pos + Vector3.new(0, 1, 0), color = Rarities.Info[def.rarity].color, radius = 3 })
	self:sendState()
	return true, nil
end

function Battle:upgrade(id: number): (boolean, string?)
	local tower = self.towers[id]
	if not tower then
		return false, "Unit not found"
	end
	if tower.level >= Units.MaxLevel then
		return false, "Already max level"
	end
	local cost = Stats.upgradeCost(tower.unitId, tower.level, tower.trait)
	if self.cash < cost then
		return false, "Not enough cash"
	end
	self.cash -= cost
	tower.level += 1
	tower.spent += cost
	self:recalcTowers()
	self:fx({ style = "placed", to = tower.pos + Vector3.new(0, 1, 0), color = Color3.fromRGB(255, 230, 80), radius = 4 })
	self:sendState()
	return true, nil
end

function Battle:sell(id: number): (boolean, string?)
	local tower = self.towers[id]
	if not tower then
		return false, "Unit not found"
	end
	self.cash += math.floor(tower.spent * 0.6)
	tower.model:Destroy()
	self.towers[id] = nil
	for _, e in self.enemies do
		if e.burnSource == tower then
			e.burnSource = nil
		end
	end
	self:recalcTowers()
	self:sendState()
	return true, nil
end

function Battle:setTargeting(id: number, mode: string): (boolean, string?)
	local tower = self.towers[id]
	if not tower or not table.find(TARGETING, mode) then
		return false, "Invalid"
	end
	tower.targeting = mode
	tower.model:SetAttribute("Targeting", mode)
	return true, nil
end

function Battle:setSpeed(speed: number)
	if speed == 1 or speed == 2 or speed == 3 then
		self.speed = speed
		self:sendState()
	end
end

-- ============================================================ waves

function Battle:startNextWave(): boolean
	if self.state ~= "prep" and self.state ~= "break" then
		return false
	end
	self.waveIndex += 1
	local wave = self.waves[self.waveIndex]
	for _, g in wave.groups do
		table.insert(self.spawners, { group = g, left = g.count, timer = g.delay, hpMult = wave.hpMult, bossMult = wave.bossMult })
	end
	self.state = "wave"
	self:sendState()
	return true
end

function Battle:runSpawners(dt: number)
	local active = {}
	for _, sp in self.spawners do
		sp.timer -= dt
		while sp.left > 0 and sp.timer <= 0 do
			self:spawnEnemy(sp.group.enemy, sp.hpMult, sp.bossMult, 0)
			sp.left -= 1
			sp.timer += sp.group.interval
		end
		if sp.left > 0 then
			table.insert(active, sp)
		end
	end
	self.spawners = active
end

function Battle:waveCleared()
	local bonus = 100 + 20 * self.waveIndex
	for _, tower in self.towers do
		if tower.stats.farm > 0 then
			bonus += math.floor(tower.stats.farm)
			self:fx({ style = "cash", to = tower.pos + Vector3.new(0, tower.def.height + 1, 0), color = Color3.fromRGB(255, 215, 0), amount = math.floor(tower.stats.farm) })
		end
	end
	self.cash += bonus
	if self.waveIndex >= #self.waves then
		self:finish(true)
	else
		self.state = "break"
		self.timer = BREAK_SECONDS
	end
	self:sendState()
end

function Battle:step(dt: number)
	if self.state == "won" or self.state == "lost" then
		return
	end
	self.time += dt
	if self.state == "prep" or self.state == "break" then
		self.timer -= dt
		if self.timer <= 0 then
			self:startNextWave()
		end
	end
	self:runSpawners(dt)
	self:moveEnemies(dt)
	if self.state == "won" or self.state == "lost" then
		return
	end
	self:updateTowers(dt)
	if self.state == "wave" and #self.spawners == 0 and #self.enemies == 0 then
		self:waveCleared()
	end
end

function Battle:finish(won: boolean)
	if self.state == "won" or self.state == "lost" then
		return
	end
	self.state = won and "won" or "lost"
	for _, e in self.enemies do
		if e.model then
			e.model:Destroy()
		end
	end
	self.enemies = {}
	self.spawners = {}
	self:sendState()
	if self.onEnd then
		task.spawn(self.onEnd, self, won)
	end
end

-- ============================================================ client sync

function Battle:fx(payload: { [string]: any })
	if self.player.Parent then
		fxEvent:FireClient(self.player, payload)
	end
end

function Battle:snapshot()
	local team = {}
	for i = 1, Units.TeamSize do
		local m = self.team[i]
		if m then
			team[i] = {
				uid = m.uid,
				unitId = m.unitId,
				trait = m.trait,
				placed = self:towerCount(m.unitId),
				cost = Stats.placeCost(m.unitId, m.trait),
				allowed = rarityOk(self, m.unitId),
			}
		else
			team[i] = false
		end
	end
	return {
		active = true,
		mapId = self.mapDef.id,
		stage = self.stage,
		challenge = self.challenge and self.challenge.id or nil,
		origin = self.origin,
		wave = self.waveIndex,
		waves = #self.waves,
		state = self.state,
		timer = math.max(0, math.ceil(self.timer)),
		cash = self.cash,
		baseHp = self.baseHp,
		maxBaseHp = Maps.BaseHealth,
		speed = self.speed,
		enemies = #self.enemies,
		units = self:towerCount(),
		maxUnits = self.mods.maxUnits,
		team = team,
	}
end

function Battle:sendState()
	if self.player.Parent then
		stateEvent:FireClient(self.player, self:snapshot())
	end
end

function Battle:destroy()
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if self.arena then
		self.arena:Destroy()
		self.arena = nil
	end
	if self.player.Parent then
		stateEvent:FireClient(self.player, { active = false })
	end
end

function Battle:spawnPoint(): CFrame
	return CFrame.new(self.origin + Vector3.new(0, 4, 0))
end

Battle.Targeting = TARGETING
return Battle
