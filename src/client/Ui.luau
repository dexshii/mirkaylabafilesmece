-- Small UI toolkit: instance creation, the game's button/panel style, model viewports and toasts.
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local ModelFactory = require(game.ReplicatedStorage.Shared.ModelFactory)

local Ui = {}

Ui.Font = Enum.Font.FredokaOne
Ui.Colors = {
	panel = Color3.fromRGB(38, 34, 70),
	panelDark = Color3.fromRGB(26, 23, 50),
	card = Color3.fromRGB(56, 50, 100),
	text = Color3.fromRGB(255, 255, 255),
	muted = Color3.fromRGB(190, 185, 225),
	green = Color3.fromRGB(70, 200, 90),
	red = Color3.fromRGB(230, 70, 70),
	blue = Color3.fromRGB(60, 140, 255),
	gold = Color3.fromRGB(255, 200, 40),
	purple = Color3.fromRGB(160, 90, 255),
	gem = Color3.fromRGB(80, 220, 255),
	crystal = Color3.fromRGB(220, 120, 255),
}

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

function Ui.stroke(color: Color3?, thickness: number?): UIStroke
	return Ui.new("UIStroke", {
		Color = color or Color3.fromRGB(15, 12, 30),
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.padding(n: number): UIPadding
	local u = UDim.new(0, n)
	return Ui.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Ui.list(direction: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return Ui.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Ui.text(props: { [string]: any }): TextLabel
	local p = {
		BackgroundTransparency = 1,
		Font = Ui.Font,
		TextColor3 = Ui.Colors.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for k, v in props do
		if k ~= "MaxText" then
			p[k] = v
		end
	end
	local label = Ui.new("TextLabel", p)
	Ui.new("UITextSizeConstraint", { MaxTextSize = props.MaxText or 24, Parent = label })
	return label
end

function Ui.button(text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local p = {
		Text = text,
		Font = Ui.Font,
		TextScaled = true,
		TextColor3 = Ui.Colors.text,
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(140, 40),
	}
	for k, v in (props or {}) :: { [string]: any } do
		if k ~= "MaxText" then
			p[k] = v
		end
	end
	local button = Ui.new("TextButton", p, { Ui.corner(10), Ui.stroke(nil, 2), Ui.padding(6) })
	Ui.new("UITextSizeConstraint", { MaxTextSize = (props and props.MaxText) or 22, Parent = button })
	Ui.new("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = button,
	})
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

-- a centred window with a title bar and close button; returns window and its content frame
function Ui.window(parent: Instance, title: string, size: UDim2, onClose: () -> ()): (Frame, Frame)
	local window = Ui.new("Frame", {
		Name = title,
		Size = size,
		Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Ui.Colors.panel,
		Visible = false,
		Parent = parent,
	}, { Ui.corner(16), Ui.stroke(Color3.fromRGB(12, 10, 25), 3) })
	Ui.text({
		Text = title,
		Size = UDim2.new(1, -80, 0, 40),
		Position = UDim2.fromOffset(18, 8),
		MaxText = 32,
		Parent = window,
	})
	Ui.button("X", Ui.Colors.red, onClose, {
		Size = UDim2.fromOffset(40, 40),
		Position = UDim2.new(1, -50, 0, 8),
		Parent = window,
	})
	local content = Ui.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -24, 1, -64),
		Position = UDim2.fromOffset(12, 54),
		BackgroundTransparency = 1,
		Parent = window,
	})
	return window, content
end

-- a ViewportFrame showing a unit or enemy model
function Ui.viewport(key: string, props: { [string]: any }?): ViewportFrame
	local p = {
		BackgroundColor3 = Color3.fromRGB(80, 75, 140),
		BackgroundTransparency = 0.3,
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.5, -1, 0.7),
	}
	for k, v in (props or {}) :: { [string]: any } do
		p[k] = v
	end
	local vp = Ui.new("ViewportFrame", p, { Ui.corner(10) })
	local model = ModelFactory.build(key, 1, true)
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local dist = math.max(size.X, size.Y, size.Z) * 1.45 + 1
	local camera = Ui.new("Camera", {
		FieldOfView = 40,
		CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.45, dist * 0.3, -dist), cf.Position),
		Parent = vp,
	})
	vp.CurrentCamera = camera
	return vp
end

-- a rotated square used as a currency icon
function Ui.gemIcon(color: Color3, size: number, parent: Instance?): Frame
	local holder = Ui.new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
	Ui.new("Frame", {
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		BackgroundColor3 = color,
		Parent = holder,
	}, { Ui.corner(3), Ui.stroke(Color3.new(1, 1, 1), 1.5) })
	return holder
end

function Ui.clear(frame: Instance)
	for _, child in frame:GetChildren() do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
end

local toastHolder: Frame? = nil
function Ui.toast(message: string, color: Color3?)
	if not toastHolder then
		local gui = Ui.new("ScreenGui", {
			Name = "Toasts",
			ResetOnSpawn = false,
			DisplayOrder = 50,
			Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
		})
		toastHolder = Ui.new("Frame", {
			Size = UDim2.new(0, 420, 1, -140),
			Position = UDim2.new(0.5, 0, 0, 90),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Parent = gui,
		}, { Ui.list(Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center) })
	end
	local toast = Ui.new("TextLabel", {
		Text = message,
		Font = Ui.Font,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = color or Ui.Colors.panelDark,
		Size = UDim2.fromOffset(400, 38),
		Parent = toastHolder,
	}, { Ui.corner(10), Ui.stroke(nil, 2), Ui.padding(6) })
	Ui.new("UITextSizeConstraint", { MaxTextSize = 20, Parent = toast })
	task.delay(2.6, function()
		local tween = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

function Ui.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return Ui
