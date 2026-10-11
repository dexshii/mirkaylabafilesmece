-- The admin panel (F2, or the ADMIN button), for players the server marks with the IsAdmin attribute: give
-- currency, units and traits, unlock maps, control the current battle, and see which SM64 models built.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game.ReplicatedStorage.Shared
local Units = require(Shared.Units)
local Traits = require(Shared.Traits)
local Rarities = require(Shared.Rarities)

local Ui = require(script.Parent.Ui)
local Store = require(script.Parent.Store)
local Skins = require(script.Parent.Skins)
local Audio = require(script.Parent.Audio)

local AdminPanel = {}

local C = Ui.Colors

local function act(action: string, a: any?, b: any?)
	local ok, msg = Store.call("Admin", action, a, b)
	Ui.toast(msg or (ok and "Done" or "Failed"), ok and C.green or C.red)
end

local function section(parent: Instance, title: string, order: number, height: number): Frame
	local f = Ui.inset(parent, { Size = UDim2.new(1, -12, 0, height), LayoutOrder = order })
	Ui.title({ Text = title, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), MaxText = 20, Parent = f })
	local row = Ui.new("Frame", { Name = "Row", Size = UDim2.new(1, -20, 1, -40), Position = UDim2.fromOffset(10, 34), BackgroundTransparency = 1, Parent = f }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(150, 40), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	return row
end

local function numberBox(parent: Instance, default: string): TextBox
	return Ui.new("TextBox", {
		Text = default,
		Font = Ui.Font,
		TextSize = 20,
		TextColor3 = C.text,
		BackgroundColor3 = Color3.fromRGB(14, 10, 26),
		ClearTextOnFocus = false,
		Parent = parent,
	}, { Ui.corner(8), Ui.stroke(C.gold, 2) })
end

function AdminPanel.start()
	local player = Players.LocalPlayer
	local gui = Ui.new("ScreenGui", { Name = "Admin", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, Parent = player:WaitForChild("PlayerGui") })
	local window, content = Ui.window(gui, "Admin", "🛠", UDim2.fromOffset(720, 600), function() end)
	local close = window:FindFirstChildWhichIsA("TextButton")
	local scroll = Ui.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 10), Ui.padding(4) })

	local currency = section(scroll, "💎 Currency", 1, 140)
	local amount = numberBox(currency, "1000")
	Ui.button("+ Gems", C.blue, function()
		act("gems", tonumber(amount.Text) or 0)
	end, { Parent = currency })
	Ui.button("- Gems", C.panel, function()
		act("gems", -(tonumber(amount.Text) or 0))
	end, { Parent = currency })
	Ui.button("+ Crystals", C.purple, function()
		act("crystals", tonumber(amount.Text) or 0)
	end, { Parent = currency })
	Ui.button("Set Player Lvl", C.gold, function()
		act("level", tonumber(amount.Text) or 1)
	end, { Parent = currency })

	local unitsRow = section(scroll, "🎒 Give units", 2, 40 + math.ceil(#Units.List / 4) * 48)
	for _, def in Units.List do
		local b = Ui.button(Ui.unitName(def.id), Ui.RarityGradient[def.rarity][2], function()
			act("giveUnit", def.id, 1)
		end, { MaxText = 16, Parent = unitsRow })
		b.LayoutOrder = -Rarities.Info[def.rarity].rank
	end

	local unitTools = section(scroll, "⭐ Units and traits", 3, 40 + math.ceil((#Traits.List + 1) / 4) * 48)
	Ui.button("Max all units", C.gold, function()
		act("maxUnits")
	end, { LayoutOrder = -10, Parent = unitTools })
	for i, t in Traits.List do
		Ui.button("Team: " .. t.name, Rarities.Info[t.rarity].color, function()
			act("traitTeam", t.id)
		end, { LayoutOrder = i, MaxText = 15, Parent = unitTools })
	end

	local progress = section(scroll, "🗺 Progress", 4, 90)
	Ui.button("Unlock all maps", C.green, function()
		act("unlockMaps")
	end, { Parent = progress })
	Ui.button("Reset challenges", C.orange, function()
		act("resetChallenges")
	end, { Parent = progress })

	local battle = section(scroll, "⚔ Current battle", 5, 140)
	Ui.button("+ Cash", C.gold, function()
		act("cash", tonumber(amount.Text) or 0)
	end, { Parent = battle })
	Ui.button("Next wave", C.blue, function()
		act("nextWave")
	end, { Parent = battle })
	Ui.button("Kill all", C.red, function()
		act("killAll")
	end, { Parent = battle })
	Ui.button("Heal castle", C.green, function()
		act("heal")
	end, { Parent = battle })
	Ui.button("Win battle", C.purple, function()
		act("win")
	end, { Parent = battle })

	local sm64 = Ui.inset(scroll, { Size = UDim2.new(1, -12, 0, 150), LayoutOrder = 6 })
	Ui.title({ Text = "🍄 SM64 models", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 6), MaxText = 20, Parent = sm64 })
	local modeButton
	modeButton = Ui.button("Mode: " .. Skins.mode, C.blue, function()
		Skins.setMode(Skins.mode == "mesh" and "parts" or "mesh")
		modeButton.Text = "Mode: " .. Skins.mode
		Ui.toast("SM64 models rebuilt as " .. Skins.mode, C.green)
	end, { Size = UDim2.fromOffset(160, 32), Position = UDim2.new(1, -170, 0, 4), MaxText = 16, Parent = sm64 })
	local status = Ui.text({ Text = "", Size = UDim2.new(1, -20, 1, -40), Position = UDim2.fromOffset(10, 40), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, MaxText = 14, Parent = sm64 })

	local function toggle()
		window.Visible = not window.Visible
		if window.Visible then
			Ui.pop(window)
			local lines = { Audio.status() }
			if not Skins.available() then
				table.insert(lines, "No SM64Models folder: this is the build without SM64 models.")
			else
				local any = false
				for key, err in Skins.failures do
					any = true
					table.insert(lines, key .. ": " .. err)
				end
				if not any then
					table.insert(lines, "No failures so far.")
				end
			end
			status.Text = table.concat(lines, "\n")
		end
	end
	if close then
		close.Activated:Connect(toggle)
	end

	local openButton = Ui.button("🛠 ADMIN", C.red, toggle, { Size = UDim2.fromOffset(110, 36), Position = UDim2.new(1, -124, 1, -50), MaxText = 18, Parent = gui })
	local function refresh()
		local admin = player:GetAttribute("IsAdmin") == true
		gui.Enabled = admin
		openButton.Visible = admin
	end
	player:GetAttributeChangedSignal("IsAdmin"):Connect(refresh)
	refresh()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.F2 and player:GetAttribute("IsAdmin") then
			toggle()
		end
	end)
end

return AdminPanel
