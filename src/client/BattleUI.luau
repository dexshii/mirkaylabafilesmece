-- The battle HUD: boss bar, wave counter and countdown ring, castle health, cash, the unit hotbar, placing units,
-- the selected-unit panel (Upgrade T, Sell X, Target R) and the victory/defeat screen.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
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
local Audio = require(script.Parent.Audio)
local Store = require(script.Parent.Store)
local Skins = require(script.Parent.Skins)

local BattleUI = {}

local C = Ui.Colors
local player = Players.LocalPlayer
local gui: ScreenGui

local waveLabel: TextLabel
local timerLabel: TextLabel
local timerRing: Frame
local statusLabel: TextLabel
local cashLabel: TextLabel
local hpFill: Frame
local hpLabel: TextLabel
local bossFrame: Frame
local bossName: TextLabel
local bossFill: Frame
local bossHp: TextLabel
local speedButton: TextButton
local skipButton: TextButton
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
local lastCash = 0

local TARGET_MODES = { "First", "Last", "Strongest", "Closest" }

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
	disc.CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90))
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

local function memberUnit(m): { [string]: any }
	return { l = m.level, g = m.grades }
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
				d.Transparency = 0.35
			end
		end
	end
	model.Parent = workspace
	Skins.apply(model, true)
	ghost = model
	local s = Stats.compute(member.unitId, 0, member.trait, nil, memberUnit(member))
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
	ghost:PivotTo(CFrame.new(pos) * CFrame.Angles(0, math.pi, 0))
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
	local ok, err = Store.call("PlaceUnit", placingSlot, pos)
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

local refreshInfo: () -> ()

local function towerUnit(model: Model): { [string]: any }
	local raw = model:GetAttribute("Grades")
	local grades = string.split(type(raw) == "string" and raw or "A,A,A", ",")
	return { l = model:GetAttribute("UnitLevel") or 1, g = { d = grades[1], s = grades[2], r = grades[3] } }
end

local function upgradeSelected()
	if not selectedTower then
		return
	end
	local ok, err = Store.call("UpgradeTower", selectedTower:GetAttribute("TowerId"))
	if not ok then
		Ui.toast(err or "Can't upgrade", C.red)
	end
	task.wait(0.1)
	refreshInfo()
end

local function sellSelected()
	if not selectedTower then
		return
	end
	if Store.call("SellTower", selectedTower:GetAttribute("TowerId")) then
		Audio.play("coin_spurt", { max = 2 })
	end
	deselect()
end

local function cycleTarget()
	if not selectedTower then
		return
	end
	local current = selectedTower:GetAttribute("Targeting") or "First"
	local nextMode = TARGET_MODES[(table.find(TARGET_MODES, current) or 0) % #TARGET_MODES + 1]
	Store.call("SetTargeting", selectedTower:GetAttribute("TowerId"), nextMode)
	task.wait(0.1)
	refreshInfo()
end

function refreshInfo()
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
	local unit = towerUnit(model)
	local buffs = { damage = model:GetAttribute("DamageBuff") or 0, hitsAir = model:GetAttribute("AirBuff") == true }
	local s = Stats.compute(unitId, level, traitId, buffs, unit)
	local spent = model:GetAttribute("Spent") or 0
	local targeting = model:GetAttribute("Targeting") or "First"
	infoPanel:SetAttribute("Level", level)

	Ui.clear(infoPanel)
	infoPanel.Visible = true
	local color = Rarities.Info[def.rarity].color
	-- header: portrait, name, rarity / trait chips
	local portrait = Ui.new("Frame", {
		Size = UDim2.fromOffset(96, 96),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = infoPanel,
	}, { Ui.corner(12), Ui.stroke(C.ink, 3), Ui.gradient(Ui.RarityGradient[def.rarity][1], Ui.RarityGradient[def.rarity][2]) })
	Ui.viewport(unitId, { Size = UDim2.fromScale(1, 1) }).Parent = portrait
	Ui.text({ Text = "Lvl " .. unit.l, Size = UDim2.fromOffset(60, 18), Position = UDim2.fromOffset(4, 3), MaxText = 15, ZIndex = 3, Parent = portrait })
	Ui.title({ Text = Ui.unitName(unitId), Size = UDim2.new(1, -106, 0, 30), Position = UDim2.fromOffset(106, 0), MaxText = 26, Parent = infoPanel })
	Ui.chip(def.rarity, color, { Size = UDim2.fromOffset(100, 22), Position = UDim2.fromOffset(106, 34), Parent = infoPanel })
	local trait = traitId and Traits.ById[traitId]
	Ui.chip(trait and trait.name or "No trait", trait and Rarities.Info[trait.rarity].color or C.panel, { Size = UDim2.fromOffset(118, 22), Position = UDim2.fromOffset(212, 34), Parent = infoPanel })
	Ui.text({
		Text = string.rep("★", level) .. string.rep("☆", Units.MaxLevel - level),
		Size = UDim2.new(1, -106, 0, 26),
		Position = UDim2.fromOffset(106, 62),
		TextColor3 = C.gold,
		MaxText = 24,
		Parent = infoPanel,
	})

	-- stats
	local rows = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 100), Position = UDim2.fromOffset(0, 104), BackgroundTransparency = 1, Parent = infoPanel }, { Ui.list(Enum.FillDirection.Vertical, 6) })
	if def.attack.kind ~= "none" then
		local top = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = rows }, { Ui.list(Enum.FillDirection.Horizontal, 6) })
		Ui.statChip("DMG", Ui.short(s.damage), unit.g.d, C.red, { Size = UDim2.fromOffset(106, 46), Parent = top })
		Ui.statChip("SPA", string.format("%.2fs", s.cooldown), unit.g.s, C.blue, { Size = UDim2.fromOffset(106, 46), Parent = top })
		Ui.statChip("RNG", string.format("%.1f", s.range), unit.g.r, C.gold, { Size = UDim2.fromOffset(106, 46), Parent = top })
		local extra = {}
		table.insert(extra, (s.hitsGround and "Ground" or "") .. (s.hitsGround and s.hitsAir and " + " or "") .. (s.hitsAir and "Air" or ""))
		if buffs.damage > 0 then
			table.insert(extra, string.format("+%d%% aura", buffs.damage * 100))
		end
		if s.farm > 0 then
			table.insert(extra, string.format("$%d/wave", s.farm))
		end
		Ui.text({ Text = table.concat(extra, "  •  "), Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.muted, MaxText = 15, Parent = rows })
	else
		Ui.statChip("FARM", "$" .. math.floor(s.farm) .. " per wave", nil, C.gold, { Size = UDim2.new(1, 0, 0, 46), Parent = rows })
	end

	-- actions
	if level < Units.MaxLevel then
		local cost = Stats.upgradeCost(unitId, level, traitId)
		local up = Ui.button(string.format("[T] Upgrade %d/%d   $%s", level, Units.MaxLevel, Ui.formatNumber(cost)), Store.battle.cash >= cost and C.green or C.panel, upgradeSelected, {
			Size = UDim2.new(1, 0, 0, 46),
			Position = UDim2.fromOffset(0, 212),
			MaxText = 20,
			Parent = infoPanel,
		})
		up.Name = "Upgrade"
		up:SetAttribute("Cost", cost)
	else
		Ui.button("Upgrade MAXED", C.panel, function() end, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 212), Parent = infoPanel })
	end
	if def.attack.kind ~= "none" then
		Ui.button("[R] Target: " .. targeting, C.blue, cycleTarget, { Size = UDim2.new(0.5, -4, 0, 42), Position = UDim2.fromOffset(0, 264), MaxText = 18, Parent = infoPanel })
	end
	Ui.button("[X] Sell $" .. Ui.formatNumber(math.floor(spent * 0.6)), C.red, sellSelected, {
		Size = UDim2.new(def.attack.kind ~= "none" and 0.5 or 1, def.attack.kind ~= "none" and -4 or 0, 0, 42),
		Position = def.attack.kind ~= "none" and UDim2.new(0.5, 4, 0, 264) or UDim2.fromOffset(0, 264),
		MaxText = 18,
		Parent = infoPanel,
	})

	if selectedRange then
		selectedRange:Destroy()
	end
	local disc = rangeDisc(math.max(s.range, 2), color)
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
	-- rebuild only when the team or what is allowed changes; prices and counts update in place
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
			local holder = Ui.new("Frame", { Name = "Slot" .. i, Size = UDim2.fromOffset(98, 130), BackgroundTransparency = 1, LayoutOrder = i, Parent = hotbar })
			if m then
				local card = Ui.unitCard(holder, { unitId = m.unitId, level = m.level, trait = m.trait, price = m.cost, dim = not m.allowed }, UDim2.fromOffset(98, 112), function()
					if placingSlot == i then
						cancelPlacement()
					else
						startPlacement(i)
					end
				end)
				card.Name = "Card"
				Ui.chip(tostring(i), C.panel, { Size = UDim2.fromOffset(24, 22), Position = UDim2.new(1, -18, 1, -16), ZIndex = 8, Parent = card })
				Ui.text({ Name = "Count", Text = "", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.muted, MaxText = 14, Parent = holder })
			else
				Ui.new("Frame", { Size = UDim2.fromOffset(98, 112), BackgroundColor3 = C.panelDark, BackgroundTransparency = 0.4, Parent = holder }, { Ui.corner(12), Ui.stroke(Color3.fromRGB(90, 76, 160), 2) })
			end
		end
	end
	for i = 1, Units.TeamSize do
		local m = state.team[i]
		local holder = hotbar:FindFirstChild("Slot" .. i)
		if m and holder and holder:FindFirstChild("Count") then
			local def = Units.ById[m.unitId]
			holder.Count.Text = m.allowed and (m.placed .. "/" .. def.limit .. (state.cash < m.cost and "  need $" .. Ui.formatNumber(m.cost - state.cash) or "")) or "not allowed"
			holder.Count.TextColor3 = state.cash >= m.cost and C.muted or Color3.fromRGB(255, 120, 120)
			local stroke = holder.Card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = placingSlot == i and Color3.new(1, 1, 1) or C.ink
				stroke.Thickness = placingSlot == i and 4 or 3
			end
		end
	end
end

local function applyLighting(mapId: string?)
	for _, name in { "SkMapAtmosphere", "SkMapColor", "SkMapBloom", "SkMapSunRays" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local theme
	if not mapId then
		for k, v in defaultLighting do
			(Lighting :: any)[k] = v
		end
		-- the lobby's own look: a soft sunny haze
		theme = {
			atmosphere = { density = 0.25, color = Color3.fromRGB(205, 225, 255), decay = Color3.fromRGB(120, 160, 220), haze = 1.4 },
			saturation = 0.2,
			tint = Color3.fromRGB(255, 250, 240),
		}
	else
		theme = Maps.ById[mapId].theme
	end
	if mapId then
		Lighting.ClockTime = theme.clock
		Lighting.Ambient = theme.ambient
		Lighting.OutdoorAmbient = theme.ambient
		Lighting.FogColor = theme.fog
		Lighting.FogEnd = 100000
	end
	local atmo = Instance.new("Atmosphere")
	atmo.Name = "SkMapAtmosphere"
	atmo.Density = theme.atmosphere.density
	atmo.Color = theme.atmosphere.color
	atmo.Decay = theme.atmosphere.decay
	atmo.Haze = theme.atmosphere.haze
	atmo.Glare = 0.2
	atmo.Offset = 0.1
	atmo.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SkMapColor"
	cc.Saturation = theme.saturation
	cc.Contrast = 0.08
	cc.TintColor = theme.tint
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "SkMapBloom"
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "SkMapSunRays"
	rays.Intensity = 0.06
	rays.Spread = 0.6
	rays.Parent = Lighting
end

local function bumpCash(cash: number)
	if cash > lastCash then
		local box = cashLabel.Parent :: Instance
		local s = box:FindFirstChild("Bump") or Ui.new("UIScale", { Name = "Bump", Parent = box })
		s.Scale = 1.12
		TweenService:Create(s, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	lastCash = cash
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
		lastCash = state.cash
		applyLighting(state.mapId)
	end
	gui.Enabled = true
	waveLabel.Text = string.format("WAVE %d/%d", state.wave, state.waves)
	local showTimer = state.state == "prep" or (state.state == "wave" and not state.lastWave)
	timerRing.Visible = showTimer
	timerLabel.Text = tostring(state.timer) .. "s"
	if state.state == "prep" then
		statusLabel.Text = "Place your units!"
	elseif state.state == "wave" then
		statusLabel.Text = state.enemies .. " enemies" .. (state.lastWave and "  •  FINAL WAVE" or "")
	elseif state.state == "won" then
		statusLabel.Text = "Victory!"
	else
		statusLabel.Text = "Defeat"
	end
	if state.maxUnits then
		statusLabel.Text ..= string.format("  •  units %d/%d", state.units, state.maxUnits)
	end
	cashLabel.Text = "$" .. Ui.formatNumber(state.cash)
	bumpCash(state.cash)
	local hpFrac = math.clamp(state.baseHp / state.maxBaseHp, 0, 1)
	hpFill.Size = UDim2.fromScale(hpFrac, 1)
	hpLabel.Text = state.baseHp .. " / " .. state.maxBaseHp
	speedButton.Text = "⏩ " .. state.speed .. "x"
	skipButton.Visible = state.state == "prep" or state.canSkip
	skipButton.Text = state.state == "prep" and "START" or "SKIP WAVE"

	if state.boss then
		bossFrame.Visible = true
		bossName.Text = Ui.enemyName(state.boss.id, state.boss.name) .. (state.boss.immune and "  🛡" or "")
		bossFill.Size = UDim2.fromScale(math.clamp(state.boss.hp / state.boss.maxHp, 0, 1), 1)
		bossHp.Text = string.format("%s / %s (%d%%)", Ui.short(state.boss.hp), Ui.short(state.boss.maxHp), math.floor(state.boss.hp / state.boss.maxHp * 100 + 0.5))
	else
		bossFrame.Visible = false
	end

	refreshHotbar(state)
	if selectedTower and infoPanel.Visible then
		local level = selectedTower:GetAttribute("Level")
		local up = infoPanel:FindFirstChild("Upgrade")
		if level ~= infoPanel:GetAttribute("Level") then
			refreshInfo()
		elseif up then
			Ui.setButtonColor(up, state.cash >= (up:GetAttribute("Cost") or 0) and C.green or C.panel)
		end
	end
end

local function showEnd(result)
	if leaving then
		return
	end
	cancelPlacement()
	deselect()
	if result.won then
		Audio.music(nil, 0.5)
		Audio.jingle("jingle_victory")
		task.delay(0.6, Audio.play, "voice_yahoo", { gap = 1 })
	else
		Audio.play("voice_mama_mia", { gap = 1 })
	end
	Ui.clear(endPanel)
	endPanel.Visible = true
	Ui.pop(endPanel)
	local won = result.won
	local banner = Ui.title({
		Text = won and "VICTORY!" or "DEFEAT",
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.fromOffset(0, -6),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = won and C.gold or C.red,
		MaxText = 64,
		Outline = 3,
		Parent = endPanel,
	})
	if won then
		Ui.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 170)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 190, 40)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 250, 170)),
			}),
			Rotation = 90,
			Parent = banner,
		})
	end
	Ui.text({
		Text = string.format("Waves cleared: %d / %d%s", won and result.waves or math.max(0, result.wave - 1), result.waves, result.challenge and ("  •  " .. result.challenge) or ""),
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.muted,
		MaxText = 20,
		Parent = endPanel,
	})
	local rewards = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 106), BackgroundTransparency = 1, Parent = endPanel }, { Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	Ui.chip("💎 +" .. result.gems, C.blue, { Size = UDim2.fromOffset(130, 36), Parent = rewards })
	if result.crystals > 0 then
		Ui.chip("🔮 +" .. result.crystals, C.crystal, { Size = UDim2.fromOffset(120, 36), Parent = rewards })
	end
	if (result.xp or 0) > 0 then
		Ui.chip("⭐ +" .. result.xp .. " XP", C.gold, { Size = UDim2.fromOffset(140, 36), Parent = rewards })
	end
	local lines = {}
	if result.firstClear then
		table.insert(lines, "First clear bonus!")
	end
	if result.unlocked then
		table.insert(lines, "New map unlocked: " .. result.unlocked)
	end
	for _, lu in result.levelUps or {} do
		table.insert(lines, Ui.unitName(lu.unitId) .. " reached Lvl " .. lu.level .. "!")
	end
	Ui.text({
		Text = table.concat(lines, "\n"),
		Size = UDim2.new(1, -20, 0, 100),
		Position = UDim2.fromOffset(10, 156),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = C.gold,
		MaxText = 20,
		Parent = endPanel,
	})
	local back = Ui.button("BACK TO LOBBY", C.green, function()
		leaving = true
		Store.call("LeaveBattle")
	end, { Size = UDim2.fromOffset(260, 60), Position = UDim2.new(0.5, 0, 1, -68), AnchorPoint = Vector2.new(0.5, 0), MaxText = 28, Parent = endPanel })
	back.Font = Ui.TitleFont
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

	-- top centre: boss bar (only while a boss is alive) above the wave bar
	local top = Ui.new("Frame", { Size = UDim2.fromOffset(720, 150), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, Parent = gui })
	bossFrame = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Visible = false, Parent = top })
	local skull = Ui.new("Frame", { Size = UDim2.fromOffset(52, 52), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Parent = bossFrame }, { Ui.round(), Ui.stroke(C.ink, 3), Ui.gradient(Color3.fromRGB(255, 90, 90), Color3.fromRGB(140, 10, 30)) })
	Ui.text({ Text = "👑", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 30, Outline = 0, ZIndex = 4, Parent = skull })
	bossName = Ui.title({ Text = "", Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(60, 0), MaxText = 22, Parent = bossFrame })
	bossHp = Ui.text({ Text = "", Size = UDim2.new(0.5, -60, 0, 22), Position = UDim2.new(0.5, 0, 0, 1), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(255, 210, 120), MaxText = 18, Parent = bossFrame })
	local _, fill = Ui.bar(bossFrame, { Size = UDim2.new(1, -60, 0, 20), Position = UDim2.fromOffset(56, 28) }, Color3.fromRGB(255, 140, 30), 1)
	bossFill = fill

	local waveBar = Ui.new("Frame", {
		Size = UDim2.fromOffset(520, 76),
		Position = UDim2.new(0.5, 0, 0, 62),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = top,
	}, { Ui.corner(16), Ui.stroke(C.ink, 3), Ui.gradient(Color3.fromRGB(60, 48, 112), Color3.fromRGB(26, 20, 52)) })
	waveLabel = Ui.title({ Text = "", Size = UDim2.fromOffset(200, 34), Position = UDim2.fromOffset(14, 6), MaxText = 30, Parent = waveBar })
	statusLabel = Ui.text({ Text = "", Size = UDim2.new(1, -110, 0, 20), Position = UDim2.fromOffset(16, 42), TextColor3 = C.muted, MaxText = 16, Parent = waveBar })
	local hpBack = Ui.new("Frame", { Size = UDim2.fromOffset(200, 26), Position = UDim2.fromOffset(222, 10), BackgroundColor3 = Color3.fromRGB(60, 20, 30), Parent = waveBar }, { Ui.round(), Ui.stroke(C.ink, 2) })
	hpFill = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), Parent = hpBack }, { Ui.round(), Ui.gradient(Color3.fromRGB(120, 240, 120), Color3.fromRGB(30, 160, 60)) })
	Ui.icon("heart", "❤️", { Size = UDim2.fromOffset(32, 32), Position = UDim2.new(0, -14, 0.5, -16), MaxText = 20, ZIndex = 3, Parent = hpBack })
	hpLabel = Ui.text({ Text = "", Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 2), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 16, ZIndex = 2, Parent = hpBack })
	-- the countdown ring to the next wave
	timerRing = Ui.new("Frame", {
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.new(1, -72, 0, 6),
		BackgroundColor3 = Color3.fromRGB(30, 24, 60),
		Parent = waveBar,
	}, { Ui.round() })
	local ringStroke = Ui.new("UIStroke", { Thickness = 5, Color = Color3.new(1, 1, 1), Parent = timerRing })
	Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 120, 255)), Parent = ringStroke })
	timerLabel = Ui.title({ Text = "", Size = UDim2.new(1, -10, 1, -16), Position = UDim2.fromOffset(5, 8), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 26, Parent = timerRing })

	-- right: skip / speed / leave
	local controls = Ui.new("Frame", {
		Size = UDim2.fromOffset(170, 170),
		Position = UDim2.new(1, -14, 0, 14),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right) })
	skipButton = Ui.button("SKIP WAVE", C.green, function()
		Store.call("StartWave")
	end, { Size = UDim2.fromOffset(170, 48), LayoutOrder = 1, MaxText = 22, Parent = controls })
	skipButton.Font = Ui.TitleFont
	speedButton = Ui.button("⏩ 1x", C.blue, function()
		Store.call("SetSpeed", (Store.battle.speed % 3) + 1)
	end, { Size = UDim2.fromOffset(170, 44), LayoutOrder = 2, Parent = controls })
	local leaveConfirm = false
	local leaveButton
	leaveButton = Ui.button("Leave", C.red, function()
		if Store.battle.state ~= "won" and Store.battle.state ~= "lost" and not leaveConfirm then
			leaveConfirm = true
			leaveButton.Text = "Leave? (= loss)"
			task.delay(3, function()
				leaveConfirm = false
				leaveButton.Text = "Leave"
			end)
			return
		end
		leaving = true
		Store.call("LeaveBattle")
	end, { Size = UDim2.fromOffset(170, 40), LayoutOrder = 3, Parent = controls })

	-- bottom: cash above the hotbar
	local cashBox = Ui.new("Frame", { Size = UDim2.fromOffset(300, 54), Position = UDim2.new(0.5, 0, 1, -158), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Parent = gui })
	Ui.icon("coin", "🪙", { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(24, 1), MaxText = 40, Parent = cashBox })
	cashLabel = Ui.title({ Text = "", Size = UDim2.fromOffset(220, 50), Position = UDim2.fromOffset(80, 2), TextColor3 = Color3.fromRGB(255, 225, 90), MaxText = 44, Outline = 3, Parent = cashBox })

	hotbar = Ui.new("Frame", {
		Size = UDim2.fromOffset(6 * 104, 130),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
	Ui.text({
		Text = "Click a unit or press 1-6, then click the ground  •  Shift keeps placing  •  Q cancels  •  click a placed unit to upgrade",
		Size = UDim2.fromOffset(820, 18),
		Position = UDim2.new(0.5, 0, 1, -210),
		AnchorPoint = Vector2.new(0.5, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxText = 14,
		Parent = gui,
	})

	infoPanel = Ui.new("Frame", {
		Size = UDim2.fromOffset(356, 320),
		Position = UDim2.new(0, 14, 0.5, 10),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		Parent = gui,
	}, { Ui.corner(16), Ui.stroke(C.ink, 3), Ui.padding(12), Ui.gradient(C.bgTop, C.bgBottom) })

	endPanel = Ui.new("Frame", {
		Size = UDim2.fromOffset(520, 360),
		Position = UDim2.fromScale(0.5, 0.48),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		ZIndex = 5,
		Parent = gui,
	}, { Ui.corner(20), Ui.padding(16), Ui.gradient(C.bgTop, C.bgBottom) })
	local border = Ui.new("UIStroke", { Thickness = 5, Color = Color3.new(1, 1, 1), Parent = endPanel })
	Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 230, 110), Color3.fromRGB(240, 150, 30)), Rotation = 45, Parent = border })
end

function BattleUI.start()
	buildHud()
	applyLighting(nil)
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
		if selectedTower and infoPanel.Visible then
			if input.KeyCode == Enum.KeyCode.T then
				task.spawn(upgradeSelected)
				return
			elseif input.KeyCode == Enum.KeyCode.X then
				task.spawn(sellSelected)
				return
			elseif input.KeyCode == Enum.KeyCode.R then
				task.spawn(cycleTarget)
				return
			end
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
