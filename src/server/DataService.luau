-- Player save data in a DataStore. In Studio without "Enable Studio Access to API Services" (or in an unpublished
-- place) the DataStore calls fail; the game then runs on fresh, unsaved data and says so once.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Units = require(game.ReplicatedStorage.Shared.Units)

local DataService = {}

local STORE_NAME = "StarKingdomDefense_v1"
local AUTOSAVE_SECONDS = 120

export type UnitEntry = { u: string, t: string? }
export type Data = {
	gems: number,
	crystals: number,
	units: { [string]: UnitEntry },
	nextUid: number,
	team: { string },
	progress: { [string]: number },
	challenges: { [string]: number },
	pity: { legendary: number, mythic: number },
	stats: { [string]: number },
}

local store: DataStore? = nil
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local profiles: { [Player]: Data } = {}
local canSave: { [Player]: boolean } = {} -- only after a successful load, so a failed load never overwrites a save
local saving: { [Player]: boolean } = {}
local changedCallback: ((Player, Data) -> ())? = nil

local function defaultData(): Data
	return {
		gems = 500, -- enough for one 10x summon
		crystals = 3,
		units = { ["1"] = { u = "mushling" }, ["2"] = { u = "shellback" } },
		nextUid = 3,
		team = { "1", "2", "", "", "", "" },
		progress = {},
		challenges = {},
		pity = { legendary = 0, mythic = 0 },
		stats = { summons = 0, wins = 0, rolls = 0 },
	}
end

-- fill fields added after a save was written, drop units that no longer exist
local function reconcile(data: any): Data
	local fresh = defaultData()
	if type(data) ~= "table" then
		return fresh
	end
	for k, v in fresh :: any do
		if data[k] == nil then
			data[k] = v
		end
	end
	for uid, entry in data.units do
		if type(entry) ~= "table" or not Units.ById[entry.u] then
			data.units[uid] = nil
		end
	end
	for i = 1, Units.TeamSize do
		local uid = data.team[i]
		if type(uid) ~= "string" or (uid ~= "" and not data.units[uid]) then
			data.team[i] = ""
		end
	end
	return data
end

local warned = false
local function warnOnce(msg: string)
	if not warned then
		warned = true
		warn("[StarKingdomDefense] " .. msg)
	end
end

local function load(player: Player): (Data, boolean)
	if not storeOk or not store then
		warnOnce("DataStores are unavailable: progress will not be saved (publish the place and enable API access).")
		return defaultData(), false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync("p_" .. player.UserId)
		end)
		if ok then
			return reconcile(result), true
		end
		warnOnce("DataStore load failed (" .. tostring(result) .. "); progress will not be saved this session.")
		if attempt < 3 then
			task.wait(1)
		end
	end
	return defaultData(), false
end

function DataService.save(player: Player)
	local data = profiles[player]
	if not data or not store or not canSave[player] or saving[player] then
		return
	end
	saving[player] = true
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync("p_" .. player.UserId, data)
	end)
	saving[player] = nil
	if not ok then
		warnOnce("DataStore save failed: " .. tostring(err))
	end
end

function DataService.get(player: Player): Data?
	return profiles[player]
end

-- call after changing a player's data: sends it to their client
function DataService.changed(player: Player)
	local data = profiles[player]
	if data and changedCallback then
		changedCallback(player, data)
	end
end

function DataService.onChanged(callback: (Player, Data) -> ())
	changedCallback = callback
end

function DataService.addUnit(data: Data, unitId: string): string
	local uid = tostring(data.nextUid)
	data.nextUid += 1
	data.units[uid] = { u = unitId }
	return uid
end

function DataService.unitCount(data: Data): number
	local n = 0
	for _ in data.units do
		n += 1
	end
	return n
end

function DataService.start()
	local function onJoin(player: Player)
		local data, ok = load(player)
		if player.Parent then
			profiles[player] = data
			canSave[player] = ok
			DataService.changed(player)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in Players:GetPlayers() do
		task.spawn(onJoin, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		profiles[player] = nil
		canSave[player] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			task.spawn(DataService.save, p)
		end
		task.wait(2)
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for _, p in Players:GetPlayers() do
				task.spawn(DataService.save, p)
			end
		end
	end)
end

-- the client may call GetData before the profile has loaded
function DataService.waitFor(player: Player, timeout: number): Data?
	local t = 0
	while not profiles[player] and t < timeout and player.Parent do
		t += task.wait(0.1)
	end
	return profiles[player]
end

return DataService
