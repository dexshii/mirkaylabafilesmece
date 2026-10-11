-- Remote names in one place. The server creates them (Net.setup); clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

Net.Functions = {
	"GetData",
	"Summon",
	"EquipUnit",
	"RollTrait",
	"ReleaseUnit",
	"LockUnit",
	"Admin",
	"StartBattle",
	"PlaceUnit",
	"UpgradeTower",
	"SellTower",
	"SetTargeting",
	"StartWave",
	"SetSpeed",
	"LeaveBattle",
}

Net.Events = {
	"DataChanged",
	"BattleState",
	"BattleEnded",
	"Fx",
	"Notify",
}

function Net.setup()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in Net.Functions do
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = folder
	end
	for _, name in Net.Events do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function Net.fn(name: string): RemoteFunction
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteFunction
end

function Net.ev(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

return Net
