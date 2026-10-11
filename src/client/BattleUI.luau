-- The battle HUD: wave/cash/castle health, the unit hotbar, placing units, the selected-unit panel and the
-- victory/defeat screen.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Shared = game.ReplicatedStorage.Shared
local Units = require(Shared.Units)
local Traits = require(Shared.Traits)
local Rarities = require(Shared.Rarities)
local Maps = require(Shared.Maps)
local Stats = require(Shared.Stats)
local ModelFactory = require(Shared.ModelFactory)
local Net = require(Shared.Net)

local Ui = require(script.Parent.Ui)
local Store = require(script.Parent.Store)

local BattleUI = {}

local C = Ui.Colors
local player = Players.LocalPlayer
local gui: ScreenGui

local waveLabel: TextLabel
local statusLabel: TextLabel
local cashLabel: TextLabel
local hpFill: Frame
local hpLabel: TextLabel
local speedButton: TextButton
local startButton: TextButton
local hotbar: Frame
local infoPanel: Frame
local endPanel: Frame

local placingSlot: number? = nil
local ghost: Model? = nil
local ghostRange: Part? = nil
local selectedTower: Model? = nil
local selectedRange: Part? = nil
local leaving = false
local hotbarKey = ""

local defaultLighting = {
	ClockTime = Lighting.ClockTime,
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	FogColor = Lighting.FogColor,
	FogEnd = Lighting.FogEnd,
}

local function arena(): Model?
	local state = Store.battle
	if not state.active then
		return nil
	end
	return workspace:FindFirstChild("Arena_" .. state.mapId) :: Model?
end

local function towerFolder(): Instance?
	local a = arena()
	return a and a:FindFirstChild("Units")
end

-- ============================================================ range circles

local function rangeDisc(radius: number, color: Color3): Part
	local disc = Instance.new("Part")
	disc.Name = "Range"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.ForceField
	disc.Color = color
	disc.Size = Vector3.new(0.4, radius * 2, radius * 2)
	disc.Parent = workspace
	return disc
end

local function placeDisc(disc: Part, pos: Vector3)
	disc.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

-- ============================================================ placement

local function cancelPlacement()
	placingSlot = nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if ghostRange then
		ghostRange:Destroy()
		ghostRange = nil
	end
end

local function deselect()
	selectedTower = nil
	if selectedRange then
		selectedRange:Destroy()
		selectedRange = nil
	end
	infoPanel.Visible = false
end

local function startPlacement(slot: number)
	local member = Store.battle.team and Store.battle.team[slot]
	if not member then
		return
	end
	if not member.allowed then
		Ui.toast("That unit is not allowed in this challenge", C.red)
		return
	end
	cancelPlacement()
	deselect()
	placingSlot = slot
	local model = ModelFactory.build(member.unitId, 1, true)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanCollide = false
			if d.Transparency < 1 then
				d.Transparency = 0.4
			end
		end
	end
	model.Parent = workspace
	ghost = model
	local s = Stats.compute(member.unitId, 0, member.trait, nil)
	ghostRange = rangeDisc(math.max(s.range, 2), C.green)
end

local function groundHit(): RaycastResult?
	local a = arena()
	local ground = a and a:FindFirstChild("Ground")
	if not ground then
		return nil
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ground }
	return workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
end

local function placementProblem(pos: Vector3): string?
	local state = Store.battle
	local map = Maps.ById[state.mapId]
	local others = {}
	local folder = towerFolder()
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				table.insert(others, m:GetPivot().Position - state.origin)
			end
		end
	end
	local x, z = pos.X - state.origin.X, pos.Z - state.origin.Z
	return Stats.placementProblem(map.waypoints, Maps.FieldHalf, Maps.PathWidth, x, z, others)
end

local function updateGhost()
	if not ghost or not ghostRange then
		return
	end
	local hit = groundHit()
	if not hit then
		ghost:PivotTo(CFrame.new(0, -500, 0))
		placeDisc(ghostRange, Vector3.new(0, -500, 0))
		return
	end
	local pos = Vector3.new(hit.Position.X, Store.battle.origin.Y, hit.Position.Z)
	ghost:PivotTo(CFrame.new(pos))
	placeDisc(ghostRange, pos)
	ghostRange.Color = placementProblem(pos) and C.red or C.green
end

local function tryPlace()
	if not placingSlot then
		return
	end
	local hit = groundHit()
	if not hit then
		return
	end
	local pos = Vector3.new(hit.Position.X, Store.battle.origin.Y, hit.Position.Z)
	local problem = placementProblem(pos)
	if problem then
		Ui.toast(problem, C.red)
		return
	end
	local slot = placingSlot
	local ok, err = Store.call("PlaceUnit", slot, pos)
	if not ok then
		Ui.toast(err or "Can't place there", C.red)
		return
	end
	-- hold Shift to keep placing the same unit
	if not UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		cancelPlacement()
	end
end

-- ============================================================ selected unit panel

local function refreshInfo()
	local model = selectedTower
	if not model or not model.Parent then
		deselect()
		return
	end
	local unitId = model:GetAttribute("UnitId")
	local def = Units.ById[unitId]
	local level = model:GetAttribute("Level") or 0
	local traitId = model:GetAttribute("Trait")
	if traitId == "" then
		traitId = nil
	end
	local buffs = { damage = model:GetAttribute("DamageBuff") or 0, hitsAir = model:GetAttribute("AirBuff") == true }
	local s = Stats.compute(unitId, level, traitId, buffs)
	local spent = model:GetAttribute("Spent") or 0
	local targeting = model:GetAttribute("Targeting") or "First"

	Ui.clear(infoPanel)
	infoPanel.Visible = true
	Ui.viewport(unitId, { Size = UDim2.fromOffset(90, 90), BackgroundColor3 = Rarities.Info[def.rarity].color:Lerp(Color3.new(0, 0, 0), 0.5), Parent = infoPanel })
	Ui.text({ Text = def.name, Size = UDim2.new(1, -100, 0, 26), Position = UDim2.fromOffset(100, 0), MaxText = 22, Parent = infoPanel })
	Ui.text({
		Text = string.rep("★", level) .. string.rep("☆", Units.MaxLevel - level),
		Size = UDim2.new(1, -100, 0, 22),
		Position = UDim2.fromOffset(100, 28),
		TextColor3 = C.gold,
		MaxText = 20,
		Parent = infoPanel,
	})
	local trait = traitId and Traits.ById[traitId]
	Ui.text({
		Text = trait and trait.name or "No trait",
		Size = UDim2.new(1, -100, 0, 20),
		Position = UDim2.fromOffset(100, 54),
		TextColor3 = trait and Rarities.Info[trait.rarity].color or C.muted,
		MaxText = 16,
		Parent = infoPanel,
	})
	local lines
	if def.attack.kind == "none" then
		lines = string.format("Pays $%d per wave", s.farm)
	else
		lines = string.format("Damage %.0f  Range %.0f\nAttack every %.2fs\nHits %s", s.damage, s.range, s.cooldown, (s.hitsGround and "ground" or "") .. (s.hitsGround and s.hitsAir and " + " or "") .. (s.hitsAir and "air" or ""))
		if s.farm > 0 then
			lines ..= string.format("\nPays $%d per wave", s.farm)
		end
		if buffs.damage > 0 then
			lines ..= string.format("\nAura buff +%d%% damage", buffs.damage * 100)
		end
	end
	Ui.text({
		Text = lines,
		Size = UDim2.new(1, 0, 0, 78),
		Position = UDim2.fromOffset(0, 96),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		MaxText = 16,
		Parent = infoPanel,
	})
	local id = model:GetAttribute("TowerId")
	if level < Units.MaxLevel then
		local cost = Stats.upgradeCost(unitId, level, traitId)
		Ui.button("Upgrade $" .. Ui.formatNumber(cost), C.green, function()
			local ok, err = Store.call("UpgradeTower", id)
			if not ok then
				Ui.toast(err or "Can't upgrade", C.red)
			end
			task.wait(0.1)
			refreshInfo()
		end, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 178), Parent = infoPanel })
	else
		Ui.button("MAX LEVEL", C.card, function() end, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 178), Parent = infoPanel })
	end
	if def.attack.kind ~= "none" then
		Ui.button("Target: " .. targeting, C.blue, function()
			local modes = { "First", "Last", "Strongest", "Closest" }
			local nextMode = modes[(table.find(modes, targeting) or 0) % #modes + 1]
			Store.call("SetTargeting", id, nextMode)
			task.wait(0.1)
			refreshInfo()
		end, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 224), Parent = infoPanel })
	end
	Ui.button("Sell +$" .. Ui.formatNumber(math.floor(spent * 0.6)), C.red, function()
		Store.call("SellTower", id)
		deselect()
	end, { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 266), Parent = infoPanel })

	if selectedRange then
		selectedRange:Destroy()
	end
	local disc = rangeDisc(math.max(s.range, 2), Rarities.Info[def.rarity].color)
	placeDisc(disc, model:GetPivot().Position)
	selectedRange = disc
end

local function trySelect()
	local folder = towerFolder()
	if not folder then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	local model = hit and hit.Instance:FindFirstAncestorWhichIsA("Model")
	while model and model.Parent ~= folder do
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	if model then
		selectedTower = model
		refreshInfo()
	end
end

-- ============================================================ HUD

local function refreshHotbar(state)
	-- rebuild only when the team or what is allowed changes; costs and counts update in place
	local key = ""
	for i = 1, Units.TeamSize do
		local m = state.team[i]
		key ..= (m and (m.unitId .. tostring(m.allowed)) or "-") .. ","
	end
	if key ~= hotbarKey then
		hotbarKey = key
		Ui.clear(hotbar)
		for i = 1, Units.TeamSize do
			local m = state.team[i]
			if m then
				local def = Units.ById[m.unitId]
				local card = Ui.new("TextButton", {
					Name = "Slot" .. i,
					Text = "",
					Size = UDim2.fromOffset(96, 112),
					BackgroundColor3 = m.allowed and C.card or C.panelDark,
					LayoutOrder = i,
					Parent = hotbar,
				}, { Ui.corner(10), Ui.stroke(Rarities.Info[def.rarity].color, 3) })
				Ui.viewport(m.unitId, {
					Size = UDim2.new(1, -8, 1, -40),
					Position = UDim2.fromOffset(4, 4),
					BackgroundColor3 = Rarities.Info[def.rarity].color:Lerp(Color3.new(0, 0, 0), 0.55),
					Parent = card,
				})
				Ui.text({ Name = "Key", Text = tostring(i), Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(6, 4), ZIndex = 3, MaxText = 16, Parent = card })
				Ui.text({ Name = "Cost", Text = "", Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 1, -36), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.gold, MaxText = 16, Parent = card })
				Ui.text({ Name = "Count", Text = "", Size = UDim2.new(1, -8, 0, 16), Position = UDim2.new(0, 4, 1, -18), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.muted, MaxText = 13, Parent = card })
				card.Activated:Connect(function()
					if placingSlot == i then
						cancelPlacement()
					else
						startPlacement(i)
					end
				end)
			end
		end
	end
	for i = 1, Units.TeamSize do
		local m = state.team[i]
		local card = hotbar:FindFirstChild("Slot" .. i)
		if m and card then
			local def = Units.ById[m.unitId]
			card.Cost.Text = "$" .. Ui.formatNumber(m.cost)
			card.Cost.TextColor3 = state.cash >= m.cost and C.gold or C.red
			card.Count.Text = m.allowed and (m.placed .. "/" .. def.limit) or "not allowed"
		end
	end
end

local function applyLighting(mapId: string?)
	if mapId then
		local theme = Maps.ById[mapId].theme
		Lighting.ClockTime = theme.clock
		Lighting.Ambient = theme.ambient
		Lighting.OutdoorAmbient = theme.ambient
		Lighting.FogColor = theme.fog
		Lighting.FogEnd = 700
	else
		for k, v in defaultLighting do
			(Lighting :: any)[k] = v
		end
	end
end

local wasActive = false
local function onState(state)
	if not state.active then
		if wasActive then
			wasActive = false
			cancelPlacement()
			deselect()
			applyLighting(nil)
			endPanel.Visible = false
			hotbarKey = ""
		end
		gui.Enabled = false
		return
	end
	if not wasActive then
		wasActive = true
		leaving = false
		endPanel.Visible = false
		applyLighting(state.mapId)
	end
	gui.Enabled = true
	waveLabel.Text = string.format("Wave %d / %d", state.wave, state.waves)
	if state.state == "prep" then
		statusLabel.Text = "Place your units! First wave in " .. state.timer .. "s"
	elseif state.state == "break" then
		statusLabel.Text = "Next wave in " .. state.timer .. "s"
	elseif state.state == "wave" then
		statusLabel.Text = state.enemies .. " enemies"
	elseif state.state == "won" then
		statusLabel.Text = "Victory!"
	else
		statusLabel.Text = "Defeat"
	end
	if state.maxUnits then
		statusLabel.Text ..= string.format("   |   units %d/%d", state.units, state.maxUnits)
	end
	cashLabel.Text = "$" .. Ui.formatNumber(state.cash)
	hpFill.Size = UDim2.fromScale(math.clamp(state.baseHp / state.maxBaseHp, 0, 1), 1)
	hpLabel.Text = "Castle " .. state.baseHp .. " / " .. state.maxBaseHp
	speedButton.Text = state.speed .. "x speed"
	startButton.Visible = state.state == "prep" or state.state == "break"
	refreshHotbar(state)
	if selectedTower and infoPanel.Visible then
		-- costs and stats may have changed (cash, auras)
		local level = selectedTower:GetAttribute("Level")
		if level ~= infoPanel:GetAttribute("Level") then
			infoPanel:SetAttribute("Level", level)
			refreshInfo()
		end
	end
end

local function showEnd(result)
	if leaving then
		return
	end
	cancelPlacement()
	deselect()
	Ui.clear(endPanel)
	endPanel.Visible = true
	Ui.text({
		Text = result.won and "VICTORY!" or "DEFEAT",
		Size = UDim2.new(1, 0, 0, 60),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = result.won and C.gold or C.red,
		TextStrokeTransparency = 0,
		MaxText = 56,
		Parent = endPanel,
	})
	local lines = { string.format("Waves cleared: %d / %d", result.won and result.waves or math.max(0, result.wave - 1), result.waves) }
	if result.challenge then
		table.insert(lines, "Challenge: " .. result.challenge)
	end
	table.insert(lines, "+" .. result.gems .. " gems")
	if result.crystals > 0 then
		table.insert(lines, "+" .. result.crystals .. " Trait Crystal" .. (result.crystals == 1 and "" or "s"))
	end
	if result.firstClear then
		table.insert(lines, "First clear bonus!")
	end
	if result.unlocked then
		table.insert(lines, "New map unlocked: " .. result.unlocked)
	end
	Ui.text({
		Text = table.concat(lines, "\n"),
		Size = UDim2.new(1, 0, 0, 150),
		Position = UDim2.fromOffset(0, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxText = 22,
		Parent = endPanel,
	})
	Ui.button("Back to Lobby", C.green, function()
		leaving = true
		Store.call("LeaveBattle")
	end, { Size = UDim2.fromOffset(220, 56), Position = UDim2.new(0.5, 0, 1, -66), AnchorPoint = Vector2.new(0.5, 0), MaxText = 24, Parent = endPanel })
end

local function buildHud()
	gui = Ui.new("ScreenGui", {
		Name = "Battle",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	Ui.new("UIScale", { Name = "Scale", Parent = gui })

	local top = Ui.new("Frame", {
		Size = UDim2.fromOffset(460, 104),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.panelDark,
		BackgroundTransparency = 0.1,
		Parent = gui,
	}, { Ui.corner(12), Ui.stroke(nil, 2) })
	waveLabel = Ui.text({ Text = "", Size = UDim2.new(0.5, -10, 0, 30), Position = UDim2.fromOffset(12, 6), MaxText = 26, Parent = top })
	cashLabel = Ui.text({
		Text = "",
		Size = UDim2.new(0.5, -12, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.gold,
		MaxText = 28,
		Parent = top,
	})
	statusLabel = Ui.text({ Text = "", Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, 40), TextColor3 = C.muted, MaxText = 18, Parent = top })
	local hpBack = Ui.new("Frame", {
		Size = UDim2.new(1, -24, 0, 24),
		Position = UDim2.fromOffset(12, 70),
		BackgroundColor3 = Color3.fromRGB(60, 20, 30),
		Parent = top,
	}, { Ui.corner(8) })
	hpFill = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.green, Parent = hpBack }, { Ui.corner(8) })
	hpLabel = Ui.text({ Text = "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 2, MaxText = 16, Parent = hpBack })

	local controls = Ui.new("Frame", {
		Size = UDim2.fromOffset(160, 150),
		Position = UDim2.new(1, -12, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Vertical, 8) })
	startButton = Ui.button("Start wave", C.green, function()
		Store.call("StartWave")
	end, { Size = UDim2.fromOffset(160, 42), LayoutOrder = 1, Parent = controls })
	speedButton = Ui.button("1x speed", C.blue, function()
		local nextSpeed = (Store.battle.speed % 3) + 1
		Store.call("SetSpeed", nextSpeed)
	end, { Size = UDim2.fromOffset(160, 42), LayoutOrder = 2, Parent = controls })
	local leaveConfirm = false
	local leaveButton
	leaveButton = Ui.button("Leave", C.red, function()
		if Store.battle.state ~= "won" and Store.battle.state ~= "lost" and not leaveConfirm then
			leaveConfirm = true
			leaveButton.Text = "Leave? (counts as loss)"
			task.delay(3, function()
				leaveConfirm = false
				leaveButton.Text = "Leave"
			end)
			return
		end
		leaving = true
		Store.call("LeaveBattle")
	end, { Size = UDim2.fromOffset(160, 42), LayoutOrder = 3, Parent = controls })

	hotbar = Ui.new("Frame", {
		Size = UDim2.fromOffset(6 * 102, 112),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
	Ui.text({
		Text = "Click a unit (or press 1-6), then click the ground. Shift keeps placing. Q / right-click cancels. Click a placed unit to upgrade it.",
		Size = UDim2.fromOffset(700, 18),
		Position = UDim2.new(0.5, 0, 1, -130),
		AnchorPoint = Vector2.new(0.5, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.4,
		MaxText = 14,
		Parent = gui,
	})

	infoPanel = Ui.new("Frame", {
		Size = UDim2.fromOffset(250, 320),
		Position = UDim2.new(1, -12, 0.5, 30),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = C.panel,
		Visible = false,
		Parent = gui,
	}, { Ui.corner(12), Ui.stroke(nil, 2), Ui.padding(10) })

	endPanel = Ui.new("Frame", {
		Size = UDim2.fromOffset(420, 320),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	}, { Ui.corner(16), Ui.stroke(nil, 3), Ui.padding(14) })
end

function BattleUI.start()
	buildHud()
	Store.BattleChanged:Connect(onState)
	Net.ev("BattleEnded").OnClientEvent:Connect(showEnd)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not Store.battle.active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q or input.UserInputType == Enum.UserInputType.MouseButton2 then
			cancelPlacement()
			return
		end
		if processed then
			return
		end
		local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
		local slot = table.find(keys, input.KeyCode)
		if slot then
			if placingSlot == slot then
				cancelPlacement()
			else
				startPlacement(slot)
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if placingSlot then
				tryPlace()
			else
				trySelect()
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		if placingSlot then
			updateGhost()
		end
	end)
	return gui
end

return BattleUI
