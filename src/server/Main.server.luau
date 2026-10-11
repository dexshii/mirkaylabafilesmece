-- Server entry point: remotes, summons, traits, team, starting and ending battles.
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Units = require(Shared.Units)
local Traits = require(Shared.Traits)
local Rarities = require(Shared.Rarities)
local Maps = require(Shared.Maps)
local Challenges = require(Shared.Challenges)
local Progression = require(Shared.Progression)

local DataService = require(script.Parent.DataService)
local Battle = require(script.Parent.Battle)
local Lobby = require(script.Parent.Lobby)
local MapBuilder = require(script.Parent.MapBuilder)

Net.setup()
Battle.init()
Lobby.build()

local SUMMON_COST = { [1] = 50, [10] = 450 }

local rng = Random.new()
local battles: { [Player]: any } = {}
local slotsInUse: { [number]: boolean } = {}

local dataChanged = Net.ev("DataChanged")
local battleEnded = Net.ev("BattleEnded")

DataService.onChanged(function(player, data)
	dataChanged:FireClient(player, data)
end)
DataService.start()

local function handle(name: string, fn: (Player, ...any) -> ...any)
	Net.fn(name).OnServerInvoke = function(player, ...)
		local ok, a, b, c = pcall(fn, player, ...)
		if not ok then
			warn("[StarKingdomDefense] " .. name .. " failed: " .. tostring(a))
			return false, "Something went wrong"
		end
		return a, b, c
	end
end

local function mapUnlocked(data, mapId: string): boolean
	local index = Maps.Index[mapId]
	if not index then
		return false
	end
	if index == 1 then
		return true
	end
	return (data.progress[Maps.List[index - 1].id] or 0) >= Maps.Stages
end

local function teleport(player: Player, cf: CFrame)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		character:PivotTo(cf)
	end
end

-- ============================================================ lobby actions

handle("GetData", function(player)
	return DataService.waitFor(player, 15)
end)

handle("Summon", function(player, count)
	local data = DataService.get(player)
	local cost = SUMMON_COST[count]
	if not data or not cost then
		return false, "Invalid summon"
	end
	if data.gems < cost then
		return false, "Not enough gems"
	end
	if DataService.unitCount(data) + count > Units.InventoryLimit then
		return false, "Your unit inventory is full (" .. Units.InventoryLimit .. "). Release some units first."
	end
	data.gems -= cost
	local results = {}
	for _ = 1, count do
		data.pity.legendary += 1
		data.pity.mythic += 1
		local rarity = Rarities.roll(Rarities.SummonRates, rng)
		if data.pity.mythic >= Rarities.MythicPity then
			rarity = "Mythic"
		elseif data.pity.legendary >= Rarities.LegendaryPity and Rarities.Info[rarity].rank < Rarities.Info.Legendary.rank then
			rarity = "Legendary"
		end
		if rarity == "Mythic" then
			data.pity.mythic = 0
			data.pity.legendary = 0
		elseif rarity == "Legendary" then
			data.pity.legendary = 0
		end
		local pool = Units.ByRarity[rarity]
		local def = pool[rng:NextInteger(1, #pool)]
		local uid = DataService.addUnit(data, def.id)
		data.units[uid].g = Progression.rollGrades(rng)
		-- fill an empty team slot with new units so a new player can play right away
		local empty = nil
		for i, other in data.team do
			if other == "" and Progression.slotUnlocked(data.level, i) then
				empty = i
				break
			end
		end
		local alreadyOnTeam = false
		for _, other in data.team do
			if other ~= "" and data.units[other] and data.units[other].u == def.id then
				alreadyOnTeam = true
			end
		end
		if empty and not alreadyOnTeam then
			data.team[empty] = uid
		end
		table.insert(results, { uid = uid, unitId = def.id, rarity = rarity, grades = data.units[uid].g })
	end
	data.stats.summons = (data.stats.summons or 0) + count
	DataService.changed(player)
	return true, results
end)

handle("EquipUnit", function(player, slot, uid)
	local data = DataService.get(player)
	if not data or type(slot) ~= "number" or slot < 1 or slot > Units.TeamSize or slot % 1 ~= 0 then
		return false, "Invalid slot"
	end
	if type(uid) ~= "string" or (uid ~= "" and not data.units[uid]) then
		return false, "Invalid unit"
	end
	if uid ~= "" and not Progression.slotUnlocked(data.level, slot) then
		return false, "Team slot " .. slot .. " unlocks at player level " .. Progression.SlotUnlock[slot]
	end
	if uid ~= "" then
		local unitId = data.units[uid].u
		for i, other in data.team do
			if i ~= slot and other ~= "" then
				if other == uid then
					data.team[i] = ""
				elseif data.units[other] and data.units[other].u == unitId then
					return false, "That unit is already on your team (one copy per unit type)"
				end
			end
		end
	end
	data.team[slot] = uid
	DataService.changed(player)
	return true
end)

handle("RollTrait", function(player, uid)
	local data = DataService.get(player)
	if not data or type(uid) ~= "string" or not data.units[uid] then
		return false, "Invalid unit"
	end
	if data.crystals < Traits.RollCost then
		return false, "Not enough Trait Crystals. Clear challenges to earn more!"
	end
	data.crystals -= Traits.RollCost
	local rarity = Rarities.roll(Rarities.TraitRates, rng)
	local pool = Traits.ByRarity[rarity]
	local trait = pool[rng:NextInteger(1, #pool)]
	data.units[uid].t = trait.id
	data.stats.rolls = (data.stats.rolls or 0) + 1
	DataService.changed(player)
	return true, trait.id
end)

handle("LockUnit", function(player, uid)
	local data = DataService.get(player)
	if not data or type(uid) ~= "string" or not data.units[uid] then
		return false, "Invalid unit"
	end
	data.units[uid].k = not data.units[uid].k or nil
	DataService.changed(player)
	return true, data.units[uid].k == true
end)

handle("ReleaseUnit", function(player, uid)
	local data = DataService.get(player)
	if not data or type(uid) ~= "string" or not data.units[uid] then
		return false, "Invalid unit"
	end
	if DataService.unitCount(data) <= 1 then
		return false, "You can't release your last unit"
	end
	if data.units[uid].k then
		return false, "That unit is locked. Unlock it first"
	end
	local def = Units.ById[data.units[uid].u]
	local gems = Rarities.Info[def.rarity].releaseGems
	data.units[uid] = nil
	for i, other in data.team do
		if other == uid then
			data.team[i] = ""
		end
	end
	data.gems += gems
	DataService.changed(player)
	return true, gems
end)

-- ============================================================ battles

local function rewardsFor(data, battle, won: boolean)
	local result = { won = won, gems = 0, crystals = 0, wave = battle.waveIndex, waves = #battle.waves, firstClear = false }
	if battle.challenge then
		local ch = battle.challenge
		result.challenge = ch.name
		if won then
			if data.challenges[ch.id] ~= Challenges.today() then
				data.challenges[ch.id] = Challenges.today()
				result.gems = ch.gems
				result.crystals = ch.crystals
				result.firstClear = true
			else
				result.gems = ch.repeatGems
			end
		else
			result.gems = 2 * math.max(0, battle.waveIndex - 1)
		end
	else
		local mapIndex = Maps.Index[battle.mapDef.id]
		local factor = 1 + 0.25 * (mapIndex - 1)
		if won then
			local prev = data.progress[battle.mapDef.id] or 0
			if battle.stage > prev then
				result.firstClear = true
				data.progress[battle.mapDef.id] = battle.stage
				result.gems = math.floor((60 + 30 * battle.stage + (battle.stage == Maps.Stages and 150 or 0)) * factor)
				result.crystals = battle.stage == Maps.Stages and 3 or 1
				if battle.stage == Maps.Stages and Maps.List[mapIndex + 1] then
					result.unlocked = Maps.List[mapIndex + 1].name
				end
			else
				result.gems = math.floor((15 + 5 * battle.stage) * factor)
			end
		else
			result.gems = 2 * math.max(0, battle.waveIndex - 1)
		end
	end
	if won then
		data.stats.wins = (data.stats.wins or 0) + 1
	end
	data.gems += result.gems
	data.crystals += result.crystals

	-- every unit that went into battle earns XP: per wave survived, doubled on a win
	local xp = math.max(0, battle.waveIndex - (won and 0 or 1)) * 12 * (won and 2 or 1)
	result.xp = xp
	result.levelUps = {}
	-- the player's own XP
	local playerXp = math.max(0, battle.waveIndex - (won and 0 or 1)) * 8 + (won and 40 or 0)
	result.playerXp = playerXp
	data.level = data.level or 1
	data.xp = (data.xp or 0) + playerXp
	while data.xp >= Progression.playerXpToNext(data.level) do
		data.xp -= Progression.playerXpToNext(data.level)
		data.level += 1
		result.playerLevel = data.level
	end
	for _, member in battle.team do
		local entry = data.units[member.uid]
		if entry and xp > 0 then
			local gained = Progression.addXp(entry, xp)
			if gained > 0 then
				table.insert(result.levelUps, { unitId = entry.u, level = entry.l })
			end
		end
	end
	return result
end

local function endBattle(player: Player)
	local battle = battles[player]
	if not battle then
		return
	end
	battles[player] = nil
	local ok, err = pcall(battle.destroy, battle)
	if not ok then
		warn("[StarKingdomDefense] cleaning up a battle failed: " .. tostring(err))
	end
	Net.ev("BattleState"):FireClient(player, { active = false })
	teleport(player, Lobby.spawnCFrame())
	-- the arena slot is free again once its terrain is gone
	task.spawn(function()
		MapBuilder.clear(battle.origin)
		slotsInUse[battle.slot] = nil
	end)
end

handle("StartBattle", function(player, kind, id, stage)
	local data = DataService.get(player)
	if not data then
		return false, "Your data is still loading"
	end
	if battles[player] then
		return false, "You are already in a battle"
	end
	local mapId, challenge
	if kind == "challenge" then
		challenge = Challenges.ById[id]
		if not challenge then
			return false, "Unknown challenge"
		end
		mapId = challenge.map
		stage = challenge.stage
		if not mapUnlocked(data, mapId) or (data.progress[mapId] or 0) < 1 then
			return false, "Clear stage 1 of " .. Maps.ById[mapId].name .. " to unlock this challenge"
		end
	else
		mapId = id
		if not Maps.ById[mapId] or type(stage) ~= "number" or stage < 1 or stage > Maps.Stages or stage % 1 ~= 0 then
			return false, "Unknown stage"
		end
		if not mapUnlocked(data, mapId) then
			return false, "Map locked: beat stage " .. Maps.Stages .. " of the previous map"
		end
		if (data.progress[mapId] or 0) < stage - 1 then
			return false, "Beat stage " .. (stage - 1) .. " first"
		end
	end

	local team = {}
	local any = false
	for i = 1, Units.TeamSize do
		local uid = data.team[i]
		local entry = uid ~= "" and data.units[uid]
		if entry and Progression.slotUnlocked(data.level, i) then
			team[i] = { uid = uid, unitId = entry.u, trait = entry.t, level = entry.l or 1, grades = entry.g or Progression.DefaultGrades }
			any = true
		end
	end
	if not any then
		return false, "Equip at least one unit on your team first"
	end

	local slot = 1
	while slotsInUse[slot] do
		slot += 1
	end
	slotsInUse[slot] = true

	local battle = Battle.new(player, {
		mapId = mapId,
		stage = stage,
		challenge = challenge,
		team = team,
		slot = slot,
		onEnd = function(b, won)
			local d = DataService.get(player)
			if not d then
				return
			end
			local result = rewardsFor(d, b, won)
			DataService.changed(player)
			battleEnded:FireClient(player, result)
			task.spawn(DataService.save, player)
		end,
	})
	battles[player] = battle
	teleport(player, battle:spawnPoint())
	return true
end)

local function withBattle(fn: (any, ...any) -> ...any)
	return function(player, ...)
		local battle = battles[player]
		if not battle then
			return false, "You are not in a battle"
		end
		return fn(battle, ...)
	end
end

handle(
	"PlaceUnit",
	withBattle(function(battle, slot, position)
		if type(slot) ~= "number" or typeof(position) ~= "Vector3" then
			return false, "Invalid placement"
		end
		return battle:place(slot, position)
	end)
)

handle(
	"UpgradeTower",
	withBattle(function(battle, id)
		if type(id) ~= "number" then
			return false, "Invalid"
		end
		return battle:upgrade(id)
	end)
)

handle(
	"SellTower",
	withBattle(function(battle, id)
		if type(id) ~= "number" then
			return false, "Invalid"
		end
		return battle:sell(id)
	end)
)

handle(
	"SetTargeting",
	withBattle(function(battle, id, mode)
		if type(id) ~= "number" or type(mode) ~= "string" then
			return false, "Invalid"
		end
		return battle:setTargeting(id, mode)
	end)
)

handle(
	"StartWave",
	withBattle(function(battle)
		return battle:startNextWave()
	end)
)

handle(
	"SetSpeed",
	withBattle(function(battle, speed)
		if type(speed) ~= "number" then
			return false
		end
		battle:setSpeed(speed)
		return true
	end)
)

handle("LeaveBattle", function(player)
	if battles[player] then
		local battle = battles[player]
		-- leaving mid-battle counts as a loss (no rewards beyond waves survived)
		if battle.state ~= "won" and battle.state ~= "lost" then
			pcall(battle.finish, battle, false)
		end
		endBattle(player)
	end
	return true
end)

-- ============================================================ admin panel

-- user ids that may use the admin panel; the game's owner and anyone testing in Studio always may
local ADMINS: { number } = {}

local RunService = game:GetService("RunService")

local function isAdmin(player: Player): boolean
	return RunService:IsStudio() or player.UserId == game.CreatorId or table.find(ADMINS, player.UserId) ~= nil
end

local adminActions: { [string]: (Player, any, any) -> (boolean, string?) } = {
	gems = function(player, n)
		local data = DataService.get(player)
		data.gems = math.max(0, data.gems + math.floor(tonumber(n) or 0))
		return true, "Gems: " .. data.gems
	end,
	crystals = function(player, n)
		local data = DataService.get(player)
		data.crystals = math.max(0, data.crystals + math.floor(tonumber(n) or 0))
		return true, "Crystals: " .. data.crystals
	end,
	level = function(player, n)
		local data = DataService.get(player)
		data.level = math.clamp(math.floor(tonumber(n) or 1), 1, 999)
		data.xp = 0
		return true, "Player level " .. data.level
	end,
	giveUnit = function(player, unitId, count)
		local data = DataService.get(player)
		if not Units.ById[unitId] then
			return false, "Unknown unit"
		end
		for _ = 1, math.clamp(math.floor(tonumber(count) or 1), 1, 50) do
			local uid = DataService.addUnit(data, unitId)
			data.units[uid].g = Progression.rollGrades(rng)
		end
		return true, "Gave " .. Units.ById[unitId].name
	end,
	maxUnits = function(player)
		local data = DataService.get(player)
		for _, e in data.units do
			e.l, e.x, e.g = Progression.MaxLevel, 0, { d = "SSS", s = "SSS", r = "SSS" }
		end
		return true, "Every unit is Lvl 50 with SSS grades"
	end,
	traitTeam = function(player, traitId)
		local data = DataService.get(player)
		if not Traits.ById[traitId] then
			return false, "Unknown trait"
		end
		for _, uid in data.team do
			if uid ~= "" and data.units[uid] then
				data.units[uid].t = traitId
			end
		end
		return true, "Team trait: " .. Traits.ById[traitId].name
	end,
	unlockMaps = function(player)
		local data = DataService.get(player)
		for _, m in Maps.List do
			data.progress[m.id] = Maps.Stages
		end
		return true, "Every map and stage unlocked"
	end,
	resetChallenges = function(player)
		local data = DataService.get(player) :: any
		data.challenges = {}
		return true, "Challenges can be cleared again today"
	end,
	cash = function(player, n)
		local battle = battles[player]
		if not battle then
			return false, "Not in a battle"
		end
		battle.cash += math.floor(tonumber(n) or 0)
		return true, "Cash: " .. battle.cash
	end,
	nextWave = function(player)
		local battle = battles[player]
		if not battle or battle.state ~= "wave" and battle.state ~= "prep" then
			return false, "No wave to skip"
		end
		battle.timer = 0
		if battle.state == "prep" then
			battle:startNextWave()
		end
		return true, "Next wave"
	end,
	killAll = function(player)
		local battle = battles[player]
		if not battle then
			return false, "Not in a battle"
		end
		for _, e in table.clone(battle.enemies) do
			battle:kill(e, nil)
		end
		return true, "Cleared the field"
	end,
	heal = function(player)
		local battle = battles[player]
		if not battle then
			return false, "Not in a battle"
		end
		battle.baseHp = Maps.BaseHealth
		return true, "Castle healed"
	end,
	win = function(player)
		local battle = battles[player]
		if not battle then
			return false, "Not in a battle"
		end
		battle:finish(true)
		return true, "Victory"
	end,
}

handle("Admin", function(player, action, a, b)
	if not isAdmin(player) then
		return false, "Not an admin"
	end
	local fn = type(action) == "string" and adminActions[action]
	if not fn or not DataService.get(player) then
		return false, "Unknown action"
	end
	local ok, msg = fn(player, a, b)
	DataService.changed(player)
	return ok, msg
end)

-- ============================================================ players

local function onPlayer(player: Player)
	player:SetAttribute("IsAdmin", isAdmin(player))
end
for _, p in Players:GetPlayers() do
	onPlayer(p)
end
Players.PlayerAdded:Connect(onPlayer)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		local battle = battles[player]
		if battle then
			teleport(player, battle:spawnPoint())
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local battle = battles[player]
	if battle then
		battles[player] = nil
		pcall(battle.destroy, battle)
		task.spawn(function()
			MapBuilder.clear(battle.origin)
			slotsInUse[battle.slot] = nil
		end)
	end
end)

