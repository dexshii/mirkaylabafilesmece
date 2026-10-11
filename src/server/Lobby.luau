-- Decorates the lobby (the floor and spawn are in the place file): a castle, unit statues and a welcome sign.
local Shared = game.ReplicatedStorage.Shared
local ModelFactory = require(Shared.ModelFactory)
local Units = require(Shared.Units)

local Lobby = {}

function Lobby.spawnCFrame(): CFrame
	return CFrame.new(0, 5, 0)
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function Lobby.build()
	local lobby = workspace:FindFirstChild("Lobby") or Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.Parent = workspace

	-- a castle behind the spawn
	local wall = Color3.fromRGB(240, 235, 225)
	part(lobby, Vector3.new(60, 26, 20), CFrame.new(0, 13, 60), wall, Enum.Material.Brick)
	for _, x in { -34, 34 } do
		local t = part(lobby, Vector3.new(36, 14, 14), CFrame.new(x, 18, 60) * CFrame.Angles(0, 0, math.rad(90)), wall, Enum.Material.Brick)
		t.Shape = Enum.PartType.Cylinder
		part(lobby, Vector3.new(16, 8, 16), CFrame.new(x, 40, 60), Color3.fromRGB(220, 50, 50))
	end
	part(lobby, Vector3.new(14, 18, 1), CFrame.new(0, 9, 49.6), Color3.fromRGB(120, 70, 40), Enum.Material.Wood)
	local star = part(lobby, Vector3.new(8, 8, 1), CFrame.new(0, 34, 49.4) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 215, 40), Enum.Material.Neon)
	star.CanCollide = false

	-- the sign
	local sign = part(lobby, Vector3.new(30, 8, 1), CFrame.new(0, 30, 49), Color3.fromRGB(60, 40, 120))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 90)
	label.Text = "STAR KINGDOM DEFENSE"
	label.Parent = gui

	-- every unit as a statue on a plinth, in a ring around the spawn
	local count = #Units.List
	for i, def in Units.List do
		local angle = math.pi * 0.15 + (i - 1) / (count - 1) * math.pi * 0.7
		local pos = Vector3.new(math.cos(angle) * -42, 0, math.sin(angle) * -42 + 10)
		part(lobby, Vector3.new(6, 2, 6), CFrame.new(pos + Vector3.new(0, 1, 0)), Color3.fromRGB(200, 200, 210), Enum.Material.Marble)
		local model = ModelFactory.build(def.id, 1.3, true)
		model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 2, 0), Vector3.new(0, 2, 0)))
		model.Parent = lobby
	end
end

return Lobby
