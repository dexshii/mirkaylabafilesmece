-- The loading screen shown while the player is teleported between the lobby and a battle server (the server
-- sets the player's "Travel" attribute), and while a battle server sets up the battle after arriving.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Ui = require(script.Parent.Ui)
local Store = require(script.Parent.Store)
local Audio = require(script.Parent.Audio)

local Travel = {}

local C = Ui.Colors

local function build(text: string): ScreenGui
	local gui = Ui.new("ScreenGui", { Name = "Travel", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 50 })
	local bg = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = gui }, {
		Ui.gradient(Color3.fromRGB(70, 40, 150), Color3.fromRGB(14, 8, 34)),
	})
	local star = Ui.icon("star", "⭐", { Name = "Star", Size = UDim2.fromOffset(150, 150), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), MaxText = 120, Parent = bg })
	star:SetAttribute("Spin", true)
	Ui.title({
		Name = "Caption",
		Text = text,
		Size = UDim2.fromOffset(800, 60),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, 100),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxText = 46,
		Outline = 3,
		Parent = bg,
	})
	Ui.text({
		Text = "Star Kingdom Defense",
		Size = UDim2.fromOffset(400, 28),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.muted,
		MaxText = 22,
		Parent = bg,
	})
	return gui
end

function Travel.start()
	local player = Players.LocalPlayer
	local current: ScreenGui? = nil
	local function show(text: string?)
		if current then
			current:Destroy()
			current = nil
		end
		if text then
			Audio.play("enter_pipe", { gap = 1 })
			local gui = build(text)
			gui.Parent = player:WaitForChild("PlayerGui")
			current = gui
			-- shown during the teleport itself too
			pcall(function()
				TeleportService:SetTeleportGui(build(text))
			end)
		end
	end
	RunService.RenderStepped:Connect(function(dt)
		local star = current and current:FindFirstChild("Star", true)
		if star and star:IsA("GuiObject") then
			star.Rotation += dt * 120
		end
	end)
	player:GetAttributeChangedSignal("Travel"):Connect(function()
		show(player:GetAttribute("Travel"))
	end)
	-- a battle server: cover the empty world until the battle has started
	if workspace:GetAttribute("BattleServer") then
		show("Loading battle...")
		Store.BattleChanged:Connect(function(state)
			if state.active and not player:GetAttribute("Travel") then
				show(nil)
			end
		end)
	end
end

return Travel
