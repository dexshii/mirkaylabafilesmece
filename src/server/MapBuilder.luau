-- Builds a campaign map out of parts at an arena origin: the play field (tiled ground, a curbed path, themed
-- landmarks), the scenery around it, the enemy portal and your castle.
local Maps = require(game.ReplicatedStorage.Shared.Maps)

local MapBuilder = {}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- ============================================================ part helpers

type Opts = { [string]: any }

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	local o = opts or {}
	local p: BasePart
	if o.wedge then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if o.shape == "Ball" then
			-- a sphere mesh stretches to the part's size; Ball parts are always perfect spheres
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = q
		elseif o.shape == "Cylinder" then
			q.Shape = Enum.PartType.Cylinder
		end
		p = q
	end
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	p.CanCollide = o.collide == true
	p.CanQuery = o.query == true
	p.CanTouch = false
	p.CastShadow = o.shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.name then
		p.Name = o.name
	end
	p.Parent = parent
	return p
end

local function ball(parent: Instance, size: Vector3, pos: Vector3, color: Color3, opts: Opts?): BasePart
	local o = opts or {}
	o.shape = "Ball"
	return part(parent, size, CFrame.new(pos), color, o)
end

-- a vertical cylinder standing on `base`
local function pillar(parent: Instance, height: number, diameter: number, base: Vector3, color: Color3, opts: Opts?): BasePart
	local o = opts or {}
	o.shape = "Cylinder"
	return part(parent, Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, o)
end

local function emitter(parent: Instance, texture: string, color: Color3, props: Opts?)
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.6
	e.Rate = 6
	e.Lifetime = NumberRange.new(1.5, 2.5)
	e.Speed = NumberRange.new(1, 3)
	e.Size = NumberSequence.new(1.2, 0)
	e.Transparency = NumberSequence.new(0.2, 1)
	for k, v in (props or {}) :: Opts do
		(e :: any)[k] = v
	end
	e.Parent = parent
end

local function light(parent: Instance, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1.5
	l.Shadows = false
	l.Parent = parent
end

local function fire(parent: BasePart, color: Color3, size: number)
	local f = Instance.new("Fire")
	f.Color = color
	f.SecondaryColor = color:Lerp(Color3.new(1, 1, 0.4), 0.5)
	f.Size = size
	f.Heat = 6
	f.Parent = parent
end

local function signFace(p: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.PixelsPerStud = 20
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
end

local function shade(c: Color3, amount: number): Color3
	if amount >= 0 then
		return c:Lerp(Color3.new(1, 1, 1), amount)
	end
	return c:Lerp(Color3.new(0, 0, 0), -amount)
end

-- ============================================================ decorations

local WHITE = Color3.fromRGB(250, 250, 250)

local decor: { [string]: (Instance, Vector3, number, Random) -> () } = {}

decor.tree = function(f, p, s, rng)
	pillar(f, 6 * s, 1.6 * s, p, Color3.fromRGB(125, 85, 50), { material = Enum.Material.Wood, collide = true })
	local green = Color3.fromRGB(50, 165, 65):Lerp(Color3.fromRGB(90, 200, 70), rng:NextNumber())
	ball(f, Vector3.new(7, 6, 7) * s, p + Vector3.new(0, 7 * s, 0), green, { material = Enum.Material.Grass })
	ball(f, Vector3.new(5, 4.5, 5) * s, p + Vector3.new(0, 9.6 * s, 0), shade(green, 0.12), { material = Enum.Material.Grass })
end

decor.mushroom = function(f, p, s, rng)
	local caps = { Color3.fromRGB(230, 50, 50), Color3.fromRGB(60, 130, 235), Color3.fromRGB(250, 170, 40), Color3.fromRGB(60, 190, 80) }
	local cap = caps[rng:NextInteger(1, #caps)]
	pillar(f, 7 * s, 3 * s, p, Color3.fromRGB(250, 238, 210), { collide = true })
	ball(f, Vector3.new(11, 6, 11) * s, p + Vector3.new(0, 8 * s, 0), cap, { collide = true })
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		ball(f, Vector3.new(2.2, 1.4, 2.2) * s, p + Vector3.new(math.cos(a) * 3.6 * s, 9.4 * s, math.sin(a) * 3.6 * s), WHITE)
	end
	ball(f, Vector3.new(2.6, 1.2, 2.6) * s, p + Vector3.new(0, 11 * s, 0), WHITE)
end

decor.pipe = function(f, p, s, _rng)
	local green = Color3.fromRGB(40, 180, 60)
	pillar(f, 6 * s, 6 * s, p, green, { collide = true, material = Enum.Material.Plastic })
	pillar(f, 2 * s, 7.4 * s, p + Vector3.new(0, 6 * s, 0), shade(green, 0.1), { collide = true, material = Enum.Material.Plastic })
	pillar(f, 0.2, 5.6 * s, p + Vector3.new(0, 8 * s, 0), Color3.fromRGB(10, 40, 15))
end

decor.qblock = function(f, p, s, rng)
	local b = part(f, Vector3.new(5, 5, 5) * s, CFrame.new(p + Vector3.new(0, rng:NextNumber(11, 15), 0)), Color3.fromRGB(255, 200, 40), { material = Enum.Material.SmoothPlastic })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		signFace(b, face, "?", Color3.new(1, 1, 1))
	end
	light(b, Color3.fromRGB(255, 220, 120), 10, 0.8)
end

decor.bush = function(f, p, s, rng)
	local green = Color3.fromRGB(60, 175, 70)
	for i = 1, 3 do
		ball(f, Vector3.new(4, 3.4, 4) * s * rng:NextNumber(0.8, 1.2), p + Vector3.new((i - 2) * 2.4 * s, 1.4 * s, rng:NextNumber(-1, 1)), shade(green, (i - 2) * 0.08), { material = Enum.Material.Grass })
	end
	ball(f, Vector3.new(0.9, 0.9, 0.9), p + Vector3.new(0, 3 * s, -1.6 * s), Color3.fromRGB(255, 90, 140))
end

decor.flowers = function(f, p, _s, rng)
	local colors = { Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 230, 70), Color3.fromRGB(150, 110, 255), WHITE }
	for _ = 1, 5 do
		local q = p + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		pillar(f, 1.2, 0.2, q, Color3.fromRGB(60, 150, 60), { shadow = false })
		ball(f, Vector3.new(0.8, 0.5, 0.8), q + Vector3.new(0, 1.3, 0), colors[rng:NextInteger(1, #colors)], { shadow = false })
	end
end

decor.coin = function(f, p, _s, rng)
	local c = part(f, Vector3.new(0.5, 3, 3), CFrame.new(p + Vector3.new(0, rng:NextNumber(4, 7), 0)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(255, 210, 40), { shape = "Cylinder", material = Enum.Material.Metal })
	light(c, Color3.fromRGB(255, 220, 80), 6, 0.6)
end

decor.palm = function(f, p, s, rng)
	local lean = rng:NextNumber(-0.25, 0.25)
	local top = p
	for i = 0, 5 do
		local seg = p + Vector3.new(lean * i * i * 0.4 * s, (i + 0.5) * 2 * s, 0)
		part(f, Vector3.new(1.3, 2.1, 1.3) * s, CFrame.new(seg) * CFrame.Angles(0, i, lean), Color3.fromRGB(150, 110, 70), { material = Enum.Material.Wood })
		top = seg
	end
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		part(f, Vector3.new(0.4, 1.2, 6) * s, CFrame.new(top + Vector3.new(0, 1 * s, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -3 * s) * CFrame.Angles(math.rad(-25), 0, 0), Color3.fromRGB(70, 160, 60), { wedge = true, material = Enum.Material.Grass })
	end
	ball(f, Vector3.new(1, 1, 1) * s, top + Vector3.new(0.6 * s, 0.2, 0), Color3.fromRGB(120, 80, 40))
end

decor.cactus = function(f, p, s, _rng)
	local green = Color3.fromRGB(70, 155, 75)
	pillar(f, 8 * s, 2 * s, p, green, { collide = true, material = Enum.Material.Grass })
	ball(f, Vector3.new(2, 2, 2) * s, p + Vector3.new(0, 8 * s, 0), green, { material = Enum.Material.Grass })
	pillar(f, 3 * s, 1.3 * s, p + Vector3.new(1.8 * s, 3.5 * s, 0), green, { material = Enum.Material.Grass })
	part(f, Vector3.new(1.8, 1.2, 1.2) * s, CFrame.new(p + Vector3.new(1.1 * s, 3.5 * s, 0)), green, { material = Enum.Material.Grass })
	ball(f, Vector3.new(1.3, 1.3, 1.3) * s, p + Vector3.new(1.8 * s, 6.5 * s, 0), green, { material = Enum.Material.Grass })
	ball(f, Vector3.new(0.9, 0.9, 0.9) * s, p + Vector3.new(0, 9 * s, 0), Color3.fromRGB(255, 120, 170))
end

decor.pyramid = function(f, p, s, _rng)
	local sand = Color3.fromRGB(220, 185, 110)
	for i = 0, 5 do
		local w = (24 - i * 4) * s
		part(f, Vector3.new(w, 3 * s, w), CFrame.new(p + Vector3.new(0, (1.5 + i * 3) * s, 0)), shade(sand, -i * 0.03), { material = Enum.Material.Sandstone, collide = true })
	end
	part(f, Vector3.new(3, 4, 0.4) * s, CFrame.new(p + Vector3.new(0, 2 * s, -12.1 * s)), Color3.fromRGB(40, 30, 20))
end

decor.rock = function(f, p, s, rng)
	local c = Color3.fromRGB(150, 140, 130)
	ball(f, Vector3.new(5, 3.5, 4.5) * s * rng:NextNumber(0.7, 1.3), p + Vector3.new(0, 1 * s, 0), c, { material = Enum.Material.Rock, collide = true })
	ball(f, Vector3.new(3, 2, 3) * s, p + Vector3.new(2.2 * s, 0.6 * s, 1 * s), shade(c, -0.1), { material = Enum.Material.Rock })
end

decor.oasis = function(f, p, s, rng)
	pillar(f, 0.3, 16 * s, p + Vector3.new(0, -0.05, 0), Color3.fromRGB(60, 160, 220), { material = Enum.Material.Glass, transparency = 0.25 })
	pillar(f, 0.2, 19 * s, p + Vector3.new(0, -0.1, 0), Color3.fromRGB(110, 170, 80), { material = Enum.Material.Grass })
	decor.palm(f, p + Vector3.new(7 * s, 0, 4 * s), s, rng)
end

decor.pine = function(f, p, s, _rng)
	pillar(f, 3 * s, 1.2 * s, p, Color3.fromRGB(100, 70, 45), { material = Enum.Material.Wood, collide = true })
	for i = 0, 2 do
		local w = (7 - i * 1.9) * s
		local y = (3.2 + i * 2.6) * s
		part(f, Vector3.new(w, 3 * s, w), CFrame.new(p + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(45 * i), 0), Color3.fromRGB(35, 105, 70), { material = Enum.Material.Grass })
		part(f, Vector3.new(w * 0.95, 0.7 * s, w * 0.95), CFrame.new(p + Vector3.new(0, y + 1.6 * s, 0)) * CFrame.Angles(0, math.rad(45 * i), 0), WHITE, { material = Enum.Material.Snow })
	end
end

decor.snowman = function(f, p, s, _rng)
	ball(f, Vector3.new(5, 5, 5) * s, p + Vector3.new(0, 2.3 * s, 0), WHITE, { material = Enum.Material.Snow, collide = true })
	ball(f, Vector3.new(3.6, 3.6, 3.6) * s, p + Vector3.new(0, 6 * s, 0), WHITE, { material = Enum.Material.Snow })
	ball(f, Vector3.new(2.6, 2.6, 2.6) * s, p + Vector3.new(0, 8.6 * s, 0), WHITE, { material = Enum.Material.Snow })
	part(f, Vector3.new(0.5, 0.5, 1.6) * s, CFrame.new(p + Vector3.new(0, 8.6 * s, -1.6 * s)), Color3.fromRGB(255, 130, 30), { wedge = true })
	pillar(f, 1.6 * s, 2 * s, p + Vector3.new(0, 9.6 * s, 0), Color3.fromRGB(30, 30, 35))
	pillar(f, 0.3 * s, 3 * s, p + Vector3.new(0, 9.6 * s, 0), Color3.fromRGB(30, 30, 35))
	part(f, Vector3.new(4, 0.6, 0.8) * s, CFrame.new(p + Vector3.new(0, 7.4 * s, 0)), Color3.fromRGB(220, 40, 40))
end

decor.igloo = function(f, p, s, _rng)
	ball(f, Vector3.new(14, 14, 14) * s, p, Color3.fromRGB(235, 245, 255), { material = Enum.Material.Ice, collide = true })
	part(f, Vector3.new(4, 5, 3) * s, CFrame.new(p + Vector3.new(0, 2.5 * s, -6.5 * s)), Color3.fromRGB(225, 238, 255), { material = Enum.Material.Ice })
	part(f, Vector3.new(2.6, 3.6, 0.3) * s, CFrame.new(p + Vector3.new(0, 1.8 * s, -8.05 * s)), Color3.fromRGB(30, 40, 60))
end

decor.crystal = function(f, p, s, rng)
	for i = 1, 4 do
		local h = rng:NextNumber(4, 9) * s
		local c = part(f, Vector3.new(1.6 * s, h, 1.6 * s), CFrame.new(p + Vector3.new(rng:NextNumber(-2, 2) * s, h / 2, rng:NextNumber(-2, 2) * s)) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4)), Color3.fromRGB(130, 210, 255), { material = Enum.Material.Glass, transparency = 0.25 })
		if i == 1 then
			light(c, Color3.fromRGB(120, 200, 255), 12, 1)
		end
	end
end

decor.basalt = function(f, p, s, rng)
	for i = 1, 5 do
		local h = rng:NextNumber(4, 12) * s
		pillar(f, h, 2.6 * s, p + Vector3.new(math.cos(i * 1.3) * 2.4 * s, 0, math.sin(i * 1.3) * 2.4 * s), Color3.fromRGB(45, 38, 40), { material = Enum.Material.Basalt, collide = true })
	end
end

decor.lavapool = function(f, p, s, _rng)
	pillar(f, 0.6, 18 * s, p + Vector3.new(0, -0.2, 0), Color3.fromRGB(40, 30, 30), { material = Enum.Material.Basalt })
	local lava = pillar(f, 0.4, 15 * s, p + Vector3.new(0, 0, 0), Color3.fromRGB(255, 110, 20), { material = Enum.Material.Neon })
	light(lava, Color3.fromRGB(255, 120, 40), 22, 2)
	emitter(lava, FIRE, Color3.fromRGB(255, 140, 40), { Rate = 4, Speed = NumberRange.new(2, 5), Size = NumberSequence.new(2, 0) })
end

decor.brazier = function(f, p, s, _rng)
	pillar(f, 5 * s, 1.2 * s, p, Color3.fromRGB(60, 50, 50), { material = Enum.Material.Metal, collide = true })
	local bowl = pillar(f, 1.2 * s, 3 * s, p + Vector3.new(0, 5 * s, 0), Color3.fromRGB(80, 70, 70), { material = Enum.Material.Metal })
	fire(bowl, Color3.fromRGB(255, 120, 30), 5 * s)
	light(bowl, Color3.fromRGB(255, 140, 60), 18, 2)
end

decor.ruin = function(f, p, s, rng)
	local brick = Color3.fromRGB(100, 80, 75)
	for i = 0, 3 do
		local h = rng:NextNumber(2, 8) * s
		part(f, Vector3.new(4 * s, h, 2 * s), CFrame.new(p + Vector3.new((i - 1.5) * 4 * s, h / 2, 0)), shade(brick, rng:NextNumber(-0.1, 0.1)), { material = Enum.Material.Brick, collide = true })
	end
end

decor.starpillar = function(f, p, s, _rng)
	pillar(f, 1 * s, 4.4 * s, p, Color3.fromRGB(240, 210, 110), { material = Enum.Material.Metal, collide = true })
	pillar(f, 13 * s, 3 * s, p + Vector3.new(0, 1 * s, 0), Color3.fromRGB(235, 230, 245), { material = Enum.Material.Marble, collide = true })
	pillar(f, 1 * s, 4.4 * s, p + Vector3.new(0, 14 * s, 0), Color3.fromRGB(240, 210, 110), { material = Enum.Material.Metal })
	local star = part(f, Vector3.new(2.4, 2.4, 0.6) * s, CFrame.new(p + Vector3.new(0, 17 * s, 0)) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 220, 60), { material = Enum.Material.Neon })
	light(star, Color3.fromRGB(255, 220, 120), 14, 1.2)
end

decor.torch = function(f, p, s, _rng)
	pillar(f, 6 * s, 0.8 * s, p, Color3.fromRGB(70, 50, 90), { material = Enum.Material.Metal, collide = true })
	local top = ball(f, Vector3.new(1.4, 1.4, 1.4) * s, p + Vector3.new(0, 6.4 * s, 0), Color3.fromRGB(200, 120, 255), { material = Enum.Material.Neon })
	fire(top, Color3.fromRGB(170, 80, 255), 3 * s)
	light(top, Color3.fromRGB(180, 110, 255), 16, 1.8)
end

decor.banner = function(f, p, s, _rng)
	pillar(f, 12 * s, 0.6 * s, p, Color3.fromRGB(230, 200, 100), { material = Enum.Material.Metal, collide = true })
	local cloth = part(f, Vector3.new(4 * s, 6 * s, 0.2), CFrame.new(p + Vector3.new(2.2 * s, 9 * s, 0)), Color3.fromRGB(180, 30, 60), { material = Enum.Material.Fabric })
	signFace(cloth, Enum.NormalId.Front, "★", Color3.fromRGB(255, 220, 60))
	signFace(cloth, Enum.NormalId.Back, "★", Color3.fromRGB(255, 220, 60))
end

-- what each theme scatters on the field: { decoration, weight, scale range }
local fieldDecor = {
	meadow = { { "tree", 5, 0.9, 1.3 }, { "bush", 5, 0.8, 1.2 }, { "flowers", 6, 1, 1 }, { "mushroom", 3, 0.7, 1.1 }, { "pipe", 2, 0.8, 1.1 }, { "qblock", 2, 1, 1 }, { "coin", 3, 1, 1 } },
	desert = { { "cactus", 6, 0.8, 1.3 }, { "rock", 5, 0.7, 1.4 }, { "palm", 3, 0.9, 1.2 }, { "oasis", 1, 0.8, 1 }, { "ruin", 2, 0.8, 1.1 } },
	frost = { { "pine", 7, 0.8, 1.4 }, { "snowman", 2, 0.8, 1.1 }, { "crystal", 4, 0.8, 1.3 }, { "rock", 3, 0.8, 1.2 }, { "igloo", 1, 0.8, 1 } },
	magma = { { "basalt", 5, 0.7, 1.2 }, { "lavapool", 3, 0.7, 1 }, { "brazier", 3, 0.9, 1.1 }, { "ruin", 4, 0.8, 1.2 }, { "rock", 3, 0.8, 1.3 } },
	starcastle = { { "starpillar", 5, 0.8, 1.1 }, { "torch", 5, 0.9, 1.1 }, { "banner", 4, 0.9, 1.1 }, { "coin", 3, 1, 1 } },
}

-- big scenery around the field
local scenery = {
	meadow = function(f: Instance, p: Vector3, s: number, rng: Random)
		if rng:NextNumber() < 0.45 then
			ball(f, Vector3.new(60, 34, 60) * s, p + Vector3.new(0, 4 * s, 0), Color3.fromRGB(80, 180, 80):Lerp(Color3.fromRGB(110, 200, 90), rng:NextNumber()), { material = Enum.Material.Grass })
			ball(f, Vector3.new(4, 6, 2) * s, p + Vector3.new(-4 * s, 14 * s, -27 * s), Color3.fromRGB(20, 20, 20))
			ball(f, Vector3.new(4, 6, 2) * s, p + Vector3.new(4 * s, 14 * s, -27 * s), Color3.fromRGB(20, 20, 20))
		elseif rng:NextNumber() < 0.6 then
			decor.mushroom(f, p, s * 3, rng)
		else
			decor.tree(f, p, s * 3, rng)
		end
	end,
	desert = function(f, p, s, rng)
		if rng:NextNumber() < 0.35 then
			decor.pyramid(f, p, s * 2.5, rng)
		else
			ball(f, Vector3.new(80, 22, 50) * s, p, Color3.fromRGB(235, 200, 125), { material = Enum.Material.Sand })
		end
	end,
	frost = function(f, p, s, rng)
		local h = rng:NextNumber(40, 90) * s
		local w = h * 1.2
		for i = 0, 4 do
			local ww = w * (1 - i * 0.19)
			pillar(f, h / 5 + 0.5, ww, p + Vector3.new(0, i * h / 5, 0), i >= 3 and WHITE or Color3.fromRGB(125, 135, 155), { material = i >= 3 and Enum.Material.Snow or Enum.Material.Rock })
		end
		ball(f, Vector3.new(w * 0.24, h * 0.16, w * 0.24), p + Vector3.new(0, h, 0), WHITE, { material = Enum.Material.Snow })
	end,
	magma = function(f, p, s, rng)
		local h = rng:NextNumber(40, 80) * s
		local w = h * 1.3
		for i = 0, 4 do
			pillar(f, h / 5 + 0.5, w * (1 - i * 0.18), p + Vector3.new(0, i * h / 5, 0), Color3.fromRGB(58, 42, 42):Lerp(Color3.fromRGB(35, 28, 30), i / 4), { material = Enum.Material.Basalt })
		end
		if rng:NextNumber() < 0.5 then
			local crater = pillar(f, 1.5, w * 0.24, p + Vector3.new(0, h + 0.2, 0), Color3.fromRGB(255, 100, 20), { material = Enum.Material.Neon })
			emitter(crater, SMOKE, Color3.fromRGB(80, 70, 70), { Rate = 3, Lifetime = NumberRange.new(6, 9), Speed = NumberRange.new(6, 10), Size = NumberSequence.new(8, 20), Transparency = NumberSequence.new(0.3, 1), LightEmission = 0 })
			light(crater, Color3.fromRGB(255, 120, 40), 40, 3)
		end
	end,
	starcastle = function(f, p, s, rng)
		local wall = Color3.fromRGB(120, 100, 160)
		local h = rng:NextNumber(30, 50) * s
		part(f, Vector3.new(40 * s, h, 12 * s), CFrame.new(p + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), wall, { material = Enum.Material.Brick })
		pillar(f, h + 14 * s, 14 * s, p + Vector3.new(0, 0, 0), shade(wall, 0.1), { material = Enum.Material.Brick })
		local glass = ball(f, Vector3.new(6, 6, 6) * s, p + Vector3.new(0, h + 16 * s, 0), Color3.fromRGB(255, 210, 60), { material = Enum.Material.Neon })
		light(glass, Color3.fromRGB(255, 220, 120), 30, 1.5)
	end,
}

-- ============================================================ portal and castle

local function portal(parent: Instance, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Portal"
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local stone = Color3.fromRGB(70, 45, 100)
	for i = -1, 1, 2 do
		part(m, Vector3.new(3, 18, 3), cf * CFrame.new(i * 8, 9, 0), stone, { material = Enum.Material.Slate, collide = true })
		local orb = ball(m, Vector3.new(2.4, 2.4, 2.4), (cf * CFrame.new(i * 8, 19, 0)).Position, Color3.fromRGB(190, 90, 255), { material = Enum.Material.Neon })
		light(orb, Color3.fromRGB(190, 100, 255), 16, 2)
	end
	part(m, Vector3.new(20, 3, 3), cf * CFrame.new(0, 18, 0), stone, { material = Enum.Material.Slate })
	local swirl = part(m, Vector3.new(13, 15, 0.6), cf * CFrame.new(0, 8.5, 0), Color3.fromRGB(140, 50, 240), { material = Enum.Material.Neon, transparency = 0.25 })
	emitter(swirl, SPARKLE, Color3.fromRGB(220, 160, 255), { Rate = 25, Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(60, 60), Size = NumberSequence.new(1.5, 0) })
	light(swirl, Color3.fromRGB(160, 80, 255), 30, 3)
	m.Parent = parent
end

local function castle(parent: Instance, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Castle"
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local wall = Color3.fromRGB(245, 238, 225)
	local roof = Color3.fromRGB(220, 50, 55)
	local gold = Color3.fromRGB(255, 205, 50)
	part(m, Vector3.new(24, 16, 16), cf * CFrame.new(0, 8, 8), wall, { material = Enum.Material.Brick, collide = true })
	for x = -10, 10, 4 do
		part(m, Vector3.new(2, 2.4, 16), cf * CFrame.new(x, 17.2, 8), wall, { material = Enum.Material.Brick })
	end
	for _, x in { -14, 14 } do
		pillar(m, 24, 8, (cf * CFrame.new(x, 0, 8)).Position, wall, { material = Enum.Material.Brick, collide = true })
		for i = 0, 3 do
			local w = 9 - i * 2.2
			part(m, Vector3.new(w, 2.2, w), cf * CFrame.new(x, 25 + i * 2.1, 8) * CFrame.Angles(0, math.rad(45), 0), roof)
		end
		local orb = ball(m, Vector3.new(1.4, 1.4, 1.4), (cf * CFrame.new(x, 34, 8)).Position, gold, { material = Enum.Material.Neon })
		light(orb, gold, 10, 1)
	end
	-- the keep
	part(m, Vector3.new(12, 10, 10), cf * CFrame.new(0, 21, 10), wall, { material = Enum.Material.Brick })
	for i = 0, 4 do
		local w = 13 - i * 2.6
		part(m, Vector3.new(w, 2.4, w), cf * CFrame.new(0, 27.2 + i * 2.3, 10) * CFrame.Angles(0, math.rad(45), 0), roof)
	end
	local star = part(m, Vector3.new(4, 4, 0.8), cf * CFrame.new(0, 42, 10) * CFrame.Angles(0, 0, math.rad(45)), gold, { material = Enum.Material.Neon })
	light(star, gold, 30, 2)
	emitter(star, SPARKLE, gold, { Rate = 8 })
	-- gate and windows
	part(m, Vector3.new(7, 10, 0.6), cf * CFrame.new(0, 5, -0.1), Color3.fromRGB(110, 65, 35), { material = Enum.Material.Wood })
	part(m, Vector3.new(8, 1, 0.8), cf * CFrame.new(0, 10.3, -0.15), gold, { material = Enum.Material.Metal })
	for _, x in { -7, 7 } do
		part(m, Vector3.new(2.4, 3.6, 0.4), cf * CFrame.new(x, 11, -0.1), Color3.fromRGB(80, 170, 255), { material = Enum.Material.Neon, transparency = 0.2 })
	end
	m.Parent = parent
end

-- ============================================================ build

local function nearPath(waypoints: { { number } }, x: number, z: number, margin: number): boolean
	for i = 1, #waypoints - 1 do
		local a, b = waypoints[i], waypoints[i + 1]
		local dx, dz = b[1] - a[1], b[2] - a[2]
		local len2 = dx * dx + dz * dz
		local t = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / len2, 0, 1)
		local px, pz = a[1] + dx * t - x, a[2] + dz * t - z
		if px * px + pz * pz < margin * margin then
			return true
		end
	end
	return false
end

-- returns the arena model and the world-space path points
function MapBuilder.build(def: Maps.MapDef, origin: Vector3, seed: number): (Model, { Vector3 })
	local theme = def.theme
	local rng = Random.new(seed)
	local arena = Instance.new("Model")
	arena.Name = "Arena_" .. def.id
	local half = Maps.FieldHalf

	-- the play field: tiles (the ground units are placed on) with a little colour variation
	local ground = Instance.new("Model")
	ground.Name = "Ground"
	ground.Parent = arena
	local tile = 30
	local n = math.floor(half * 2 / tile)
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local x = -half + tile * (i + 0.5)
			local z = -half + tile * (j + 0.5)
			local c
			if def.id == "starcastle" then
				c = (i + j) % 2 == 0 and theme.ground or theme.grass2
			else
				c = theme.ground:Lerp(theme.grass2, ((i + j) % 2) * 0.5 + rng:NextNumber(0, 0.25))
			end
			part(ground, Vector3.new(tile, 4, tile), CFrame.new(origin + Vector3.new(x, -2, z)), c, { material = theme.groundMaterial, collide = true, query = true, shadow = false })
		end
	end
	-- the field's edge and the cliff under it
	for _, side in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local along = side[1] == 0
		local size = along and Vector3.new(half * 2 + 6, 1.2, 3) or Vector3.new(3, 1.2, half * 2 + 6)
		part(arena, size, CFrame.new(origin + Vector3.new(side[1] * (half + 1.5), 0.6, side[2] * (half + 1.5))), theme.curb, { material = Enum.Material.Cobblestone, collide = true })
	end
	part(arena, Vector3.new(half * 2 + 6, 14, half * 2 + 6), CFrame.new(origin + Vector3.new(0, -11, 0)), shade(theme.ground, -0.45), { material = Enum.Material.Rock, collide = true })

	-- the world around it
	local world = Instance.new("Folder")
	world.Name = "Scenery"
	world.Parent = arena
	part(world, Vector3.new(1100, 4, 1100), CFrame.new(origin + Vector3.new(0, -16, 0)), shade(theme.grass2, -0.15), { material = theme.groundMaterial, shadow = false, collide = true })
	local makeScenery = scenery[def.id]
	for i = 1, 26 do
		local a = i / 26 * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(200, 420)
		makeScenery(world, origin + Vector3.new(math.cos(a) * r, -14, math.sin(a) * r), rng:NextNumber(0.8, 1.4), rng)
	end
	if def.id == "meadow" or def.id == "desert" or def.id == "frost" then
		for _ = 1, 14 do
			local p = origin + Vector3.new(rng:NextNumber(-450, 450), rng:NextNumber(70, 110), rng:NextNumber(-450, 450))
			for k = 1, 3 do
				ball(world, Vector3.new(26, 14, 18) * rng:NextNumber(0.7, 1.2), p + Vector3.new(k * 12, rng:NextNumber(-2, 3), rng:NextNumber(-4, 4)), WHITE, { shadow = false, transparency = 0.05 })
			end
		end
	end

	-- the path: a road with curbs on both sides and round joints at the corners
	local points: { Vector3 } = {}
	for _, wp in def.waypoints do
		table.insert(points, origin + Vector3.new(wp[1], 0, wp[2]))
	end
	local pathFolder = Instance.new("Folder")
	pathFolder.Name = "Path"
	pathFolder.Parent = arena
	local w = Maps.PathWidth
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		local cf = CFrame.lookAt((a + b) / 2, b)
		part(pathFolder, Vector3.new(w, 0.3, len), cf + Vector3.new(0, 0.12, 0), theme.path, { material = theme.pathMaterial, shadow = false })
		local startTrim = i > 1 and w / 2 or 0
		local endTrim = i < #points - 1 and w / 2 or 0
		local curbLen = math.max(1, len - startTrim - endTrim)
		local curbMid = (startTrim - endTrim) / 2 -- shift toward the untrimmed end (local -Z points at b)
		for _, sideX in { -1, 1 } do
			part(pathFolder, Vector3.new(1.2, 0.7, curbLen), cf * CFrame.new(sideX * (w / 2 + 0.6), 0.3, -curbMid), theme.curb, { material = Enum.Material.Cobblestone, collide = true })
		end
		-- stepping stones across the road
		for d = 3, len - 3, 7 do
			local stone = cf * CFrame.new(rng:NextNumber(-w / 4, w / 4), 0.3, -len / 2 + d)
			part(pathFolder, Vector3.new(rng:NextNumber(1.6, 2.6), 0.12, rng:NextNumber(1.6, 2.6)), stone * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), shade(theme.path, -0.12), { material = theme.pathMaterial, shadow = false })
		end
	end
	-- square road tiles fill the corners, with a curb post on the outside corner
	for i = 2, #points - 1 do
		local inDir = (points[i] - points[i - 1]).Unit
		local outDir = (points[i + 1] - points[i]).Unit
		part(pathFolder, Vector3.new(w + 0.2, 0.32, w + 0.2), CFrame.lookAt(points[i], points[i] + outDir) + Vector3.new(0, 0.13, 0), theme.path, { material = theme.pathMaterial, shadow = false })
		local corner = points[i] + (inDir - outDir) * (w / 2 + 0.6)
		part(pathFolder, Vector3.new(1.6, 1, 1.6), CFrame.new(corner + Vector3.new(0, 0.5, 0)), theme.curb, { material = Enum.Material.Cobblestone, collide = true })
	end

	-- decorations on the field, off the path, more of them toward the edges so the middle stays buildable
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "Decor"
	decoFolder.Parent = arena
	local choices = fieldDecor[def.id]
	local total = 0
	for _, c in choices do
		total += c[2]
	end
	local placed, tries = 0, 0
	while placed < 60 and tries < 900 do
		tries += 1
		local x = rng:NextNumber(-half + 5, half - 5)
		local z = rng:NextNumber(-half + 5, half - 5)
		local edge = math.max(math.abs(x), math.abs(z)) > half - 26
		if not nearPath(def.waypoints, x, z, edge and 12 or 22) and (edge or rng:NextNumber() < 0.25) then
			local roll = rng:NextNumber() * total
			for _, c in choices do
				roll -= c[2]
				if roll <= 0 then
					decor[c[1]](decoFolder, origin + Vector3.new(x, 0, z), rng:NextNumber(c[3], c[4]), rng)
					break
				end
			end
			placed += 1
		end
	end

	local first, second = points[1], points[2]
	local last, beforeLast = points[#points], points[#points - 1]
	local startDir = (second - first).Unit
	local endDir = (last - beforeLast).Unit
	portal(arena, first - startDir * 2, math.atan2(startDir.X, startDir.Z))
	castle(arena, last + endDir * 3, math.atan2(endDir.X, endDir.Z))

	arena.Parent = workspace
	return arena, points
end

return MapBuilder
