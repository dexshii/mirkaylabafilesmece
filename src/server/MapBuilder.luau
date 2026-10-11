-- Builds a campaign map out of parts at an arena origin: ground, path, decorations, enemy portal and your castle.
local Maps = require(game.ReplicatedStorage.Shared.Maps)

local MapBuilder = {}

local function block(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, name: string?): Part
	local p = Instance.new("Part")
	p.Name = name or "Part"
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

local function ball(parent: Instance, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = block(parent, size, CFrame.new(pos), color, material)
	p.Shape = Enum.PartType.Ball
	p.CanCollide = false
	return p
end

local function cylinder(parent: Instance, height: number, diameter: number, pos: Vector3, color: Color3, material: Enum.Material?): Part
	local p = block(parent, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function decoration(parent: Instance, kind: string, pos: Vector3, rng: Random)
	local s = rng:NextNumber(0.8, 1.4)
	if kind == "tree" then
		cylinder(parent, 5 * s, 1.4 * s, pos + Vector3.new(0, 2.5 * s, 0), Color3.fromRGB(120, 80, 45), Enum.Material.Wood)
		ball(parent, Vector3.new(6, 5, 6) * s, pos + Vector3.new(0, 6.5 * s, 0), Color3.fromRGB(50, 160, 60), Enum.Material.Grass)
	elseif kind == "cactus" then
		cylinder(parent, 7 * s, 1.6 * s, pos + Vector3.new(0, 3.5 * s, 0), Color3.fromRGB(70, 150, 70), Enum.Material.Grass)
		cylinder(parent, 2.5 * s, 1 * s, pos + Vector3.new(1.4 * s, 4 * s, 0), Color3.fromRGB(70, 150, 70), Enum.Material.Grass)
	elseif kind == "pine" then
		cylinder(parent, 3 * s, 1 * s, pos + Vector3.new(0, 1.5 * s, 0), Color3.fromRGB(100, 70, 45), Enum.Material.Wood)
		for i = 0, 2 do
			local w = (6 - i * 1.6) * s
			local cone = block(parent, Vector3.new(w, 2.6 * s, w), CFrame.new(pos + Vector3.new(0, (4 + i * 2.2) * s, 0)), Color3.fromRGB(40, 110, 70), Enum.Material.Grass)
			cone.CanCollide = false
			ball(parent, Vector3.new(w * 0.9, 0.8 * s, w * 0.9), pos + Vector3.new(0, (5.3 + i * 2.2) * s, 0), Color3.fromRGB(250, 250, 255), Enum.Material.Snow)
		end
	elseif kind == "lavarock" then
		local r = ball(parent, Vector3.new(5, 3.5, 5) * s, pos + Vector3.new(0, 1.2 * s, 0), Color3.fromRGB(50, 40, 40), Enum.Material.Basalt)
		r.CanCollide = true
		ball(parent, Vector3.new(1.6, 1.6, 1.6) * s, pos + Vector3.new(0, 3 * s, 0), Color3.fromRGB(255, 100, 20), Enum.Material.Neon)
	elseif kind == "pillar" then
		cylinder(parent, 12 * s, 2.4, pos + Vector3.new(0, 6 * s, 0), Color3.fromRGB(230, 225, 240), Enum.Material.Marble)
		block(parent, Vector3.new(3.4, 0.8, 3.4), CFrame.new(pos + Vector3.new(0, 12 * s, 0)), Color3.fromRGB(240, 210, 100), Enum.Material.Metal)
		local star = block(parent, Vector3.new(1.6, 1.6, 0.4), CFrame.new(pos + Vector3.new(0, 13.6 * s, 0)) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 220, 60), Enum.Material.Neon)
		star.CanCollide = false
	end
end

local function castle(parent: Instance, pos: Vector3, yaw: number)
	local m = Instance.new("Model")
	m.Name = "Castle"
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local wall = Color3.fromRGB(240, 235, 225)
	local roof = Color3.fromRGB(220, 50, 50)
	block(m, Vector3.new(16, 10, 12), cf * CFrame.new(0, 5, 4), wall, Enum.Material.Brick)
	for _, x in { -9, 9 } do
		local tower = cylinder(m, 16, 5, (cf * CFrame.new(x, 8, 4)).Position, wall, Enum.Material.Brick)
		tower.Name = "Tower"
		local cone = block(m, Vector3.new(6, 3, 6), cf * CFrame.new(x, 17.5, 4), roof)
		cone.Name = "Roof"
	end
	block(m, Vector3.new(5, 7, 0.6), cf * CFrame.new(0, 3.5, -2.1), Color3.fromRGB(120, 70, 40), Enum.Material.Wood)
	local flag = block(m, Vector3.new(0.3, 8, 0.3), cf * CFrame.new(0, 14, 4), Color3.fromRGB(200, 200, 200), Enum.Material.Metal)
	flag.Name = "Pole"
	local star = block(m, Vector3.new(2.2, 2.2, 0.4), cf * CFrame.new(0, 18.5, 4) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(255, 215, 40), Enum.Material.Neon)
	star.Name = "Star"
	m.Parent = parent
end

local function portal(parent: Instance, pos: Vector3, yaw: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local ring = Color3.fromRGB(60, 30, 90)
	block(parent, Vector3.new(2, 14, 2), cf * CFrame.new(-6, 7, 0), ring, Enum.Material.Slate)
	block(parent, Vector3.new(2, 14, 2), cf * CFrame.new(6, 7, 0), ring, Enum.Material.Slate)
	block(parent, Vector3.new(14, 2, 2), cf * CFrame.new(0, 14, 0), ring, Enum.Material.Slate)
	local swirl = block(parent, Vector3.new(10, 12, 0.4), cf * CFrame.new(0, 7, 0), Color3.fromRGB(150, 60, 255), Enum.Material.Neon)
	swirl.Transparency = 0.35
	swirl.CanCollide = false
end

-- returns the arena model and the world-space path points
function MapBuilder.build(def: Maps.MapDef, origin: Vector3, seed: number): (Model, { Vector3 })
	local theme = def.theme
	local arena = Instance.new("Model")
	arena.Name = "Arena_" .. def.id
	local half = Maps.FieldHalf

	local ground = block(arena, Vector3.new(half * 2, 4, half * 2), CFrame.new(origin + Vector3.new(0, -2, 0)), theme.ground, theme.groundMaterial, "Ground")
	ground:SetAttribute("Placeable", true)
	-- a rim so it reads as a floating island
	block(arena, Vector3.new(half * 2 + 4, 10, half * 2 + 4), CFrame.new(origin + Vector3.new(0, -9, 0)), theme.ground:Lerp(Color3.new(0, 0, 0), 0.45), Enum.Material.Rock, "Rim")

	local points: { Vector3 } = {}
	for _, wp in def.waypoints do
		table.insert(points, origin + Vector3.new(wp[1], 0, wp[2]))
	end

	local pathFolder = Instance.new("Folder")
	pathFolder.Name = "Path"
	pathFolder.Parent = arena
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		local seg = block(pathFolder, Vector3.new(Maps.PathWidth, 0.3, len + Maps.PathWidth), CFrame.lookAt(mid, b) + Vector3.new(0, 0.1, 0), theme.path, theme.pathMaterial, "Segment")
		seg.CanCollide = false
	end

	-- decorations, kept off the path and away from the edges
	local rng = Random.new(seed)
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = arena
	local placed = 0
	local tries = 0
	while placed < 38 and tries < 400 do
		tries += 1
		local x = rng:NextNumber(-half + 6, half - 6)
		local z = rng:NextNumber(-half + 6, half - 6)
		local near = false
		for i = 1, #def.waypoints - 1 do
			local a, b = def.waypoints[i], def.waypoints[i + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len2 = dx * dx + dz * dz
			local t = math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / len2, 0, 1)
			local px, pz = a[1] + dx * t - x, a[2] + dz * t - z
			if px * px + pz * pz < 16 * 16 then
				near = true
				break
			end
		end
		-- keep the middle of each loop free for units: only decorate near the outer edge
		if not near and (math.abs(x) > half - 22 or math.abs(z) > half - 22) then
			decoration(decor, theme.decor, origin + Vector3.new(x, 0, z), rng)
			placed += 1
		end
	end

	local first, second = points[1], points[2]
	local last, beforeLast = points[#points], points[#points - 1]
	local startYaw = math.atan2(-(second - first).X, -(second - first).Z)
	local endDir = (last - beforeLast).Unit
	local endYaw = math.atan2(endDir.X, endDir.Z)
	portal(arena, first, startYaw)
	castle(arena, last + endDir * 4, endYaw)

	-- where players stand when they join the battle: next to the castle
	local spawn = block(arena, Vector3.new(8, 1, 8), CFrame.new(origin + Vector3.new(0, 0.5, 0)), theme.ground, theme.groundMaterial, "PlayerSpot")
	spawn.Transparency = 1
	spawn.CanCollide = false

	arena.Parent = workspace
	return arena, points
end

return MapBuilder
