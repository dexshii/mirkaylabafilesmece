-- Lobby screens: currencies, team bar, and the Play / Summon / Units / Traits / Challenges windows.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Units = require(Shared.Units)
local Traits = require(Shared.Traits)
local Rarities = require(Shared.Rarities)
local Maps = require(Shared.Maps)
local Enemies = require(Shared.Enemies)
local Challenges = require(Shared.Challenges)
local Stats = require(Shared.Stats)

local Ui = require(script.Parent.Ui)
local Store = require(script.Parent.Store)

local LobbyUI = {}

local C = Ui.Colors
local gui: ScreenGui
local windows: { [string]: Frame } = {}
local refreshers: { [string]: () -> () } = {}
local openName: string? = nil

local selectedMap = "meadow"
local selectedStage = 1
local selectedUnit: string? = nil -- uid in the Units window
local traitUnit: string? = nil -- uid in the Traits window
local equipMode = false
local rolling = false -- the trait roll animation is playing: hold Traits window refreshes

local function rarityColor(rarity: string): Color3
	return Rarities.Info[rarity].color
end

local function sortedUnits(data): { { uid: string, u: string, t: string? } }
	local list = {}
	for uid, entry in data.units do
		table.insert(list, { uid = uid, u = entry.u, t = entry.t })
	end
	table.sort(list, function(a, b)
		local ra = Rarities.Info[Units.ById[a.u].rarity].rank
		local rb = Rarities.Info[Units.ById[b.u].rarity].rank
		if ra ~= rb then
			return ra > rb
		end
		if a.u ~= b.u then
			return Units.ById[a.u].name < Units.ById[b.u].name
		end
		return tonumber(a.uid) < tonumber(b.uid)
	end)
	return list
end

local function onTeam(data, uid: string): number?
	return table.find(data.team, uid)
end

local function mapUnlocked(data, index: number): boolean
	return index == 1 or (data.progress[Maps.List[index - 1].id] or 0) >= Maps.Stages
end

local function open(name: string?)
	for n, w in windows do
		w.Visible = n == name
	end
	openName = name
	if name and refreshers[name] then
		refreshers[name]()
	end
end
LobbyUI.open = open

-- a unit card: viewport, name, rarity border, trait tag
local function unitCard(parent: Instance, entry, size: UDim2, onClick: () -> (), highlight: boolean?): TextButton
	local def = Units.ById[entry.u]
	local color = rarityColor(def.rarity)
	local card = Ui.new("TextButton", {
		Text = "",
		AutoButtonColor = true,
		Size = size,
		BackgroundColor3 = C.card,
		Parent = parent,
	}, { Ui.corner(10), Ui.stroke(highlight and Color3.new(1, 1, 1) or color, highlight and 4 or 3) })
	Ui.viewport(def.id, {
		Size = UDim2.new(1, -8, 1, -30),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.55),
		Parent = card,
	})
	Ui.text({
		Text = def.name,
		Size = UDim2.new(1, -8, 0, 20),
		Position = UDim2.new(0, 4, 1, -24),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxText = 16,
		Parent = card,
	})
	if entry.t then
		local trait = Traits.ById[entry.t]
		if trait then
			Ui.text({
				Text = trait.name,
				Size = UDim2.new(1, -8, 0, 16),
				Position = UDim2.fromOffset(4, 4),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = rarityColor(trait.rarity),
				TextStrokeTransparency = 0.3,
				MaxText = 13,
				ZIndex = 3,
				Parent = card,
			})
		end
	end
	card.Activated:Connect(onClick)
	return card
end

-- ============================================================ top bar and team bar

local gemsLabel: TextLabel
local crystalsLabel: TextLabel
local teamBar: Frame

local function buildTopBar()
	local bar = Ui.new("Frame", {
		Size = UDim2.fromOffset(380, 44),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.panelDark,
		BackgroundTransparency = 0.15,
		Parent = gui,
	}, { Ui.corner(12), Ui.stroke(nil, 2), Ui.padding(6), Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	Ui.gemIcon(C.gem, 30, bar)
	gemsLabel = Ui.text({ Text = "0", Size = UDim2.fromOffset(120, 30), MaxText = 24, Parent = bar })
	Ui.gemIcon(C.crystal, 30, bar)
	crystalsLabel = Ui.text({ Text = "0 crystals", Size = UDim2.fromOffset(170, 30), MaxText = 24, Parent = bar })
end

local function buildMenu()
	local menu = Ui.new("Frame", {
		Size = UDim2.fromOffset(170, 300),
		Position = UDim2.new(0, 14, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Vertical, 10) })
	local entries = {
		{ "PLAY", C.green, "Play" },
		{ "SUMMON", C.gold, "Summon" },
		{ "UNITS", C.blue, "Units" },
		{ "TRAITS", C.purple, "Traits" },
		{ "CHALLENGES", C.red, "Challenges" },
	}
	for i, e in entries do
		Ui.button(e[1], e[2], function()
			open(openName ~= e[3] and e[3] or nil)
		end, { Size = UDim2.fromOffset(170, 50), LayoutOrder = i, MaxText = 26, Parent = menu })
	end
end

local function refreshTeamBar()
	local data = Store.data
	Ui.clear(teamBar)
	for i = 1, Units.TeamSize do
		local uid = data.team[i]
		local entry = uid ~= "" and data.units[uid]
		if entry then
			unitCard(teamBar, { uid = uid, u = entry.u, t = entry.t }, UDim2.fromOffset(90, 100), function()
				selectedUnit = uid
				open("Units")
			end)
		else
			local slot = Ui.button("+", C.card, function()
				open("Units")
			end, { Size = UDim2.fromOffset(90, 100), MaxText = 40, Parent = teamBar })
			slot.TextColor3 = C.muted
		end
	end
end

local function buildTeamBar()
	teamBar = Ui.new("Frame", {
		Size = UDim2.fromOffset(6 * 96, 104),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center) })
end

-- ============================================================ Play

local function buildPlay()
	local window, content = Ui.window(gui, "Campaign", UDim2.fromOffset(820, 500), function()
		open(nil)
	end)
	windows.Play = window
	local mapList = Ui.new("ScrollingFrame", {
		Size = UDim2.new(0, 250, 1, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 8) })
	local detail = Ui.new("Frame", {
		Size = UDim2.new(1, -266, 1, 0),
		Position = UDim2.fromOffset(266, 0),
		BackgroundColor3 = C.panelDark,
		Parent = content,
	}, { Ui.corner(12), Ui.padding(14) })

	refreshers.Play = function()
		local data = Store.data
		Ui.clear(mapList)
		for i, def in Maps.List do
			local unlocked = mapUnlocked(data, i)
			local cleared = data.progress[def.id] or 0
			local label = (unlocked and "" or "LOCKED  ") .. def.name .. "\n" .. cleared .. "/" .. Maps.Stages .. " stages"
			local b = Ui.button(label, def.id == selectedMap and C.blue or C.card, function()
				selectedMap = def.id
				selectedStage = math.min((data.progress[def.id] or 0) + 1, Maps.Stages)
				refreshers.Play()
			end, { Size = UDim2.new(1, -8, 0, 64), LayoutOrder = i, MaxText = 20, Parent = mapList })
			b.TextXAlignment = Enum.TextXAlignment.Left
			if not unlocked then
				b.TextColor3 = C.muted
			end
		end

		Ui.clear(detail)
		local def = Maps.ById[selectedMap]
		local index = Maps.Index[selectedMap]
		local unlocked = mapUnlocked(data, index)
		local cleared = data.progress[def.id] or 0
		Ui.text({ Text = def.name, Size = UDim2.new(1, 0, 0, 36), MaxText = 30, Parent = detail })
		Ui.text({ Text = def.desc, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 40), TextColor3 = C.muted, MaxText = 18, Parent = detail })
		local boss = Enemies.ById[def.boss]
		Ui.text({
			Text = "Boss (stage 5): " .. boss.name .. ". " .. boss.desc,
			Size = UDim2.new(1, -110, 0, 44),
			Position = UDim2.fromOffset(0, 70),
			TextColor3 = Color3.fromRGB(255, 160, 220),
			TextWrapped = true,
			MaxText = 17,
			Parent = detail,
		})
		Ui.viewport(def.boss, { Size = UDim2.fromOffset(100, 100), Position = UDim2.new(1, -100, 0, 40), Parent = detail })

		local enemyRow = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 70),
			Position = UDim2.fromOffset(0, 150),
			BackgroundTransparency = 1,
			Parent = detail,
		}, { Ui.list(Enum.FillDirection.Horizontal, 6) })
		local shown = {}
		for _, id in def.ground do
			table.insert(shown, id)
		end
		for _, id in def.flying do
			table.insert(shown, id)
		end
		for _, id in shown do
			local holder = Ui.new("Frame", { Size = UDim2.fromOffset(70, 70), BackgroundTransparency = 1, Parent = enemyRow })
			Ui.viewport(id, { Size = UDim2.fromOffset(70, 54), Parent = holder })
			Ui.text({
				Text = (Enemies.ById[id].kind == "flying" and "Air: " or "") .. Enemies.ById[id].name,
				Size = UDim2.new(1, 0, 0, 16),
				Position = UDim2.fromOffset(0, 54),
				TextXAlignment = Enum.TextXAlignment.Center,
				MaxText = 12,
				Parent = holder,
			})
		end

		local stageRow = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 60),
			Position = UDim2.fromOffset(0, 240),
			BackgroundTransparency = 1,
			Parent = detail,
		}, { Ui.list(Enum.FillDirection.Horizontal, 8) })
		for s = 1, Maps.Stages do
			local available = unlocked and cleared >= s - 1
			local text = "Stage " .. s .. (cleared >= s and "\nCLEARED" or (s == Maps.Stages and "\nBOSS" or ""))
			local color = s == selectedStage and C.gold or (cleared >= s and C.green or C.card)
			local b = Ui.button(text, color, function()
				if available then
					selectedStage = s
					refreshers.Play()
				end
			end, { Size = UDim2.fromOffset(96, 56), MaxText = 16, Parent = stageRow })
			if not available then
				b.TextColor3 = C.muted
			end
		end

		local waves = 6 + 2 * selectedStage
		Ui.text({
			Text = "Stage " .. selectedStage .. ": " .. waves .. " waves. First clear: gems and a Trait Crystal" .. (selectedStage == Maps.Stages and " (3 crystals for the boss)" or ""),
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 312),
			TextWrapped = true,
			TextColor3 = C.muted,
			MaxText = 17,
			Parent = detail,
		})
		local canStart = unlocked and cleared >= selectedStage - 1
		Ui.button(canStart and "START" or "LOCKED", canStart and C.green or C.card, function()
			if not canStart then
				return
			end
			local ok, err = Store.call("StartBattle", "campaign", selectedMap, selectedStage)
			if ok then
				open(nil)
			else
				Ui.toast(err or "Could not start", C.red)
			end
		end, { Size = UDim2.fromOffset(200, 56), Position = UDim2.new(1, -200, 1, -56), MaxText = 28, Parent = detail })
	end
end

-- ============================================================ Summon

local resultOverlay: Frame

local function showSummonResults(results)
	Ui.clear(resultOverlay)
	resultOverlay.Visible = true
	local grid = Ui.new("Frame", {
		Size = UDim2.fromOffset(5 * 136, 2 * 166),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = resultOverlay,
	})
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(126, 156),
		CellPadding = UDim2.fromOffset(10, 10),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local best = 1
	for i, r in results do
		best = math.max(best, Rarities.Info[r.rarity].rank)
		local holder = Ui.new("Frame", { LayoutOrder = i, BackgroundTransparency = 1, Parent = grid })
		local card = unitCard(holder, { uid = r.uid, u = r.unitId }, UDim2.fromScale(1, 1), function() end)
		card.Visible = false
		Ui.text({
			Text = r.rarity,
			Size = UDim2.new(1, -8, 0, 18),
			Position = UDim2.fromOffset(4, 4),
			TextColor3 = rarityColor(r.rarity),
			TextStrokeTransparency = 0.2,
			MaxText = 15,
			ZIndex = 3,
			Parent = card,
		})
		task.delay(0.12 * i, function()
			card.Visible = true
			card.Size = UDim2.fromScale(0.2, 0.2)
			card.Position = UDim2.fromScale(0.4, 0.4)
			TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0) }):Play()
		end)
	end
	local banner = ({ "Nice!", "Rare pull!", "LEGENDARY!", "MYTHIC!!!" })[best]
	Ui.text({
		Text = banner,
		Size = UDim2.fromOffset(600, 60),
		Position = UDim2.new(0.5, 0, 0.45, -230),
		AnchorPoint = Vector2.new(0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Rarities.Info[Rarities.Order[best]].color,
		TextStrokeTransparency = 0,
		MaxText = 54,
		Parent = resultOverlay,
	})
	Ui.button("OK", C.green, function()
		resultOverlay.Visible = false
	end, { Size = UDim2.fromOffset(180, 50), Position = UDim2.new(0.5, 0, 0.45, 200), AnchorPoint = Vector2.new(0.5, 0), MaxText = 26, Parent = resultOverlay })
end

local function buildSummon()
	local window, content = Ui.window(gui, "Summon", UDim2.fromOffset(820, 500), function()
		open(nil)
	end)
	windows.Summon = window
	resultOverlay = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})

	refreshers.Summon = function()
		local data = Store.data
		Ui.clear(content)
		Ui.text({ Text = "Star Banner", Size = UDim2.new(1, 0, 0, 34), MaxText = 30, TextColor3 = C.gold, Parent = content })
		-- the four mythic and legendary units on display
		local row = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 170),
			Position = UDim2.fromOffset(0, 40),
			BackgroundTransparency = 1,
			Parent = content,
		}, { Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
		local featured = {}
		for _, r in { "Mythic", "Legendary" } do
			for _, def in Units.ByRarity[r] do
				table.insert(featured, def)
			end
		end
		for _, def in featured do
			local holder = Ui.new("Frame", { Size = UDim2.fromOffset(118, 170), BackgroundTransparency = 1, Parent = row })
			Ui.viewport(def.id, {
				Size = UDim2.fromOffset(118, 130),
				BackgroundColor3 = rarityColor(def.rarity):Lerp(Color3.new(0, 0, 0), 0.5),
				Parent = holder,
			})
			Ui.text({ Text = def.name, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 132), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 14, Parent = holder })
			Ui.text({
				Text = def.rarity,
				Size = UDim2.new(1, 0, 0, 16),
				Position = UDim2.fromOffset(0, 150),
				TextXAlignment = Enum.TextXAlignment.Center,
				TextColor3 = rarityColor(def.rarity),
				MaxText = 13,
				Parent = holder,
			})
		end
		local rates = {}
		for _, r in Rarities.Order do
			table.insert(rates, string.format('<font color="#%s">%s %s%%</font>', rarityColor(r):ToHex(), r, tostring(Rarities.SummonRates[r])))
		end
		Ui.text({
			Text = table.concat(rates, "   "),
			RichText = true,
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 222),
			TextXAlignment = Enum.TextXAlignment.Center,
			MaxText = 20,
			Parent = content,
		})
		Ui.text({
			Text = string.format(
				"Legendary or better guaranteed in %d summons  |  Mythic guaranteed in %d",
				Rarities.LegendaryPity - data.pity.legendary,
				Rarities.MythicPity - data.pity.mythic
			),
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, 254),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.muted,
			MaxText = 17,
			Parent = content,
		})
		local function summon(count: number)
			local ok, results = Store.call("Summon", count)
			if ok then
				showSummonResults(results)
			else
				Ui.toast(results or "Summon failed", C.red)
			end
		end
		Ui.button("Summon x1\n50 gems", C.blue, function()
			summon(1)
		end, { Size = UDim2.fromOffset(220, 70), Position = UDim2.new(0.5, -240, 0, 300), MaxText = 24, Parent = content })
		Ui.button("Summon x10\n450 gems", C.gold, function()
			summon(10)
		end, { Size = UDim2.fromOffset(220, 70), Position = UDim2.new(0.5, 20, 0, 300), MaxText = 24, Parent = content })
		Ui.text({
			Text = "Earn gems by clearing campaign stages and challenges. New units fill empty team slots automatically.",
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 388),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.muted,
			MaxText = 16,
			Parent = content,
		})
	end
end

-- ============================================================ Units

local function statLines(unitId: string, traitId: string?): string
	local def = Units.ById[unitId]
	local s = Stats.compute(unitId, 0, traitId, nil)
	local lines = {
		def.role,
		string.format("Cost $%d   Limit %d", Stats.placeCost(unitId, traitId), def.limit),
	}
	if def.attack.kind ~= "none" then
		table.insert(lines, string.format("Damage %.0f   Range %.0f   Every %.2fs", s.damage, s.range, s.cooldown))
		local targets = {}
		if s.hitsGround then
			table.insert(targets, "Ground")
		end
		if s.hitsAir then
			table.insert(targets, "Air")
		end
		table.insert(lines, "Hits: " .. table.concat(targets, " + "))
	end
	if s.farm > 0 then
		table.insert(lines, string.format("Pays $%d per wave", s.farm))
	end
	return table.concat(lines, "\n")
end

local function buildUnits()
	local window, content = Ui.window(gui, "Units", UDim2.fromOffset(900, 540), function()
		open(nil)
	end)
	windows.Units = window
	local grid = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, -320, 1, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, {
		Ui.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(100, 118),
			CellPadding = UDim2.fromOffset(8, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Ui.padding(4),
	})
	local detail = Ui.new("Frame", {
		Size = UDim2.new(0, 308, 1, 0),
		Position = UDim2.new(1, -308, 0, 0),
		BackgroundColor3 = C.panelDark,
		Parent = content,
	}, { Ui.corner(12), Ui.padding(12) })

	refreshers.Units = function()
		local data = Store.data
		local list = sortedUnits(data)
		if selectedUnit and not data.units[selectedUnit] then
			selectedUnit = nil
		end
		if not selectedUnit and list[1] then
			selectedUnit = list[1].uid
		end
		Ui.clear(grid)
		for i, entry in list do
			local slot = onTeam(data, entry.uid)
			local card = unitCard(grid, entry, UDim2.new(), function()
				selectedUnit = entry.uid
				equipMode = false
				refreshers.Units()
			end, entry.uid == selectedUnit)
			card.LayoutOrder = i
			if slot then
				Ui.text({
					Text = "TEAM " .. slot,
					Size = UDim2.new(1, -8, 0, 16),
					Position = UDim2.new(0, 4, 1, -42),
					TextColor3 = C.green,
					TextStrokeTransparency = 0.2,
					MaxText = 13,
					ZIndex = 3,
					Parent = card,
				})
			end
		end

		Ui.clear(detail)
		if not selectedUnit then
			return
		end
		local entry = data.units[selectedUnit]
		local def = Units.ById[entry.u]
		Ui.viewport(def.id, { Size = UDim2.new(1, 0, 0, 140), BackgroundColor3 = rarityColor(def.rarity):Lerp(Color3.new(0, 0, 0), 0.5), Parent = detail })
		Ui.text({ Text = def.name, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 146), MaxText = 26, Parent = detail })
		Ui.text({ Text = def.rarity, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 174), TextColor3 = rarityColor(def.rarity), MaxText = 18, Parent = detail })
		Ui.text({
			Text = def.desc,
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 196),
			TextWrapped = true,
			TextColor3 = C.muted,
			MaxText = 14,
			Parent = detail,
		})
		Ui.text({
			Text = statLines(entry.u, entry.t),
			Size = UDim2.new(1, 0, 0, 74),
			Position = UDim2.fromOffset(0, 238),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			MaxText = 15,
			Parent = detail,
		})
		local trait = entry.t and Traits.ById[entry.t]
		Ui.text({
			Text = trait and ("Trait: " .. trait.name .. " (" .. trait.desc .. ")") or "Trait: none",
			Size = UDim2.new(1, 0, 0, 34),
			Position = UDim2.fromOffset(0, 314),
			TextWrapped = true,
			TextColor3 = trait and rarityColor(trait.rarity) or C.muted,
			MaxText = 15,
			Parent = detail,
		})

		local buttons = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 96),
			Position = UDim2.new(0, 0, 1, -96),
			BackgroundTransparency = 1,
			Parent = detail,
		})
		if equipMode then
			Ui.text({ Text = "Pick a team slot:", Size = UDim2.new(1, 0, 0, 20), MaxText = 16, Parent = buttons })
			for i = 1, Units.TeamSize do
				local current = data.team[i]
				local label = tostring(i)
				if current ~= "" and data.units[current] then
					label = i .. "\n" .. Units.ById[data.units[current].u].name
				end
				Ui.button(label, current == selectedUnit and C.green or C.card, function()
					local ok, err = Store.call("EquipUnit", i, selectedUnit)
					if not ok then
						Ui.toast(err or "Could not equip", C.red)
					end
					equipMode = false
					refreshers.Units()
				end, { Size = UDim2.fromOffset(44, 66), Position = UDim2.fromOffset((i - 1) * 48, 26), MaxText = 12, Parent = buttons })
			end
			return
		end
		local slot = onTeam(data, selectedUnit)
		if slot then
			Ui.button("Unequip", C.card, function()
				Store.call("EquipUnit", slot, "")
			end, { Size = UDim2.new(0.5, -4, 0, 44), Parent = buttons })
		else
			Ui.button("Equip", C.green, function()
				equipMode = true
				refreshers.Units()
			end, { Size = UDim2.new(0.5, -4, 0, 44), Parent = buttons })
		end
		Ui.button("Traits", C.purple, function()
			traitUnit = selectedUnit
			open("Traits")
		end, { Size = UDim2.new(0.5, -4, 0, 44), Position = UDim2.new(0.5, 4, 0, 0), Parent = buttons })
		local releaseGems = Rarities.Info[def.rarity].releaseGems
		local confirming = false
		local release
		release = Ui.button("Release (+" .. releaseGems .. " gems)", C.red, function()
			if not confirming then
				confirming = true
				release.Text = "Tap again to release"
				task.delay(3, function()
					confirming = false
					if release.Parent then
						release.Text = "Release (+" .. releaseGems .. " gems)"
					end
				end)
				return
			end
			local ok, err = Store.call("ReleaseUnit", selectedUnit)
			if ok then
				selectedUnit = nil
			else
				Ui.toast(err or "Could not release", C.red)
			end
		end, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 52), MaxText = 18, Parent = buttons })
	end
end

-- ============================================================ Traits

local function buildTraits()
	local window, content = Ui.window(gui, "Traits", UDim2.fromOffset(900, 540), function()
		open(nil)
	end)
	windows.Traits = window
	local picker = Ui.new("ScrollingFrame", {
		Size = UDim2.new(0, 230, 1, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 6), Ui.padding(4) })
	local roller = Ui.new("Frame", {
		Size = UDim2.new(0, 280, 1, 0),
		Position = UDim2.fromOffset(240, 0),
		BackgroundColor3 = C.panelDark,
		Parent = content,
	}, { Ui.corner(12), Ui.padding(12) })
	local index = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, -534, 1, 0),
		Position = UDim2.fromOffset(534, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 4), Ui.padding(4) })

	-- the trait index never changes
	local order = 0
	for i = #Rarities.Order, 1, -1 do
		local r = Rarities.Order[i]
		order += 1
		Ui.text({
			Text = string.format("%s  (%s%%)", r, tostring(Rarities.TraitRates[r])),
			Size = UDim2.new(1, -8, 0, 24),
			TextColor3 = rarityColor(r),
			LayoutOrder = order,
			MaxText = 20,
			Parent = index,
		})
		for _, t in Traits.ByRarity[r] do
			order += 1
			Ui.text({
				Text = "  " .. t.name .. ": " .. t.desc,
				Size = UDim2.new(1, -8, 0, 32),
				TextWrapped = true,
				TextColor3 = C.muted,
				LayoutOrder = order,
				MaxText = 14,
				Parent = index,
			})
		end
	end

	refreshers.Traits = function()
		local data = Store.data
		local list = sortedUnits(data)
		if traitUnit and not data.units[traitUnit] then
			traitUnit = nil
		end
		if not traitUnit and list[1] then
			traitUnit = list[1].uid
		end
		Ui.clear(picker)
		for i, entry in list do
			local def = Units.ById[entry.u]
			local trait = entry.t and Traits.ById[entry.t]
			local b = Ui.button(def.name .. (trait and ("\n" .. trait.name) or "\nno trait"), entry.uid == traitUnit and C.blue or C.card, function()
				traitUnit = entry.uid
				refreshers.Traits()
			end, { Size = UDim2.new(1, -8, 0, 48), LayoutOrder = i, MaxText = 15, Parent = picker })
			b.TextXAlignment = Enum.TextXAlignment.Left
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = rarityColor(def.rarity)
			end
		end

		Ui.clear(roller)
		if not traitUnit then
			return
		end
		local entry = data.units[traitUnit]
		local def = Units.ById[entry.u]
		Ui.viewport(def.id, { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = rarityColor(def.rarity):Lerp(Color3.new(0, 0, 0), 0.5), Parent = roller })
		Ui.text({ Text = def.name, Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 156), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 24, Parent = roller })
		local trait = entry.t and Traits.ById[entry.t]
		local current = Ui.text({
			Text = trait and trait.name or "No trait",
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 196),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = trait and rarityColor(trait.rarity) or C.muted,
			TextStrokeTransparency = 0.3,
			MaxText = 34,
			Parent = roller,
		})
		Ui.text({
			Text = trait and (trait.rarity .. ": " .. trait.desc) or "Roll to give this unit a trait.",
			Size = UDim2.new(1, 0, 0, 44),
			Position = UDim2.fromOffset(0, 238),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.muted,
			MaxText = 16,
			Parent = roller,
		})
		Ui.text({
			Text = "You have " .. data.crystals .. " Trait Crystal" .. (data.crystals == 1 and "" or "s"),
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.new(0, 0, 1, -98),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.crystal,
			MaxText = 17,
			Parent = roller,
		})
		local confirming = false
		local rollButton
		rollButton = Ui.button("Roll Trait (" .. Traits.RollCost .. " crystal)", C.purple, function()
			-- rolling replaces the current trait: confirm before throwing away a Legendary or Mythic one
			if trait and Rarities.Info[trait.rarity].rank >= 3 and not confirming then
				confirming = true
				rollButton.Text = "Replace " .. trait.name .. "? Tap again"
				task.delay(3, function()
					confirming = false
				end)
				return
			end
			rolling = true
			local ok, result = Store.call("RollTrait", traitUnit)
			if not ok then
				rolling = false
				Ui.toast(result or "Could not roll", C.red)
				return
			end
			local rolled = Traits.ById[result]
			-- a quick spin through random trait names before the result
			for i = 1, 10 do
				local t = Traits.List[math.random(1, #Traits.List)]
				current.Text = t.name
				current.TextColor3 = rarityColor(t.rarity)
				task.wait(0.04 + i * 0.012)
			end
			current.Text = rolled.name
			current.TextColor3 = rarityColor(rolled.rarity)
			Ui.toast("Rolled " .. rolled.rarity .. " trait: " .. rolled.name .. "!", rarityColor(rolled.rarity):Lerp(Color3.new(0, 0, 0), 0.4))
			task.wait(0.6)
			rolling = false
			if openName == "Traits" then
				refreshers.Traits()
			end
		end, { Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 1, -66), MaxText = 20, Parent = roller })
	end
end

-- ============================================================ Challenges

local function buildChallenges()
	local window, content = Ui.window(gui, "Challenges", UDim2.fromOffset(820, 520), function()
		open(nil)
	end)
	windows.Challenges = window
	local list = Ui.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 8), Ui.padding(4) })

	refreshers.Challenges = function()
		local data = Store.data
		Ui.clear(list)
		Ui.text({
			Text = "Challenges reward Trait Crystals once per day each (reset at 00:00 UTC). Replays pay a few gems.",
			Size = UDim2.new(1, -8, 0, 24),
			TextColor3 = C.muted,
			LayoutOrder = 0,
			MaxText = 16,
			Parent = list,
		})
		for i, ch in Challenges.List do
			local map = Maps.ById[ch.map]
			local unlocked = mapUnlocked(data, Maps.Index[ch.map]) and (data.progress[ch.map] or 0) >= 1
			local doneToday = data.challenges[ch.id] == Challenges.today()
			local row = Ui.new("Frame", {
				Size = UDim2.new(1, -8, 0, 84),
				BackgroundColor3 = C.card,
				LayoutOrder = i,
				Parent = list,
			}, { Ui.corner(10), Ui.stroke(nil, 2) })
			Ui.text({ Text = ch.name, Size = UDim2.new(0.5, 0, 0, 28), Position = UDim2.fromOffset(12, 6), MaxText = 22, Parent = row })
			Ui.text({
				Text = map.name .. ", stage " .. ch.stage .. ": " .. ch.desc,
				Size = UDim2.new(1, -240, 0, 40),
				Position = UDim2.fromOffset(12, 36),
				TextWrapped = true,
				TextColor3 = C.muted,
				MaxText = 15,
				Parent = row,
			})
			local reward = doneToday and ("Done today. Replay: " .. ch.repeatGems .. " gems") or (ch.crystals .. " crystals + " .. ch.gems .. " gems")
			Ui.text({
				Text = reward,
				Size = UDim2.new(0, 220, 0, 26),
				Position = UDim2.new(1, -230, 0, 8),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = doneToday and C.muted or C.crystal,
				MaxText = 16,
				Parent = row,
			})
			Ui.button(unlocked and "START" or "LOCKED", unlocked and C.green or C.panelDark, function()
				if not unlocked then
					Ui.toast("Clear stage 1 of " .. map.name .. " first", C.red)
					return
				end
				local ok, err = Store.call("StartBattle", "challenge", ch.id)
				if ok then
					open(nil)
				else
					Ui.toast(err or "Could not start", C.red)
				end
			end, { Size = UDim2.fromOffset(130, 38), Position = UDim2.new(1, -140, 0, 38), Parent = row })
		end
	end
end

-- ============================================================ lifecycle

local function refreshAll()
	local data = Store.data
	if not data then
		return
	end
	gemsLabel.Text = Ui.formatNumber(data.gems)
	crystalsLabel.Text = Ui.formatNumber(data.crystals) .. " crystals"
	refreshTeamBar()
	if openName and refreshers[openName] and not (openName == "Traits" and rolling) then
		refreshers[openName]()
	end
end

function LobbyUI.setVisible(visible: boolean)
	gui.Enabled = visible
	if not visible then
		open(nil)
		resultOverlay.Visible = false
	end
end

function LobbyUI.start()
	gui = Ui.new("ScreenGui", {
		Name = "Lobby",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	Ui.new("UIScale", { Parent = gui }).Name = "Scale"
	buildTopBar()
	buildMenu()
	buildTeamBar()
	buildPlay()
	buildSummon()
	buildUnits()
	buildTraits()
	buildChallenges()
	Store.DataChanged:Connect(refreshAll)
	refreshAll()
	return gui
end

return LobbyUI
