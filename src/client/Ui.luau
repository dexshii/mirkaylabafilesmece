-- UI toolkit and the game's look: chunky outlined text, gradient buttons, gold-bannered windows, rarity unit cards,
-- stat chips with grade badges, spinning model viewports and toasts.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local ModelFactory = require(Shared.ModelFactory)
local Units = require(Shared.Units)
local Traits = require(Shared.Traits)
local Rarities = require(Shared.Rarities)
local Progression = require(Shared.Progression)
local Skins = require(script.Parent.Skins)

local Ui = {}

Ui.Font = Enum.Font.FredokaOne
Ui.TitleFont = Enum.Font.LuckiestGuy
Ui.Colors = {
	bgTop = Color3.fromRGB(52, 40, 96),
	bgBottom = Color3.fromRGB(22, 17, 44),
	panel = Color3.fromRGB(38, 30, 74),
	panelDark = Color3.fromRGB(24, 19, 48),
	card = Color3.fromRGB(58, 48, 108),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(196, 188, 236),
	ink = Color3.fromRGB(18, 12, 30),
	green = Color3.fromRGB(60, 205, 90),
	red = Color3.fromRGB(235, 55, 70),
	blue = Color3.fromRGB(55, 140, 255),
	gold = Color3.fromRGB(255, 196, 30),
	orange = Color3.fromRGB(255, 140, 30),
	purple = Color3.fromRGB(150, 80, 255),
	pink = Color3.fromRGB(255, 80, 170),
	gem = Color3.fromRGB(70, 220, 255),
	crystal = Color3.fromRGB(215, 110, 255),
}
local C = Ui.Colors

-- rarity card gradients (top -> bottom)
Ui.RarityGradient = {
	Common = { Color3.fromRGB(196, 202, 212), Color3.fromRGB(96, 102, 118) },
	Rare = { Color3.fromRGB(100, 185, 255), Color3.fromRGB(28, 72, 196) },
	Legendary = { Color3.fromRGB(255, 222, 80), Color3.fromRGB(232, 112, 16) },
	Mythic = { Color3.fromRGB(255, 96, 150), Color3.fromRGB(176, 18, 74) },
}

-- ============================================================ basics

function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	for k, v in (props or {}) :: { [string]: any } do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, child in (children or {}) :: { Instance } do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

function Ui.round(): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

function Ui.stroke(color: Color3?, thickness: number?): UIStroke
	return Ui.new("UIStroke", {
		Color = color or C.ink,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.gradient(top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Ui.new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 })
end

function Ui.padding(n: number): UIPadding
	local u = UDim.new(0, n)
	return Ui.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Ui.list(direction: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?, valign: Enum.VerticalAlignment?): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = valign or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Ui.clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
end

local function lighten(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(1, 1, 1), t)
end
local function darken(c: Color3, t: number): Color3
	return c:Lerp(Color3.new(0, 0, 0), t)
end
Ui.lighten = lighten
Ui.darken = darken

-- text with a chunky dark outline. Extra keys: MaxText (largest text size), Outline (stroke thickness, 0 = none)
function Ui.text(props: { [string]: any }): TextLabel
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Ui.Font,
		TextColor3 = C.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		if k ~= "MaxText" and k ~= "Outline" then
			p[k] = v
		end
	end
	local label = Ui.new("TextLabel", p)
	Ui.new("UITextSizeConstraint", { MaxTextSize = props.MaxText or 24, Parent = label })
	local outline = props.Outline or 1.6
	if outline > 0 then
		Ui.new("UIStroke", { Thickness = outline, Color = C.ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = label })
	end
	return label
end

function Ui.title(props: { [string]: any }): TextLabel
	props.Font = Ui.TitleFont
	props.Outline = props.Outline or 2.4
	return Ui.text(props)
end

-- a pressable gradient button. Extra props: MaxText
function Ui.button(text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local p: { [string]: any } = {
		Text = text,
		Font = Ui.Font,
		TextScaled = true,
		TextColor3 = C.text,
		BackgroundColor3 = Color3.new(1, 1, 1),
		AutoButtonColor = false,
		Size = UDim2.fromOffset(140, 42),
	}
	for k, v in (props or {}) :: { [string]: any } do
		if k ~= "MaxText" then
			p[k] = v
		end
	end
	local button = Ui.new("TextButton", p, {
		Ui.corner(12),
		Ui.stroke(C.ink, 3),
		Ui.padding(6),
		Ui.gradient(lighten(color, 0.22), darken(color, 0.22)),
	})
	Ui.new("UITextSizeConstraint", { MaxTextSize = (props and props.MaxText) or 22, Parent = button })
	Ui.new("UIStroke", { Thickness = 2, Color = C.ink, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = button })
	local scale = Ui.new("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.94 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	local busy = false
	button.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		local ok, err = pcall(onClick)
		if not ok then
			warn(err)
		end
		busy = false
	end)
	return button
end

-- recolours a button made by Ui.button
function Ui.setButtonColor(button: GuiObject, color: Color3)
	local g = button:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(lighten(color, 0.22), darken(color, 0.22))
	end
end

-- a small rounded tag
function Ui.chip(text: string, color: Color3, props: { [string]: any }?): Frame
	local p: { [string]: any } = { Size = UDim2.fromOffset(110, 26), BackgroundColor3 = Color3.new(1, 1, 1) }
	for k, v in (props or {}) :: { [string]: any } do
		p[k] = v
	end
	local chip = Ui.new("Frame", p, { Ui.round(), Ui.stroke(C.ink, 2), Ui.gradient(lighten(color, 0.15), darken(color, 0.3)) })
	Ui.text({ Text = text, Size = UDim2.new(1, -12, 1, -4), Position = UDim2.fromOffset(6, 2), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 16, ZIndex = p.ZIndex, Parent = chip })
	return chip
end

-- ============================================================ animation

-- every registered gradient spins (mythic cards, banners)
local spinning: { [UIGradient]: number } = setmetatable({}, { __mode = "k" }) :: any
RunService.RenderStepped:Connect(function(dt)
	for g, speed in spinning do
		if g.Parent then
			g.Rotation = (g.Rotation + dt * speed) % 360
		end
	end
end)
function Ui.spin(g: UIGradient, speed: number?)
	spinning[g] = speed or 60
end

-- a frame pops in (UIScale from small with an overshoot)
function Ui.pop(frame: GuiObject, delay: number?)
	local s = frame:FindFirstChild("PopScale") or Ui.new("UIScale", { Name = "PopScale", Parent = frame })
	s.Scale = 0.6
	task.delay(delay or 0, function()
		TweenService:Create(s, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
end

-- ============================================================ windows

-- A window with a dark gradient body, gold border, a slanted gold title banner and a round red close button.
-- Returns the window and its content frame.
function Ui.window(parent: Instance, title: string, icon: string, size: UDim2, onClose: () -> ()): (Frame, Frame)
	local window = Ui.new("Frame", {
		Name = title,
		Size = size,
		Position = UDim2.fromScale(0.5, 0.53),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Visible = false,
		Parent = parent,
	}, { Ui.corner(18), Ui.gradient(C.bgTop, C.bgBottom) })
	local border = Ui.new("UIStroke", { Thickness = 5, Color = Color3.new(1, 1, 1), Parent = window })
	Ui.new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 110)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(240, 150, 30)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 90)),
		}),
		Rotation = 45,
		Parent = border,
	})
	-- the title banner, overlapping the top-left corner
	local banner = Ui.new("Frame", {
		Name = "Banner",
		Size = UDim2.fromOffset(330, 58),
		Position = UDim2.fromOffset(-16, -30),
		Rotation = -2,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
		Parent = window,
	}, { Ui.corner(14), Ui.stroke(C.ink, 3), Ui.gradient(Color3.fromRGB(255, 226, 96), Color3.fromRGB(236, 136, 22)) })
	Ui.title({ Text = icon, Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 5), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 40, ZIndex = 6, Parent = banner })
	Ui.title({ Text = title, Size = UDim2.new(1, -70, 0, 44), Position = UDim2.fromOffset(62, 7), MaxText = 38, ZIndex = 6, Parent = banner })
	local close = Ui.button("X", C.red, onClose, {
		Size = UDim2.fromOffset(52, 52),
		Position = UDim2.new(1, -30, 0, -24),
		ZIndex = 6,
		MaxText = 30,
		Parent = window,
	})
	close.Font = Ui.TitleFont
	close:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	local content = Ui.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -32, 1, -58),
		Position = UDim2.fromOffset(16, 40),
		BackgroundTransparency = 1,
		Parent = window,
	})
	return window, content
end

function Ui.openWindow(window: GuiObject)
	window.Visible = true
	Ui.pop(window)
end

-- a darker inset panel inside a window
function Ui.inset(parent: Instance, props: { [string]: any }): Frame
	local p: { [string]: any } = { BackgroundColor3 = C.panelDark, BackgroundTransparency = 0.15 }
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	return Ui.new("Frame", p, { Ui.corner(14), Ui.stroke(Color3.fromRGB(80, 66, 150), 2) })
end

-- ============================================================ models

local viewportSpin: { [ViewportFrame]: { camera: Camera, center: Vector3, dist: number, angle: number } } = setmetatable({}, { __mode = "k" }) :: any
RunService.RenderStepped:Connect(function(dt)
	for vp, s in viewportSpin do
		if vp.Parent and vp.Visible then
			s.angle += dt * 0.8
			s.camera.CFrame = CFrame.lookAt(s.center + Vector3.new(math.sin(s.angle) * s.dist, s.dist * 0.25, -math.cos(s.angle) * s.dist), s.center)
		end
	end
end)

-- a ViewportFrame showing a unit or enemy model; spin = true turns it slowly
function Ui.viewport(key: string, props: { [string]: any }?, spin: boolean?): ViewportFrame
	local p: { [string]: any } = {
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(180, 180, 190),
		LightColor = Color3.fromRGB(255, 250, 240),
		LightDirection = Vector3.new(-0.4, -1, 0.6),
	}
	for k, v in (props or {}) :: { [string]: any } do
		p[k] = v
	end
	local vp = Ui.new("ViewportFrame", p)
	local model = ModelFactory.build(key, 1, true)
	model.Parent = vp
	Skins.apply(model, true)
	local cf, size = model:GetBoundingBox()
	local dist = math.max(size.X * 0.9, size.Y, size.Z * 0.9) * 1.55 + 1
	local center = cf.Position
	local camera = Ui.new("Camera", {
		FieldOfView = 38,
		CFrame = CFrame.lookAt(center + Vector3.new(dist * 0.42, dist * 0.22, -dist), center),
		Parent = vp,
	})
	vp.CurrentCamera = camera
	if spin then
		viewportSpin[vp] = { camera = camera, center = center, dist = dist, angle = 0.4 }
	end
	return vp
end

-- ============================================================ unit cards and stats

function Ui.unitName(unitId: string): string
	return Skins.displayName(unitId) or ModelFactory.displayName(unitId, Units.ById[unitId].name)
end

function Ui.enemyName(enemyId: string, fallback: string): string
	return Skins.displayName(enemyId) or ModelFactory.displayName(enemyId, fallback)
end

function Ui.gradeBadge(grade: string, props: { [string]: any }): TextLabel
	local p: { [string]: any } = {
		Text = grade,
		Font = Ui.TitleFont,
		TextColor3 = Progression.GradeColor[grade] or C.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxText = 22,
		Outline = 2,
	}
	for k, v in props do
		p[k] = v
	end
	local label = Ui.text(p)
	if grade == "SSS" or grade == "SS" then
		Ui.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 160)),
				ColorSequenceKeypoint.new(0.5, Progression.GradeColor[grade]),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 160)),
			}),
			Parent = label,
		})
	end
	return label
end

-- a stat pill: grade badge, value and caption ("DMG 6.5k")
function Ui.statChip(caption: string, value: string, grade: string?, color: Color3, props: { [string]: any }?): Frame
	local p: { [string]: any } = { Size = UDim2.fromOffset(120, 44), BackgroundColor3 = Color3.new(1, 1, 1) }
	for k, v in (props or {}) :: { [string]: any } do
		p[k] = v
	end
	local chip = Ui.new("Frame", p, { Ui.corner(10), Ui.stroke(darken(color, 0.4), 2), Ui.gradient(darken(color, 0.45), darken(color, 0.7)) })
	Ui.text({ Text = caption, Size = UDim2.new(0, 46, 0, 14), Position = UDim2.fromOffset(6, 3), TextColor3 = lighten(color, 0.35), MaxText = 12, Outline = 1, Parent = chip })
	if grade then
		Ui.gradeBadge(grade, { Size = UDim2.fromOffset(40, 22), Position = UDim2.new(0, 4, 1, -25), Parent = chip })
	end
	Ui.text({ Text = value, Size = UDim2.new(1, grade and -48 or -12, 0, 26), Position = UDim2.new(0, grade and 44 or 6, 1, -29), TextXAlignment = Enum.TextXAlignment.Right, MaxText = 22, Parent = chip })
	return chip
end

function Ui.short(n: number): string
	if n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fk", n / 1e3)
	elseif n >= 1000 then
		return string.format("%.2fk", n / 1e3)
	elseif n >= 100 then
		return string.format("%d", math.floor(n + 0.5))
	end
	return string.format("%.1f", n)
end

function Ui.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

export type CardInfo = {
	unitId: string,
	level: number?,
	trait: string?,
	price: number?,
	badge: string?,
	badgeColor: Color3?,
	selected: boolean?,
	dim: boolean?,
}

-- A unit card: rarity gradient, model, "Lvl N", trait gem, price tag and name strip.
function Ui.unitCard(parent: Instance, info: CardInfo, size: UDim2, onClick: (() -> ())?): TextButton
	local def = Units.ById[info.unitId]
	local grad = Ui.RarityGradient[def.rarity]
	local card = Ui.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = parent,
	}, { Ui.corner(12), Ui.stroke(info.selected and Color3.new(1, 1, 1) or C.ink, info.selected and 4 or 3) })
	local g = Ui.gradient(grad[1], grad[2])
	g.Parent = card
	if def.rarity == "Mythic" then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 90, 160)),
			ColorSequenceKeypoint.new(0.35, Color3.fromRGB(170, 70, 255)),
			ColorSequenceKeypoint.new(0.7, Color3.fromRGB(70, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 160)),
		})
		Ui.spin(g, 50)
	end
	-- a soft shine across the top
	Ui.new("Frame", {
		Size = UDim2.new(1, -8, 0.35, 0),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.82,
		Parent = card,
	}, { Ui.corner(9) })
	Ui.viewport(info.unitId, { Size = UDim2.new(1, 0, 1, -12), Position = UDim2.fromOffset(0, 2), ZIndex = 2, Parent = card })
	-- name strip
	local strip = Ui.new("Frame", {
		Size = UDim2.new(1, -6, 0, 20),
		Position = UDim2.new(0, 3, 1, -23),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		ZIndex = 3,
		Parent = card,
	}, { Ui.corner(6) })
	Ui.text({ Text = Ui.unitName(info.unitId), Size = UDim2.new(1, -6, 1, -2), Position = UDim2.fromOffset(3, 1), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 15, ZIndex = 4, Parent = strip })
	if info.level then
		Ui.text({ Text = "Lvl " .. info.level, Size = UDim2.fromOffset(60, 18), Position = UDim2.fromOffset(5, 3), MaxText = 16, ZIndex = 4, Parent = card })
	end
	if info.price then
		Ui.text({
			Text = "$" .. Ui.formatNumber(info.price),
			Size = UDim2.new(0.75, 0, 0, 18),
			Position = UDim2.new(0.25, -5, 1, -42),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Color3.fromRGB(255, 225, 90),
			MaxText = 17,
			ZIndex = 4,
			Parent = card,
		})
	end
	if info.trait and Traits.ById[info.trait] then
		local t = Traits.ById[info.trait]
		local gem = Ui.new("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.new(1, -22, 0, 5),
			Rotation = 45,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 4,
			Parent = card,
		}, { Ui.corner(4), Ui.stroke(C.ink, 2), Ui.gradient(lighten(Rarities.Info[t.rarity].color, 0.4), Rarities.Info[t.rarity].color) })
		if t.rarity == "Mythic" then
			Ui.spin(gem:FindFirstChildOfClass("UIGradient") :: UIGradient, 120)
		end
	end
	if info.badge then
		Ui.chip(info.badge, info.badgeColor or C.green, { Size = UDim2.fromOffset(64, 20), Position = UDim2.new(0.5, -32, 0, -10), ZIndex = 6, Parent = card })
	end
	if info.dim then
		Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = 7, Parent = card }, { Ui.corner(12) })
	end
	if onClick then
		card.Activated:Connect(onClick)
	end
	local scale = Ui.new("UIScale", { Parent = card })
	card.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	return card
end

-- a progress bar; returns the bar and its fill
function Ui.bar(parent: Instance, props: { [string]: any }, fillColor: Color3, frac: number): (Frame, Frame)
	local p: { [string]: any } = { BackgroundColor3 = Color3.fromRGB(30, 22, 50) }
	for k, v in props do
		p[k] = v
	end
	p.Parent = parent
	local bar = Ui.new("Frame", p, { Ui.round(), Ui.stroke(C.ink, 2) })
	local fill = Ui.new("Frame", {
		Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = bar,
	}, { Ui.round(), Ui.gradient(lighten(fillColor, 0.3), darken(fillColor, 0.15)) })
	return bar, fill
end

-- ============================================================ toasts

local toastHolder: Frame? = nil
function Ui.toast(message: string, color: Color3?)
	if not toastHolder then
		local gui = Ui.new("ScreenGui", {
			Name = "Toasts",
			ResetOnSpawn = false,
			DisplayOrder = 50,
			IgnoreGuiInset = true,
			Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		})
		toastHolder = Ui.new("Frame", {
			Size = UDim2.new(0, 460, 1, -160),
			Position = UDim2.new(0.5, 0, 0, 120),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Parent = gui,
		}, { Ui.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	end
	local c = color or C.panel
	local toast = Ui.new("Frame", {
		Size = UDim2.fromOffset(440, 42),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = toastHolder,
	}, { Ui.corner(12), Ui.stroke(C.ink, 3), Ui.gradient(lighten(c, 0.15), darken(c, 0.25)) })
	local label = Ui.text({ Text = message, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Center, MaxText = 20, Parent = toast })
	Ui.pop(toast)
	task.delay(2.6, function()
		TweenService:Create(toast, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		local tween = TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

return Ui
