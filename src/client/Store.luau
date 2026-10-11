-- The client's copy of the player's save data and the current battle state, with change signals.
local Net = require(game.ReplicatedStorage.Shared.Net)

local Store = {}

Store.data = nil :: any
Store.battle = { active = false } :: any

local dataChanged = Instance.new("BindableEvent")
local battleChanged = Instance.new("BindableEvent")
Store.DataChanged = dataChanged.Event
Store.BattleChanged = battleChanged.Event

function Store.start()
	Net.ev("DataChanged").OnClientEvent:Connect(function(data)
		Store.data = data
		dataChanged:Fire(data)
	end)
	Net.ev("BattleState").OnClientEvent:Connect(function(state)
		Store.battle = state
		battleChanged:Fire(state)
	end)
	task.spawn(function()
		local data = Net.fn("GetData"):InvokeServer()
		if data and not Store.data then
			Store.data = data
			dataChanged:Fire(data)
		end
	end)
end

-- invoke a remote, toasting the error message when it fails
function Store.call(name: string, ...: any): (boolean, any)
	local ok, result, extra = pcall(Net.fn(name).InvokeServer, Net.fn(name), ...)
	if not ok then
		return false, "Connection problem"
	end
	if result == false then
		return false, extra
	end
	return true, extra
end

return Store
