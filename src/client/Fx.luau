-- Attack and ability effects, drawn only on this client from the server's Fx events.
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Net = require(game.ReplicatedStorage.Shared.Net)
local Animator = require(script.Parent.Animator)

local Fx = {}

local folder: Folder

local function neon(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function fade(part: BasePart, time: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	TweenService:Create(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(part, time + 0.05)
end

-- a flat disc that expands to `radius` and fades
local function ring(pos: Vector3, radius: number, color: Color3, time: number?)
	local disc = neon(Vector3.new(0.3, 1, 1), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
	disc.Transparency = 0.35
	fade(disc, time or 0.35, Vector3.new(0.3, radius * 2, radius * 2))
end

local function burst(pos: Vector3, size: number, color: Color3)
	local ball = neon(Vector3.one * size * 0.4, CFrame.new(pos), color, Enum.PartType.Ball)
	ball.Transparency = 0.2
	fade(ball, 0.25, Vector3.one * size)
end

-- a projectile flying from `from` to `to`, with an optional arc, calling done on arrival
local function projectile(from: Vector3, to: Vector3, color: Color3, size: number, time: number, arc: number, done: (() -> ())?)
	local ball = neon(Vector3.one * size, CFrame.new(from), color, Enum.PartType.Ball)
	local t = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		t += dt / time
		if t >= 1 then
			conn:Disconnect()
			ball:Destroy()
			if done then
				done()
			end
			return
		end
		local p = from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * arc, 0)
		ball.CFrame = CFrame.new(p)
	end)
end

local function beam(a: Vector3, b: Vector3, color: Color3, width: number, time: number)
	local len = (b - a).Magnitude
	if len < 0.1 then
		return
	end
	local part = neon(Vector3.new(width, width, len), CFrame.lookAt((a + b) / 2, b), color)
	part.Transparency = 0.1
	fade(part, time)
end

local function floatingText(pos: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(pos)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 34)
	gui.AlwaysOnTop = true
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.Text = text
	label.Parent = gui
	TweenService:Create(anchor, TweenInfo.new(1.2), { CFrame = CFrame.new(pos + Vector3.new(0, 4, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.3)
end

-- a quick damage number that hops up from the target
local damageCount = 0
local function damageNumber(pos: Vector3, amount: number, color: Color3)
	if damageCount > 40 then
		return -- plenty on screen already
	end
	damageCount += 1
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	local start = pos + Vector3.new(math.random() * 2 - 1, 1, math.random() * 2 - 1)
	anchor.CFrame = CFrame.new(start)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(70, 26)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 140
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
	label.TextStrokeTransparency = 0
	label.Text = amount >= 1000 and string.format("%.1fk", amount / 1000) or tostring(amount)
	label.Parent = gui
	TweenService:Create(anchor, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(start + Vector3.new(0, 3, 0)) }):Play()
	TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.75, function()
		anchor:Destroy()
		damageCount -= 1
	end)
end

local handlers: { [string]: (any) -> () } = {
	bolt = function(p)
		projectile(p.from, p.to, p.color, 0.6, 0.15, 0, function()
			burst(p.to, 1.5, p.color)
		end)
	end,
	bonk = function(p)
		burst(p.to, 2.5, p.color:Lerp(Color3.new(1, 1, 1), 0.4))
		ring(p.to - Vector3.new(0, 1.5, 0), 2, Color3.new(1, 1, 1), 0.2)
	end,
	lob = function(p)
		projectile(p.from, p.to, p.color, 1.1, 0.4, 5, function()
			burst(p.to, (p.radius or 4) * 1.2, Color3.fromRGB(255, 160, 40))
			ring(p.to - Vector3.new(0, 1.5, 0), p.radius or 4, p.color, 0.3)
		end)
	end,
	slam = function(p)
		ring(p.ground + Vector3.new(0, 0.3, 0), p.radius or 10, p.color, 0.45)
		ring(p.ground + Vector3.new(0, 0.4, 0), (p.radius or 10) * 0.6, Color3.new(1, 1, 1), 0.3)
	end,
	cone = function(p)
		local dir = (p.to - p.from)
		for i = 1, 7 do
			local spread = Vector3.new(math.random() - 0.5, (math.random() - 0.5) * 0.4, math.random() - 0.5) * dir.Magnitude * 0.5
			projectile(p.from, p.to + spread, i % 2 == 0 and Color3.fromRGB(255, 200, 40) or p.color, 1.4, 0.25 + i * 0.02, 0, nil)
		end
	end,
	zap = function(p)
		local points = { p.from }
		for _, c in p.chain or { p.to } do
			table.insert(points, c)
		end
		for i = 1, #points - 1 do
			beam(points[i], points[i + 1], p.color, 0.35, 0.18)
			burst(points[i + 1], 2, p.color)
		end
	end,
	pop = function(p)
		burst(p.to, p.boss and 12 or 3, p.color)
	end,
	summon = function(p)
		ring(p.to, p.radius or 8, p.color, 0.6)
	end,
	shock = function(p)
		ring(p.to, p.radius or 18, p.color, 0.7)
		ring(p.to + Vector3.new(0, 0.2, 0), (p.radius or 18) * 0.5, Color3.new(1, 1, 1), 0.5)
	end,
	shield = function(p)
		local bubble = neon(Vector3.one * (p.radius or 6) * 2, CFrame.new(p.to + Vector3.new(0, 3, 0)), p.color, Enum.PartType.Ball)
		bubble.Material = Enum.Material.ForceField
		fade(bubble, p.dur or 2)
	end,
	placed = function(p)
		ring(p.to, p.radius or 3, p.color, 0.4)
	end,
	leak = function(p)
		burst(p.to, 6, p.color)
		floatingText(p.to + Vector3.new(0, 4, 0), "OUCH!", p.color)
	end,
	cash = function(p)
		floatingText(p.to, "+$" .. tostring(p.amount or 0), p.color)
	end,
}

-- extra chain-lightning arcs from the Chain Reaction trait, on any attack style
local function chainArcs(p)
	if p.style ~= "zap" and p.chain then
		for i = 1, #p.chain - 1 do
			beam(p.chain[i], p.chain[i + 1], Color3.fromRGB(120, 220, 255), 0.25, 0.18)
		end
	end
end

function Fx.start()
	folder = Instance.new("Folder")
	folder.Name = "ClientFx"
	folder.Parent = workspace
	-- the server sends each frame's effects as one list
	Net.ev("Fx").OnClientEvent:Connect(function(list)
		local numbers = 0
		for _, p in list do
			local handler = handlers[p.style]
			if handler then
				handler(p)
			end
			chainArcs(p)
			if p.tower then
				Animator.attack(p.tower)
			end
			-- at most a few damage numbers per frame, so big fights stay smooth
			if p.dmg and p.to and numbers < 6 then
				numbers += 1
				damageNumber(p.to, p.dmg, p.color or Color3.new(1, 1, 1))
			end
		end
	end)
end

return Fx
