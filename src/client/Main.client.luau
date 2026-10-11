-- Client entry point.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Store = require(script.Parent.Store)
local Fx = require(script.Parent.Fx)
local LobbyUI = require(script.Parent.LobbyUI)
local BattleUI = require(script.Parent.BattleUI)
local Ui = require(script.Parent.Ui)
local Skins = require(script.Parent.Skins)
local Animator = require(script.Parent.Animator)
local AdminPanel = require(script.Parent.AdminPanel)
local Travel = require(script.Parent.Travel)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

Store.start()
Travel.start()
Fx.start()
Skins.start()
Animator.start()

-- wait for the save data before building the lobby
while not Store.data do
	Store.DataChanged:Wait()
end

local lobbyGui = LobbyUI.start()
local battleGui = BattleUI.start()
AdminPanel.start()

-- a battle server has no lobby: its menus stay hidden
local battleServer = workspace:GetAttribute("BattleServer") == true
LobbyUI.setVisible(not battleServer)
Store.BattleChanged:Connect(function(state)
	LobbyUI.setVisible(not state.active and not battleServer)
end)

-- scale the UI down on small screens
local camera = workspace.CurrentCamera
local function rescale()
	local size = camera.ViewportSize
	local scale = math.clamp(math.min(size.X / 1280, size.Y / 760), 0.5, 1.25)
	for _, g in { lobbyGui, battleGui } do
		local s = g:FindFirstChild("Scale")
		if s then
			s.Scale = scale
		end
	end
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

Ui.toast("Welcome to Star Kingdom Defense, " .. Players.LocalPlayer.DisplayName .. "!", Ui.Colors.purple)
