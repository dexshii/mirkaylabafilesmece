-- Lobby screens: menu tiles, currencies, the team tray and the Play / Summon / Units / Traits / Challenges windows,
-- the summon animation is in SummonFx.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game.ReplicatedStorage.Shared
local Units = require(Shared.Units)
local Traits = require(Shared.Traits)
local Rarities = require(Shared.Rarities)
local Maps = require(Shared.Maps)
local Enemies = require(Shared.Enemies)
local Challenges = require(Shared.Challenges)
local Stats = require(Shared.Stats)
local Progression = require(Shared.Progression)

local Ui = require(script.Parent.Ui)
local Store = require(script.Parent.Store)
local SummonFx = require(script.Parent.SummonFx)
local Audio = require(script.Parent.Audio)

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

type Entry = { uid: string, u: string, t: string?, l: number, x: number, g: { [string]: string } }

local function entries(data): { Entry }
	local list = {}
	for uid, e in data.units do
		table.insert(list, { uid = uid, u = e.u, t = e.t, l = e.l or 1, x = e.x or 0, g = e.g or Progression.DefaultGrades })
	end
	table.sort(list, function(a, b)
		local ra = Rarities.Info[Units.ById[a.u].rarity].rank
		local rb = Rarities.Info[Units.ById[b.u].rarity].rank
		if ra ~= rb then
			return ra > rb
		end
		if a.l ~= b.l then
			return a.l > b.l
		end
		if a.u ~= b.u then
			return Units.ById[a.u].name < Units.ById[b.u].name
		end
		return tonumber(a.uid) < tonumber(b.uid)
	end)
	return list
end

local function entryOf(data, uid: string): Entry?
	local e = data.units[uid]
	if not e then
		return nil
	end
	return { uid = uid, u = e.u, t = e.t, l = e.l or 1, x = e.x or 0, g = e.g or Progression.DefaultGrades }
end

local function onTeam(data, uid: string): number?
	return table.find(data.team, uid)
end

local function mapUnlocked(data, index: number): boolean
	return index == 1 or (data.progress[Maps.List[index - 1].id] or 0) >= Maps.Stages
end

local blur: BlurEffect? = nil
local function setBlur(on: boolean)
	local effect = blur
	if not effect then
		effect = Instance.new("BlurEffect")
		effect.Name = "MenuBlur"
		effect.Size = 0
		effect.Parent = game:GetService("Lighting")
		blur = effect
	end
	TweenService:Create(effect, TweenInfo.new(0.2), { Size = on and 14 or 0 }):Play()
end

local function open(name: string?)
	if name ~= openName then
		Audio.play(name and "ui_open" or "ui_close", { volume = 0.5, gap = 0.1, max = 1 })
	end
	setBlur(name ~= nil)
	for n, w in windows do
		if n == name then
			if not w.Visible then
				Ui.openWindow(w)
			end
		else
			w.Visible = false
		end
	end
	openName = name
	if name and refreshers[name] then
		refreshers[name]()
	end
end
LobbyUI.open = open

local function closeButton()
	open(nil)
end

-- ============================================================ HUD: menu tiles, currencies, team tray

local gemsLabel: TextLabel
local crystalsLabel: TextLabel
local unitsLabel: TextLabel
local teamTray: Frame

local function tile(parent: Instance, emoji: string, label: string, color: Color3, order: number, key: string, onClick: () -> ())
	local t = Ui.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = parent,
	}, { Ui.corner(14), Ui.stroke(C.ink, 3), Ui.gradient(Ui.lighten(color, 0.2), Ui.darken(color, 0.35)) })
	Ui.new("Frame", { Size = UDim2.new(1, -8, 0.42, 0), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.85, Parent = t }, { Ui.corner(10) })
	Ui.icon(nil, emoji, { Size = UDim2.new(1, 0, 0, 58), Position = UDim2.fromOffset(0, 4), MaxText = 40, Parent = t })
	Ui.title({ Text = label, Size = UDim2.new(1, -6, 0, 22), Position = UDim2.new(0, 3, 1, -26), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 19, Parent = t })
	local badge = Ui.new("Frame", { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(-6, -6), BackgroundColor3 = Color3.fromRGB(30, 24, 50), ZIndex = 3, Parent = t }, { Ui.corner(6), Ui.stroke(C.ink, 2) })
	Ui.text({ Text = key, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 15, ZIndex = 4, Parent = badge })
	-- a shine sweeps across the tile every few seconds
	local clip = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2, Parent = t }, { Ui.corner(14) })
	local shine = Ui.new("Frame", {
		Size = UDim2.new(0.5, 0, 1.6, 0),
		Position = UDim2.fromScale(-0.8, -0.3),
		Rotation = 20,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = clip,
	}, {
		Ui.new("UIGradient", {
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		}),
	})
	task.spawn(function()
		task.wait(order * 0.35)
		while shine.Parent do
			shine.Position = UDim2.fromScale(-0.8, -0.3)
			TweenService:Create(shine, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(1.3, -0.3) }):Play()
			task.wait(4)
		end
	end)
	local scale = Ui.new("UIScale", { Parent = t })
	t.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1.07 }):Play()
	end)
	t.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	t.Activated:Connect(onClick)
end

local hotkeys: { [Enum.KeyCode]: string } = {}

local function buildMenu()
	local menu = Ui.new("Frame", {
		Size = UDim2.fromOffset(206, 330),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(98, 96), CellPadding = UDim2.fromOffset(10, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local items = {
		{ "⚔️", "PLAY", C.green, "Play", "P", Enum.KeyCode.P },
		{ "✨", "SUMMON", C.pink, "Summon", "J", Enum.KeyCode.J },
		{ "🎒", "UNITS", C.blue, "Units", "H", Enum.KeyCode.H },
		{ "🔮", "TRAITS", C.purple, "Traits", "T", Enum.KeyCode.T },
		{ "🏆", "QUESTS", C.orange, "Challenges", "C", Enum.KeyCode.C },
	}
	for i, it in items do
		hotkeys[it[6]] = it[4]
		tile(menu, it[1], it[2], it[3], i, it[5], function()
			open(openName ~= it[4] and it[4] or nil)
		end)
	end
end

local function pill(parent: Instance, emoji: string, color: Color3, width: number, order: number): TextLabel
	local p = Ui.new("Frame", {
		Size = UDim2.fromOffset(width, 44),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = parent,
	}, { Ui.round(), Ui.stroke(C.ink, 3), Ui.gradient(Color3.fromRGB(60, 48, 110), Color3.fromRGB(28, 22, 54)) })
	local icon = Ui.new("Frame", {
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = p,
	}, { Ui.round(), Ui.stroke(C.ink, 3), Ui.gradient(Ui.lighten(color, 0.3), Ui.darken(color, 0.25)) })
	Ui.icon(nil, emoji, { Size = UDim2.fromScale(0.82, 0.82), Position = UDim2.fromScale(0.09, 0.09), MaxText = 26, Parent = icon })
	return Ui.title({ Text = "0", Size = UDim2.new(1, -60, 0, 30), Position = UDim2.fromOffset(52, 7), MaxText = 26, Parent = p })
end

local function buildTopBar()
	local bar = Ui.new("Frame", {
		Size = UDim2.fromOffset(640, 44),
		Position = UDim2.new(0.5, 0, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center) })
	gemsLabel = pill(bar, "💎", C.gem, 190, 1)
	crystalsLabel = pill(bar, "🔮", C.crystal, 170, 2)
	unitsLabel = pill(bar, "🎒", C.blue, 170, 3)
end

local levelLabel: TextLabel
local levelFill: Frame

local function refreshTeamTray()
	local data = Store.data
	Ui.clear(teamTray)
	for i = 1, Units.TeamSize do
		local uid = data.team[i]
		local e = uid ~= "" and entryOf(data, uid)
		local unlocked = Progression.slotUnlocked(data.level, i)
		if e and unlocked then
			local card = Ui.unitCard(teamTray, { unitId = e.u, level = e.l, trait = e.t, price = Stats.placeCost(e.u, e.t) }, UDim2.fromOffset(92, 108), function()
				selectedUnit = e.uid
				open("Units")
			end)
			card.LayoutOrder = i
		else
			local slot = Ui.new("TextButton", {
				Text = "",
				Size = UDim2.fromOffset(92, 108),
				BackgroundColor3 = Color3.fromRGB(26, 20, 44),
				BackgroundTransparency = 0.15,
				LayoutOrder = i,
				Parent = teamTray,
			}, { Ui.corner(12), Ui.stroke(Color3.fromRGB(70, 60, 120), 2) })
			Ui.text({ Text = tostring(i), Size = UDim2.fromOffset(20, 18), Position = UDim2.new(1, -24, 0, 4), MaxText = 16, Parent = slot })
			if not unlocked then
				Ui.icon("lock", "🔒", { Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 24), MaxText = 28, Parent = slot })
				Ui.text({ Text = "Level " .. Progression.SlotUnlock[i], Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 66), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 18, Parent = slot })
			end
			slot.Activated:Connect(function()
				if unlocked then
					open("Units")
				else
					Ui.toast("Slot " .. i .. " unlocks at player level " .. Progression.SlotUnlock[i], C.red)
				end
			end)
		end
	end
	local level = data.level or 1
	local need = Progression.playerXpToNext(level)
	levelLabel.Text = string.format("Lvl %d (%d/%d XP)", level, data.xp or 0, need)
	levelFill.Size = UDim2.fromScale(math.clamp((data.xp or 0) / need, 0, 1), 1)
end

local function buildTeamTray()
	local tray = Ui.new("Frame", {
		Size = UDim2.fromOffset(6 * 98 + 24, 132),
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = gui,
	}, { Ui.corner(18), Ui.stroke(C.ink, 3), Ui.gradient(Color3.fromRGB(56, 44, 104), Color3.fromRGB(26, 20, 50)) })
	Ui.chip("YOUR TEAM", C.gold, { Size = UDim2.fromOffset(120, 24), Position = UDim2.new(0.5, -60, 0, -13), ZIndex = 3, Parent = tray })
	teamTray = Ui.new("Frame", {
		Size = UDim2.new(1, -16, 1, -18),
		Position = UDim2.fromOffset(8, 13),
		BackgroundTransparency = 1,
		Parent = tray,
	}, { Ui.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	-- the player's level bar under the team
	local bar, fill = Ui.bar(gui, { Size = UDim2.fromOffset(620, 14), Position = UDim2.new(0.5, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1) }, C.gold, 0)
	levelFill = fill
	levelLabel = Ui.title({ Text = "", Size = UDim2.fromOffset(300, 20), Position = UDim2.new(0.5, 0, 0, -22), AnchorPoint = Vector2.new(0.5, 0), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 18, Parent = bar })
end

-- ============================================================ Play

local function stars(n: number, total: number): string
	return string.rep("★", n) .. string.rep("☆", total - n)
end

local function buildPlay()
	local window, content = Ui.window(gui, "Campaign", "⚔️", UDim2.fromOffset(980, 560), closeButton)
	windows.Play = window
	local mapList = Ui.new("ScrollingFrame", {
		Size = UDim2.new(0, 270, 1, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 10), Ui.padding(6) })
	local detail = Ui.inset(content, { Size = UDim2.new(1, -286, 1, 0), Position = UDim2.fromOffset(286, 0) })
	Ui.padding(16).Parent = detail

	refreshers.Play = function()
		local data = Store.data
		Ui.clear(mapList)
		for i, def in Maps.List do
			local unlocked = mapUnlocked(data, i)
			local cleared = data.progress[def.id] or 0
			local t = Ui.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, -4, 0, 78),
				BackgroundColor3 = Color3.new(1, 1, 1),
				LayoutOrder = i,
				Parent = mapList,
			}, {
				Ui.corner(14),
				Ui.stroke(def.id == selectedMap and Color3.new(1, 1, 1) or C.ink, def.id == selectedMap and 4 or 3),
				Ui.gradient(Ui.lighten(def.theme.ground, 0.15), Ui.darken(def.theme.ground, 0.45), 0),
			})
			Ui.title({ Text = def.name, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(12, 8), MaxText = 24, Parent = t })
			Ui.text({ Text = stars(cleared, Maps.Stages), Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(12, 42), TextColor3 = C.gold, MaxText = 24, Parent = t })
			if not unlocked then
				Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, ZIndex = 3, Parent = t }, { Ui.corner(14) })
				Ui.icon("lock", "🔒", { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -50, 0.5, -20), MaxText = 32, ZIndex = 4, Parent = t })
			end
			t.Activated:Connect(function()
				selectedMap = def.id
				selectedStage = math.min((data.progress[def.id] or 0) + 1, Maps.Stages)
				refreshers.Play()
			end)
		end

		Ui.clear(detail)
		local def = Maps.ById[selectedMap]
		local unlocked = mapUnlocked(data, Maps.Index[selectedMap])
		local cleared = data.progress[def.id] or 0
		Ui.title({ Text = def.name, Size = UDim2.new(1, -140, 0, 40), MaxText = 36, Parent = detail })
		Ui.text({ Text = def.desc, Size = UDim2.new(1, -140, 0, 24), Position = UDim2.fromOffset(0, 44), TextColor3 = C.muted, MaxText = 18, Parent = detail })
		local boss = Enemies.ById[def.boss]
		local bossCard = Ui.new("Frame", {
			Size = UDim2.fromOffset(124, 132),
			Position = UDim2.new(1, -124, 0, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = detail,
		}, { Ui.corner(12), Ui.stroke(C.ink, 3), Ui.gradient(Color3.fromRGB(150, 40, 70), Color3.fromRGB(50, 10, 30)) })
		Ui.viewport(def.boss, { Size = UDim2.new(1, 0, 1, -26) }, true).Parent = bossCard
		Ui.chip("BOSS", C.red, { Size = UDim2.fromOffset(60, 20), Position = UDim2.new(0.5, -30, 0, -10), ZIndex = 3, Parent = bossCard })
		Ui.text({ Text = Ui.enemyName(boss.id, boss.name), Size = UDim2.new(1, -8, 0, 20), Position = UDim2.new(0, 4, 1, -24), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 15, Parent = bossCard })
		Ui.text({
			Text = boss.desc,
			Size = UDim2.new(1, -140, 0, 40),
			Position = UDim2.fromOffset(0, 74),
			TextWrapped = true,
			TextColor3 = Color3.fromRGB(255, 170, 210),
			MaxText = 16,
			Parent = detail,
		})

		Ui.title({ Text = "ENEMIES", Size = UDim2.fromOffset(200, 24), Position = UDim2.fromOffset(0, 140), MaxText = 20, Parent = detail })
		local row = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 92), Position = UDim2.fromOffset(0, 168), BackgroundTransparency = 1, Parent = detail }, { Ui.list(Enum.FillDirection.Horizontal, 8) })
		local shown = {}
		for _, id in def.ground do
			table.insert(shown, id)
		end
		for _, id in def.flying do
			table.insert(shown, id)
		end
		for _, id in shown do
			local e = Enemies.ById[id]
			local holder = Ui.new("Frame", {
				Size = UDim2.fromOffset(86, 92),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = row,
			}, { Ui.corner(10), Ui.stroke(C.ink, 2), Ui.gradient(Color3.fromRGB(80, 66, 140), Color3.fromRGB(40, 30, 80)) })
			Ui.viewport(id, { Size = UDim2.new(1, 0, 1, -22) }).Parent = holder
			Ui.text({ Text = Ui.enemyName(id, e.name), Size = UDim2.new(1, -6, 0, 18), Position = UDim2.new(0, 3, 1, -20), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 13, Parent = holder })
			if e.kind == "flying" then
				Ui.chip("AIR", C.blue, { Size = UDim2.fromOffset(40, 18), Position = UDim2.fromOffset(4, 4), ZIndex = 3, Parent = holder })
			end
		end

		Ui.title({ Text = "STAGE", Size = UDim2.fromOffset(200, 24), Position = UDim2.fromOffset(0, 274), MaxText = 20, Parent = detail })
		local stageRow = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 302), BackgroundTransparency = 1, Parent = detail }, { Ui.list(Enum.FillDirection.Horizontal, 10) })
		for s = 1, Maps.Stages do
			local available = unlocked and cleared >= s - 1
			local color = s == selectedStage and C.gold or (cleared >= s and C.green or (available and C.blue or C.panel))
			local b = Ui.button(tostring(s) .. (s == Maps.Stages and "\nBOSS" or (cleared >= s and "\n✓" or "")), color, function()
				if available then
					selectedStage = s
					refreshers.Play()
				end
			end, { Size = UDim2.fromOffset(84, 64), MaxText = 24, Parent = stageRow })
			b.Font = Ui.TitleFont
			if not available then
				b.TextColor3 = C.muted
			end
		end

		local waves = 6 + 2 * selectedStage
		local first = selectedStage > cleared
		Ui.text({
			Text = string.format("%d waves  •  %s", waves, first and ("First clear: 💎 gems + 🔮 " .. (selectedStage == Maps.Stages and "3 crystals" or "1 crystal")) or "Replay: 💎 gems"),
			Size = UDim2.new(1, -230, 0, 30),
			Position = UDim2.new(0, 0, 1, -50),
			TextColor3 = C.muted,
			MaxText = 18,
			Parent = detail,
		})
		local canStart = unlocked and cleared >= selectedStage - 1
		local start = Ui.button(canStart and "START" or "LOCKED", canStart and C.green or C.panel, function()
			if not canStart then
				return
			end
			local ok, err = Store.call("StartBattle", "campaign", selectedMap, selectedStage)
			if ok then
				open(nil)
			else
				Ui.toast(err or "Could not start", C.red)
			end
		end, { Size = UDim2.fromOffset(210, 62), Position = UDim2.new(1, -210, 1, -62), MaxText = 34, Parent = detail })
		start.Font = Ui.TitleFont
	end
end

-- ============================================================ Summon

local function showSummonResults(results)
	open(nil)
	SummonFx.play(results, function()
		open("Summon")
	end)
end

local function buildSummon()
	local window, content = Ui.window(gui, "Summon", "✨", UDim2.fromOffset(980, 560), closeButton)
	windows.Summon = window

	refreshers.Summon = function()
		local data = Store.data
		Ui.clear(content)
		local banner = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 300),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = content,
		}, { Ui.corner(16), Ui.stroke(C.ink, 3) })
		local bg = Ui.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 40, 200)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(230, 70, 160)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 40, 180)),
			}),
			Parent = banner,
		})
		Ui.spin(bg, 12)
		Ui.title({ Text = "★ STAR BANNER ★", Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 8), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 40, Parent = banner })
		local row = Ui.new("Frame", { Size = UDim2.new(1, -20, 0, 220), Position = UDim2.fromOffset(10, 60), BackgroundTransparency = 1, Parent = banner }, { Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
		local featured = {}
		for _, r in { "Mythic", "Legendary" } do
			for _, def in Units.ByRarity[r] do
				table.insert(featured, def)
			end
		end
		for _, def in featured do
			local holder = Ui.new("Frame", { Size = UDim2.fromOffset(146, 220), BackgroundTransparency = 1, Parent = row })
			Ui.new("Frame", {
				Size = UDim2.fromOffset(120, 26),
				Position = UDim2.new(0.5, -60, 1, -56),
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = holder,
			}, { Ui.round(), Ui.stroke(C.ink, 2), Ui.gradient(Ui.lighten(rarityColor(def.rarity), 0.4), Ui.darken(rarityColor(def.rarity), 0.3)) })
			Ui.viewport(def.id, { Size = UDim2.new(1, 0, 1, -50) }, true).Parent = holder
			Ui.text({ Text = Ui.unitName(def.id), Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 1, -28), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 17, Parent = holder })
			Ui.text({ Text = def.rarity, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -10), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = rarityColor(def.rarity), MaxText = 14, Parent = holder })
		end

		local rates = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 312), BackgroundTransparency = 1, Parent = content }, { Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
		for _, r in Rarities.Order do
			Ui.chip(r .. " " .. Rarities.SummonRates[r] .. "%", rarityColor(r), { Size = UDim2.fromOffset(170, 28), Parent = rates })
		end

		local legLeft = Rarities.LegendaryPity - data.pity.legendary
		local mythLeft = Rarities.MythicPity - data.pity.mythic
		Ui.text({ Text = "Legendary+ guaranteed in " .. legLeft, Size = UDim2.fromOffset(300, 20), Position = UDim2.fromOffset(20, 352), MaxText = 16, Parent = content })
		Ui.bar(content, { Size = UDim2.fromOffset(300, 14), Position = UDim2.fromOffset(20, 376) }, C.gold, data.pity.legendary / Rarities.LegendaryPity)
		Ui.text({ Text = "Mythic guaranteed in " .. mythLeft, Size = UDim2.fromOffset(300, 20), Position = UDim2.fromOffset(20, 398), MaxText = 16, Parent = content })
		Ui.bar(content, { Size = UDim2.fromOffset(300, 14), Position = UDim2.fromOffset(20, 422) }, C.pink, data.pity.mythic / Rarities.MythicPity)

		local function summon(count: number)
			local ok, results = Store.call("Summon", count)
			if ok then
				showSummonResults(results)
			else
				Ui.toast(results or "Summon failed", C.red)
			end
		end
		local one = Ui.button("SUMMON x1\n💎 50", C.blue, function()
			summon(1)
		end, { Size = UDim2.fromOffset(230, 84), Position = UDim2.new(1, -490, 1, -96), MaxText = 28, Parent = content })
		one.Font = Ui.TitleFont
		local ten = Ui.button("SUMMON x10\n💎 450", C.gold, function()
			summon(10)
		end, { Size = UDim2.fromOffset(230, 84), Position = UDim2.new(1, -240, 1, -96), MaxText = 28, Parent = content })
		ten.Font = Ui.TitleFont
	end
end

-- ============================================================ Units

local unitSearch = ""
local unitFilter = "All"
local FILTERS = { "All", "Mythic", "Legendary", "Rare", "Common", "Team", "Locked" }

-- a square icon button for the column beside the unit details
local function iconButton(parent: Instance, icon: string, color: Color3, order: number, onClick: () -> ())
	local b = Ui.button(icon, color, onClick, { Size = UDim2.fromOffset(52, 52), LayoutOrder = order, MaxText = 26, Parent = parent })
	b.TextColor3 = Color3.new(1, 1, 1)
	return b
end

local function buildUnits()
	local window, content = Ui.window(gui, "Units", "⭐", UDim2.fromOffset(1120, 640), closeButton)
	windows.Units = window

	-- top row: search and filter
	local search = Ui.new("TextBox", {
		Size = UDim2.new(0, 560, 0, 40),
		Position = UDim2.fromOffset(330, -2),
		BackgroundColor3 = Color3.fromRGB(14, 10, 26),
		PlaceholderText = "Search...",
		PlaceholderColor3 = C.muted,
		Text = "",
		Font = Ui.Font,
		TextSize = 20,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = window,
	}, { Ui.corner(10), Ui.stroke(Color3.fromRGB(70, 56, 130), 2), Ui.padding(10) })
	local filterButton
	filterButton = Ui.button("☰  Filters: All", C.panel, function()
		unitFilter = FILTERS[(table.find(FILTERS, unitFilter) or 1) % #FILTERS + 1]
		filterButton.Text = "☰  Filters: " .. unitFilter
		refreshers.Units()
	end, { Size = UDim2.fromOffset(160, 40), Position = UDim2.new(1, -230, 0, -2), MaxText = 18, Parent = window })
	search:GetPropertyChangedSignal("Text"):Connect(function()
		unitSearch = search.Text:lower()
		refreshers.Units()
	end)

	local grid = Ui.new("ScrollingFrame", {
		Size = UDim2.new(0, 620, 1, -110),
		Position = UDim2.fromOffset(0, 46),
		BackgroundColor3 = Color3.fromRGB(14, 10, 26),
		BackgroundTransparency = 0.3,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, {
		Ui.corner(12),
		Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(112, 130), CellPadding = UDim2.fromOffset(8, 14), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.padding(10),
	})
	local countChip = Ui.chip("0/150", C.panel, { Size = UDim2.fromOffset(110, 30), Position = UDim2.new(0, 10, 1, -100), ZIndex = 5, Parent = content })

	-- right: the selected unit
	local detail = Ui.new("Frame", {
		Size = UDim2.new(1, -700, 1, -110),
		Position = UDim2.fromOffset(632, 46),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = content,
	}, { Ui.corner(14), Ui.stroke(Color3.fromRGB(90, 200, 120), 3), Ui.padding(12) })
	local detailGradient = Ui.gradient(Color3.fromRGB(40, 110, 70), Color3.fromRGB(14, 40, 26))
	detailGradient.Parent = detail
	local icons = Ui.new("Frame", { Size = UDim2.new(0, 56, 1, -110), Position = UDim2.new(1, -56, 0, 46), BackgroundTransparency = 1, Parent = content }, { Ui.list(Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center) })

	-- bottom buttons, as in the reference: Unequip All / Teams / Quick Sell / Equip
	local bottom = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 52), Position = UDim2.new(0, 0, 1, -52), BackgroundTransparency = 1, Parent = content }, {
		Ui.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center),
	})

	refreshers.Units = function()
		local data = Store.data
		local all = entries(data)
		local list = {}
		for _, e in all do
			local def = Units.ById[e.u]
			local name = Ui.unitName(e.u):lower()
			local okSearch = unitSearch == "" or name:find(unitSearch, 1, true) ~= nil
			local okFilter = unitFilter == "All"
				or def.rarity == unitFilter
				or (unitFilter == "Team" and onTeam(data, e.uid) ~= nil)
				or (unitFilter == "Locked" and data.units[e.uid].k)
			if okSearch and okFilter then
				table.insert(list, e)
			end
		end
		if selectedUnit and not data.units[selectedUnit] then
			selectedUnit = nil
		end
		if not selectedUnit and all[1] then
			selectedUnit = all[1].uid
		end
		countChip:FindFirstChildWhichIsA("TextLabel").Text = #all .. "/" .. Units.InventoryLimit
		Ui.clear(grid)
		for i, e in list do
			local slot = onTeam(data, e.uid)
			local card = Ui.unitCard(grid, {
				unitId = e.u,
				level = e.l,
				trait = e.t,
				price = Stats.placeCost(e.u, e.t),
				selected = e.uid == selectedUnit,
				badge = slot and ("TEAM " .. slot) or nil,
			}, UDim2.new(), function()
				selectedUnit = e.uid
				equipMode = false
				refreshers.Units()
			end)
			card.LayoutOrder = i
			if data.units[e.uid].k then
				Ui.text({ Text = "🔒", Size = UDim2.fromOffset(20, 20), Position = UDim2.new(1, -24, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 16, Outline = 0, ZIndex = 6, Parent = card })
			end
		end

		Ui.clear(detail)
		Ui.clear(icons)
		Ui.clear(bottom)
		local e = selectedUnit and entryOf(data, selectedUnit)
		local def = e and Units.ById[e.u]
		local slot = e and onTeam(data, e.uid)

		-- bottom buttons
		Ui.button("Unequip All", C.red, function()
			for i = 1, Units.TeamSize do
				if Store.data.team[i] ~= "" then
					Store.call("EquipUnit", i, "")
				end
			end
		end, { Size = UDim2.fromOffset(240, 50), MaxText = 22, Parent = bottom })
		Ui.button("Teams", C.purple, function()
			-- best unit of each type, best rarity first, into the unlocked slots
			local picked, used = {}, {}
			for _, x in entries(Store.data) do
				if not used[x.u] and #picked < Units.TeamSize then
					used[x.u] = true
					table.insert(picked, x.uid)
				end
			end
			local n = 1
			for i = 1, Units.TeamSize do
				if Progression.slotUnlocked(Store.data.level, i) then
					Store.call("EquipUnit", i, picked[n] or "")
					n += 1
				end
			end
		end, { Size = UDim2.fromOffset(240, 50), MaxText = 22, Parent = bottom })
		local releaseGems = def and Rarities.Info[def.rarity].releaseGems or 0
		local confirming = false
		local sell
		sell = Ui.button("Quick Sell", C.gold, function()
			if not e then
				return
			end
			if not confirming then
				confirming = true
				sell.Text = "Sell for 💎" .. releaseGems .. "?"
				task.delay(3, function()
					confirming = false
					if sell.Parent then
						sell.Text = "Quick Sell"
					end
				end)
				return
			end
			local ok, err = Store.call("ReleaseUnit", e.uid)
			if ok then
				selectedUnit = nil
			else
				Ui.toast(err or "Could not sell", C.red)
			end
		end, { Size = UDim2.fromOffset(240, 50), MaxText = 22, Parent = bottom })
		Ui.button(slot and "Unequip" or "Equip", slot and C.red or C.green, function()
			if not e then
				return
			end
			if slot then
				Store.call("EquipUnit", slot, "")
			else
				equipMode = not equipMode
				refreshers.Units()
			end
		end, { Size = UDim2.new(1, -760, 0, 50), MaxText = 24, Parent = bottom })

		if not e or not def then
			return
		end
		local color = rarityColor(def.rarity)
		detailGradient.Color = ColorSequence.new(Ui.darken(color, 0.35), Ui.darken(color, 0.85))
		local stroke = detail:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end

		-- the coloured strip of grade blocks across the top
		local strip = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, Parent = detail }, { Ui.list(Enum.FillDirection.Horizontal, 4) })
		for i = 1, 9 do
			local g = ({ e.g.d, e.g.s, e.g.r })[(i - 1) % 3 + 1]
			Ui.new("Frame", { Size = UDim2.new(1 / 9, -4, 1, 0), BackgroundColor3 = Progression.GradeColor[g] or C.panel, Parent = strip }, { Ui.corner(3) })
		end
		-- tags
		local tags = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 22), BackgroundTransparency = 1, Parent = detail }, { Ui.list(Enum.FillDirection.Horizontal, 6) })
		local s = Stats.compute(e.u, 0, e.t, nil, { l = e.l, g = e.g })
		Ui.chip(def.attack.kind == "none" and "💰 Farm" or (s.hitsAir and "🌤 Air+Ground" or "🌍 Ground"), C.panel, { Size = UDim2.fromOffset(120, 26), Parent = tags })
		Ui.chip("⚔ " .. def.role, C.panel, { Size = UDim2.fromOffset(150, 26), Parent = tags })
		Ui.chip("👤 " .. def.limit, C.panel, { Size = UDim2.fromOffset(56, 26), Parent = tags })
		Ui.text({ Text = def.rarity .. " Unit", Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 54), TextColor3 = Ui.lighten(color, 0.3), MaxText = 18, Parent = detail })
		Ui.title({ Text = Ui.unitName(e.u), Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 74), MaxText = 32, Parent = detail })
		Ui.viewport(e.u, { Size = UDim2.new(1, 0, 1, -230), Position = UDim2.fromOffset(0, 108) }, true).Parent = detail
		-- level bar
		local maxed = e.l >= Progression.MaxLevel
		Ui.title({ Text = "Lvl " .. e.l, Size = UDim2.fromOffset(80, 22), Position = UDim2.new(0, 0, 1, -116), MaxText = 20, Parent = detail })
		Ui.bar(detail, { Size = UDim2.new(1, -90, 0, 14), Position = UDim2.new(0, 88, 1, -112) }, C.gold, maxed and 1 or e.x / Progression.xpToNext(e.l))
		-- stats
		local stats = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 48), Position = UDim2.new(0, 0, 1, -88), BackgroundTransparency = 1, Parent = detail }, { Ui.list(Enum.FillDirection.Horizontal, 6) })
		if def.attack.kind ~= "none" then
			Ui.statChip("DMG", Ui.short(s.damage), e.g.d, C.red, { Size = UDim2.new(1 / 3, -4, 1, 0), Parent = stats })
			Ui.statChip("SPA", string.format("%.2fs", s.cooldown), e.g.s, C.blue, { Size = UDim2.new(1 / 3, -4, 1, 0), Parent = stats })
			Ui.statChip("RNG", string.format("%.1f", s.range), e.g.r, C.gold, { Size = UDim2.new(1 / 3, -4, 1, 0), Parent = stats })
		else
			Ui.statChip("FARM", "$" .. math.floor(s.farm) .. " / wave", nil, C.gold, { Size = UDim2.fromScale(1, 1), Parent = stats })
		end
		local trait = e.t and Traits.ById[e.t]
		Ui.text({
			Text = trait and ("🔮 " .. trait.name .. ": " .. trait.desc) or "🔮 No trait yet",
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.new(0, 0, 1, -34),
			TextWrapped = true,
			TextColor3 = trait and Ui.lighten(rarityColor(trait.rarity), 0.3) or C.muted,
			MaxText = 15,
			Parent = detail,
		})

		-- icon column
		iconButton(icons, "🔮", C.purple, 1, function()
			traitUnit = e.uid
			open("Traits")
		end)
		iconButton(icons, data.units[e.uid].k and "🔒" or "🔓", data.units[e.uid].k and C.gold or C.panel, 2, function()
			Store.call("LockUnit", e.uid)
		end)
		iconButton(icons, "⭐", C.blue, 3, function()
			equipMode = not equipMode
			refreshers.Units()
		end)

		-- slot picker over the details
		if equipMode then
			local picker = Ui.new("Frame", {
				Size = UDim2.new(1, 0, 0, 120),
				Position = UDim2.new(0, 0, 0.5, -60),
				BackgroundColor3 = Color3.fromRGB(14, 10, 26),
				BackgroundTransparency = 0.1,
				ZIndex = 10,
				Parent = detail,
			}, { Ui.corner(12), Ui.stroke(C.gold, 3) })
			Ui.title({ Text = "PICK A TEAM SLOT", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 6), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 22, ZIndex = 11, Parent = picker })
			local row = Ui.new("Frame", { Size = UDim2.new(1, -20, 0, 60), Position = UDim2.fromOffset(10, 44), BackgroundTransparency = 1, ZIndex = 11, Parent = picker }, { Ui.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
			for i = 1, Units.TeamSize do
				local unlocked = Progression.slotUnlocked(data.level, i)
				local current = data.team[i]
				local b = Ui.button(unlocked and tostring(i) or ("🔒" .. Progression.SlotUnlock[i]), unlocked and (current ~= "" and C.blue or C.green) or C.panel, function()
					if not unlocked then
						Ui.toast("Slot " .. i .. " unlocks at player level " .. Progression.SlotUnlock[i], C.red)
						return
					end
					local ok, err = Store.call("EquipUnit", i, e.uid)
					if not ok then
						Ui.toast(err or "Could not equip", C.red)
					end
					equipMode = false
					refreshers.Units()
				end, { Size = UDim2.fromOffset(56, 56), MaxText = 22, ZIndex = 12, Parent = row })
				b.ZIndex = 12
			end
		end
	end
end

-- ============================================================ Traits

local function buildTraits()
	local window, content = Ui.window(gui, "Traits", "🔮", UDim2.fromOffset(1000, 580), closeButton)
	windows.Traits = window
	local picker = Ui.new("ScrollingFrame", {
		Size = UDim2.new(0, 260, 1, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 8), Ui.padding(6) })
	local roller = Ui.inset(content, { Size = UDim2.new(0, 330, 1, 0), Position = UDim2.fromOffset(272, 0) })
	Ui.padding(14).Parent = roller
	local index = Ui.new("ScrollingFrame", {
		Size = UDim2.new(1, -616, 1, 0),
		Position = UDim2.fromOffset(616, 0),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 6), Ui.padding(6) })

	-- the trait index never changes
	local order = 0
	for i = #Rarities.Order, 1, -1 do
		local r = Rarities.Order[i]
		order += 1
		Ui.chip(string.format("%s  %s%%", r, tostring(Rarities.TraitRates[r])), rarityColor(r), { Size = UDim2.new(1, -10, 0, 30), LayoutOrder = order, Parent = index })
		for _, t in Traits.ByRarity[r] do
			order += 1
			local row = Ui.new("Frame", { Size = UDim2.new(1, -10, 0, 46), BackgroundColor3 = C.panelDark, BackgroundTransparency = 0.2, LayoutOrder = order, Parent = index }, { Ui.corner(8) })
			Ui.text({ Text = t.name, Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(8, 3), TextColor3 = Ui.lighten(rarityColor(r), 0.2), MaxText = 16, Parent = row })
			Ui.text({ Text = t.desc, Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(8, 25), TextColor3 = C.muted, MaxText = 13, Outline = 1, Parent = row })
		end
	end

	refreshers.Traits = function()
		local data = Store.data
		local list = entries(data)
		if traitUnit and not data.units[traitUnit] then
			traitUnit = nil
		end
		if not traitUnit and list[1] then
			traitUnit = list[1].uid
		end
		Ui.clear(picker)
		for i, e in list do
			local def = Units.ById[e.u]
			local trait = e.t and Traits.ById[e.t]
			local row = Ui.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				Size = UDim2.new(1, -6, 0, 62),
				BackgroundColor3 = Color3.new(1, 1, 1),
				LayoutOrder = i,
				Parent = picker,
			}, {
				Ui.corner(10),
				Ui.stroke(e.uid == traitUnit and Color3.new(1, 1, 1) or C.ink, e.uid == traitUnit and 3 or 2),
				Ui.gradient(Ui.RarityGradient[def.rarity][1], Ui.RarityGradient[def.rarity][2], 0),
			})
			Ui.viewport(e.u, { Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(2, 2) }).Parent = row
			Ui.text({ Text = Ui.unitName(e.u) .. "  Lvl " .. e.l, Size = UDim2.new(1, -70, 0, 22), Position = UDim2.fromOffset(64, 6), MaxText = 16, Parent = row })
			Ui.text({
				Text = trait and trait.name or "no trait",
				Size = UDim2.new(1, -70, 0, 20),
				Position = UDim2.fromOffset(64, 32),
				TextColor3 = trait and Ui.lighten(rarityColor(trait.rarity), 0.3) or C.muted,
				MaxText = 15,
				Parent = row,
			})
			row.Activated:Connect(function()
				traitUnit = e.uid
				refreshers.Traits()
			end)
		end

		Ui.clear(roller)
		local e = traitUnit and entryOf(data, traitUnit)
		if not e then
			return
		end
		local def = Units.ById[e.u]
		local stage = Ui.new("Frame", {
			Size = UDim2.new(1, 0, 0, 170),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = roller,
		}, { Ui.corner(12), Ui.stroke(C.ink, 2), Ui.gradient(Ui.darken(rarityColor(def.rarity), 0.2), Ui.darken(rarityColor(def.rarity), 0.75)) })
		Ui.viewport(e.u, { Size = UDim2.fromScale(1, 1) }, true).Parent = stage
		Ui.title({ Text = Ui.unitName(e.u), Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 176), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 26, Parent = roller })
		local trait = e.t and Traits.ById[e.t]
		local current = Ui.title({
			Text = trait and trait.name or "NO TRAIT",
			Size = UDim2.new(1, 0, 0, 46),
			Position = UDim2.fromOffset(0, 214),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = trait and rarityColor(trait.rarity) or C.muted,
			MaxText = 40,
			Outline = 3,
			Parent = roller,
		})
		local desc = Ui.text({
			Text = trait and (trait.rarity .. ": " .. trait.desc) or "Roll to give this unit a trait.",
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 262),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = C.muted,
			MaxText = 16,
			Parent = roller,
		})
		Ui.chip("🔮 " .. data.crystals .. " Trait Crystal" .. (data.crystals == 1 and "" or "s"), C.crystal, { Size = UDim2.new(1, -40, 0, 30), Position = UDim2.new(0, 20, 1, -116), Parent = roller })
		local confirming = false
		local rollButton
		rollButton = Ui.button("ROLL TRAIT  🔮" .. Traits.RollCost, C.purple, function()
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
			local ok, result = Store.call("RollTrait", e.uid)
			if not ok then
				rolling = false
				Ui.toast(result or "Could not roll", C.red)
				return
			end
			local rolled = Traits.ById[result]
			-- spin through random trait names before landing on the result
			for i = 1, 14 do
				local t = Traits.List[math.random(1, #Traits.List)]
				current.Text = t.name
				current.TextColor3 = rarityColor(t.rarity)
				task.wait(0.03 + i * 0.012)
			end
			current.Text = rolled.name
			current.TextColor3 = rarityColor(rolled.rarity)
			desc.Text = rolled.rarity .. ": " .. rolled.desc
			Ui.pop(current)
			Ui.toast("Rolled " .. rolled.rarity .. " trait: " .. rolled.name .. "!", Ui.darken(rarityColor(rolled.rarity), 0.3))
			task.wait(0.8)
			rolling = false
			if openName == "Traits" then
				refreshers.Traits()
			end
		end, { Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 1, -74), MaxText = 26, Parent = roller })
		rollButton.Font = Ui.TitleFont
	end
end

-- ============================================================ Challenges

local function buildChallenges()
	local window, content = Ui.window(gui, "Challenges", "🏆", UDim2.fromOffset(940, 560), closeButton)
	windows.Challenges = window
	local list = Ui.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = content,
	}, { Ui.list(Enum.FillDirection.Vertical, 10), Ui.padding(6) })

	refreshers.Challenges = function()
		local data = Store.data
		Ui.clear(list)
		Ui.text({
			Text = "Each challenge pays 🔮 Trait Crystals once per day (resets 00:00 UTC). Replays pay a few gems.",
			Size = UDim2.new(1, -10, 0, 24),
			TextColor3 = C.muted,
			LayoutOrder = 0,
			MaxText = 17,
			Parent = list,
		})
		for i, ch in Challenges.List do
			local map = Maps.ById[ch.map]
			local unlocked = mapUnlocked(data, Maps.Index[ch.map]) and (data.progress[ch.map] or 0) >= 1
			local doneToday = data.challenges[ch.id] == Challenges.today()
			local row = Ui.new("Frame", {
				Size = UDim2.new(1, -10, 0, 92),
				BackgroundColor3 = Color3.new(1, 1, 1),
				LayoutOrder = i,
				Parent = list,
			}, { Ui.corner(14), Ui.stroke(C.ink, 3), Ui.gradient(Ui.darken(map.theme.ground, 0.2), Ui.darken(map.theme.ground, 0.7), 0) })
			Ui.title({ Text = ch.name, Size = UDim2.new(0.5, 0, 0, 32), Position = UDim2.fromOffset(14, 8), MaxText = 28, Parent = row })
			Ui.text({ Text = map.name .. " • stage " .. ch.stage .. " • " .. ch.desc, Size = UDim2.new(1, -330, 0, 40), Position = UDim2.fromOffset(14, 44), TextWrapped = true, TextColor3 = C.muted, MaxText = 16, Parent = row })
			local rewards = Ui.new("Frame", { Size = UDim2.fromOffset(300, 30), Position = UDim2.new(1, -310, 0, 10), BackgroundTransparency = 1, Parent = row }, { Ui.list(Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right) })
			if doneToday then
				Ui.chip("DONE TODAY", C.green, { Size = UDim2.fromOffset(130, 28), Parent = rewards })
				Ui.chip("💎 " .. ch.repeatGems, C.blue, { Size = UDim2.fromOffset(80, 28), Parent = rewards })
			else
				Ui.chip("🔮 x" .. ch.crystals, C.crystal, { Size = UDim2.fromOffset(90, 28), Parent = rewards })
				Ui.chip("💎 " .. ch.gems, C.blue, { Size = UDim2.fromOffset(90, 28), Parent = rewards })
			end
			local start = Ui.button(unlocked and "START" or "🔒 LOCKED", unlocked and C.green or C.panel, function()
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
			end, { Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -160, 0, 44), MaxText = 22, Parent = row })
			start.Font = Ui.TitleFont
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
	crystalsLabel.Text = Ui.formatNumber(data.crystals)
	local n = 0
	for _ in data.units do
		n += 1
	end
	unitsLabel.Text = n .. "/" .. Units.InventoryLimit
	refreshTeamTray()
	if openName and refreshers[openName] and not (openName == "Traits" and rolling) then
		refreshers[openName]()
	end
end

function LobbyUI.setVisible(visible: boolean)
	gui.Enabled = visible
	if not visible then
		open(nil)
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
	Ui.new("UIScale", { Name = "Scale", Parent = gui })
	buildTopBar()
	buildMenu()
	buildTeamTray()
	buildPlay()
	buildSummon()
	buildUnits()
	buildTraits()
	buildChallenges()
	Store.DataChanged:Connect(refreshAll)
	refreshAll()

	-- walking up to the Summon Hall pedestal or the battle portal opens their windows
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed or not gui.Enabled then
			return
		end
		local target = hotkeys[input.KeyCode]
		if target then
			open(openName ~= target and target or nil)
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local target = prompt:GetAttribute("OpensWindow")
		if type(target) == "string" and windows[target] and gui.Enabled then
			open(target)
		end
	end)
	return gui
end

return LobbyUI
