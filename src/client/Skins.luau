-- Puts SM64 meshes on units, enemies, statues and UI models when ReplicatedStorage.SM64Models exists (a private
-- build made with tools/sm64_import --luau). Each mesh is built once on this client with EditableMesh and
-- EditableImage, then cloned onto every model whose "SkinKey" attribute names it; the model's own parts are hidden.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local Skins = {}

-- why each model that failed did fail (shown in the admin panel)
Skins.failures = {} :: { [string]: string }

-- found in start(): the folder is several MB, so it often replicates after this script starts
local folder: Instance? = nil
-- "mesh" (EditableMesh, textured) or "parts" (triangles made of wedges; works everywhere). A model whose mesh
-- can't be built falls back to parts on its own.
Skins.mode = "mesh"
local templates: { [string]: any } = {}
local building: { [string]: BindableEvent } = {}

local function decode64(s: string): buffer
	local map = {}
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, 64 do
		map[string.byte(chars, i)] = i - 1
	end
	local clean = s:gsub("=", "")
	local n = #clean
	local out = buffer.create(n * 3 // 4)
	local o = 0
	for i = 1, n - 3, 4 do
		local a, b, c, d = map[string.byte(clean, i)], map[string.byte(clean, i + 1)], map[string.byte(clean, i + 2)], map[string.byte(clean, i + 3)]
		local v = a * 262144 + b * 4096 + c * 64 + d
		buffer.writeu8(out, o, v // 65536)
		buffer.writeu8(out, o + 1, (v // 256) % 256)
		buffer.writeu8(out, o + 2, v % 256)
		o += 3
	end
	local rest = n % 4
	if rest >= 2 then
		local i = n - rest + 1
		local a, b = map[string.byte(clean, i)], map[string.byte(clean, i + 1)]
		local c = rest == 3 and map[string.byte(clean, i + 2)] or 0
		local v = a * 262144 + b * 4096 + c * 64
		buffer.writeu8(out, o, v // 65536)
		if rest == 3 then
			buffer.writeu8(out, o + 1, (v // 256) % 256)
		end
	end
	return out
end

Skins.decode64 = decode64

function Skins.available(): boolean
	return folder ~= nil
end

function Skins.displayName(key: string): string?
	local names = folder and folder:FindFirstChild("Names")
	if names and names:IsA("ModuleScript") then
		local ok, t = pcall(require, names)
		if ok and type(t) == "table" then
			return t[key]
		end
	end
	return nil
end

local function loadData(key: string): any
	local module = folder and (folder:FindFirstChild(key) or folder:WaitForChild(key, 5))
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	return require(module) :: any
end

-- draws triangle a-b-c with two thin wedges
local function triangle(a: Vector3, b: Vector3, c: Vector3, color: Color3, parent: Instance)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-5 or bc.Magnitude < 1e-5 then
		return
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for side = 1, 2 do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.CanTouch = false
		w.CanQuery = false
		w.CastShadow = false
		w.Massless = true
		w.Material = Enum.Material.SmoothPlastic
		w.Color = color
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		if side == 1 then
			w.Size = Vector3.new(0.02, height, math.abs(ab:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
		else
			w.Size = Vector3.new(0.02, height, math.abs(ac:Dot(back)))
			w.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		end
		w.Parent = parent
	end
end

-- the SM64 model as a Model of wedge triangles coloured from its texture (no EditableMesh needed)
local function buildParts(key: string, data: any): Model?
	local pos = decode64(data.positions)
	local uvs = decode64(data.uvs)
	local img = decode64(data.image)
	local w, h = data.width, data.height
	local count = buffer.len(pos) // 12
	local function texel(u: number, v: number): (number, number, number, number)
		local x = math.clamp(math.floor(u * w), 0, w - 1)
		local y = math.clamp(math.floor(v * h), 0, h - 1)
		local o = (y * w + x) * 4
		return buffer.readu8(img, o), buffer.readu8(img, o + 1), buffer.readu8(img, o + 2), buffer.readu8(img, o + 3)
	end
	local points, uv = table.create(count), table.create(count)
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	for i = 0, count - 1 do
		local p = Vector3.new(buffer.readf32(pos, i * 12), buffer.readf32(pos, i * 12 + 4), buffer.readf32(pos, i * 12 + 8))
		points[i + 1] = p
		uv[i + 1] = Vector2.new(buffer.readf32(uvs, i * 8), buffer.readf32(uvs, i * 8 + 4))
		minV = minV:Min(p)
		maxV = maxV:Max(p)
	end
	local center = (minV + maxV) / 2
	local model = Instance.new("Model")
	model.Name = "SM64"
	local budget = 1600 -- triangles per model, so crowds of enemies stay smooth
	local tris = 0
	-- samples the texture over a triangle; splits it while its colours differ a lot (eyes, logos, buttons)
	local function draw(a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, depth: number)
		local bary = { { 1 / 3, 1 / 3 }, { 0.7, 0.15 }, { 0.15, 0.7 }, { 0.15, 0.15 }, { 0.45, 0.45 }, { 0.45, 0.1 }, { 0.1, 0.45 } }
		local r, g, bl, al, n = 0, 0, 0, 0, 0
		local lo, hi = math.huge, -math.huge
		for _, q in bary do
			local t = ua * q[1] + ub * q[2] + uc * (1 - q[1] - q[2])
			local cr, cg, cb, ca = texel(t.X, t.Y)
			r += cr
			g += cg
			bl += cb
			al += ca
			n += 1
			local lum = cr * 0.3 + cg * 0.59 + cb * 0.11
			lo = math.min(lo, lum)
			hi = math.max(hi, lum)
		end
		if al / n < 100 then
			return -- cut-out texels (transparent)
		end
		local area = (b - a):Cross(c - a).Magnitude
		if depth < 3 and hi - lo > 45 and area > 0.02 and tris < budget then
			local ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
			local uab, ubc, uca = (ua + ub) / 2, (ub + uc) / 2, (uc + ua) / 2
			draw(a, ab, ca, ua, uab, uca, depth + 1)
			draw(ab, b, bc, uab, ub, ubc, depth + 1)
			draw(ca, bc, c, uca, ubc, uc, depth + 1)
			draw(ab, bc, ca, uab, ubc, uca, depth + 1)
			return
		end
		tris += 1
		triangle(a - center, b - center, c - center, Color3.fromRGB(r / n, g / n, bl / n), model)
	end
	for t = 0, count // 3 - 1 do
		local i = t * 3 + 1
		draw(points[i], points[i + 1], points[i + 2], uv[i], uv[i + 1], uv[i + 2], 0)
	end
	if #model:GetChildren() == 0 then
		return nil
	end
	-- an invisible box the size of the model, used to scale and weld it like a MeshPart
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Transparency = 1
	box.Anchored = true
	box.CanCollide = false
	box.CanTouch = false
	box.CanQuery = false
	box.Massless = true
	box.Size = (maxV - minV):Max(Vector3.one * 0.05)
	box.CFrame = CFrame.new()
	box.Parent = model
	model.PrimaryPart = box
	for _, d in model:GetChildren() do
		if d ~= box and d:IsA("BasePart") then
			d.Anchored = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = box
			weld.Part1 = d
			weld.Parent = d
		end
	end
	return model
end

local function buildMesh(key: string, data: any): MeshPart?
	local pos = decode64(data.positions)
	local uvs = decode64(data.uvs)
	local count = buffer.len(pos) // 12
	-- centre the mesh on its bounding box so the MeshPart's position is the mesh's centre
	local minV, maxV = Vector3.one * math.huge, -Vector3.one * math.huge
	local points = table.create(count)
	for i = 0, count - 1 do
		local p = Vector3.new(buffer.readf32(pos, i * 12), buffer.readf32(pos, i * 12 + 4), buffer.readf32(pos, i * 12 + 8))
		points[i + 1] = p
		minV = minV:Min(p)
		maxV = maxV:Max(p)
	end
	local center = (minV + maxV) / 2
	local mesh = AssetService:CreateEditableMesh({})
	local ids: { [string]: number } = {}
	local faces = 0
	for t = 0, count // 3 - 1 do
		local a, b, c = points[t * 3 + 1], points[t * 3 + 2], points[t * 3 + 3]
		-- skip zero-area triangles: they make mesh creation fail
		if (b - a):Cross(c - a).Magnitude > 1e-6 then
			local v, u = {}, {}
			for k = 0, 2 do
				local i = t * 3 + k
				local p = points[i + 1] - center
				local vkey = string.format("%.4f,%.4f,%.4f", p.X, p.Y, p.Z)
				local id = ids[vkey]
				if not id then
					id = mesh:AddVertex(p)
					ids[vkey] = id
				end
				v[k + 1] = id
				u[k + 1] = mesh:AddUV(Vector2.new(buffer.readf32(uvs, i * 8), buffer.readf32(uvs, i * 8 + 4)))
			end
			if v[1] ~= v[2] and v[2] ~= v[3] and v[1] ~= v[3] then
				local face = mesh:AddTriangle(v[1], v[2], v[3])
				mesh:SetFaceUVs(face, u)
				faces += 1
			end
		end
	end
	if faces == 0 then
		warn("[SM64] " .. key .. " has no usable triangles")
		return nil
	end
	-- no collision geometry: these are only visuals, and computing hulls fails on SM64's flat parts (eyes, billboards)
	local content = Content.fromObject(mesh)
	local ok, created = pcall(function()
		return AssetService:CreateMeshPartAsync(content, { CollisionFidelity = Enum.CollisionFidelity.Box, RenderFidelity = Enum.RenderFidelity.Precise })
	end)
	if not ok then
		Skins.failures[key] = "mesh with Box collision: " .. tostring(created)
		created = AssetService:CreateMeshPartAsync(content)
	end
	local part = created :: MeshPart
	local image = AssetService:CreateEditableImage({ Size = Vector2.new(data.width, data.height) })
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(data.width, data.height), decode64(data.image))
	part.TextureContent = Content.fromObject(image)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.Name = "SM64"
	return part
end

type Template = MeshPart | Model

local function build(key: string): Template?
	local data = loadData(key)
	if not data then
		return nil
	end
	if data.alias then
		return Skins.template(data.alias)
	end
	if Skins.mode == "mesh" then
		local ok, result = pcall(buildMesh, key, data)
		if ok and result then
			return result
		end
		Skins.failures[key] = "mesh failed (" .. tostring(result) .. "), using parts"
		warn("[SM64] " .. key .. ": " .. Skins.failures[key])
	end
	return buildParts(key, data)
end

-- the mesh for a key, built on first use (yields); nil when there is none
function Skins.template(key: string): (MeshPart | Model)?
	local cached = templates[key]
	if cached ~= nil then
		return cached or nil
	end
	if building[key] then
		building[key].Event:Wait()
		return templates[key] or nil
	end
	local done = Instance.new("BindableEvent")
	building[key] = done
	local ok, result = pcall(build, key)
	if not ok then
		Skins.failures[key] = tostring(result)
		warn("[SM64] could not build " .. key .. ": " .. tostring(result))
	elseif result then
		print("[SM64] built " .. key)
	end
	templates[key] = ok and result or false
	building[key] = nil
	done:Fire()
	return templates[key] or nil
end

-- swaps a model's look for its SM64 mesh. local = true when the model is this client's own copy (viewports)
function Skins.apply(model: Model, isLocal: boolean?)
	if not folder or model:GetAttribute("Skinned") then
		return
	end
	local key = model:GetAttribute("SkinKey")
	if type(key) ~= "string" then
		return
	end
	model:SetAttribute("Skinned", true)
	task.spawn(function()
		-- on clients a model's parts can arrive after the model itself: wait for its Root
		local root = model.PrimaryPart or model:WaitForChild("Root", 15)
		if not root or not root:IsA("BasePart") then
			return
		end
		local template = Skins.template(key)
		if not template or not model.Parent then
			return
		end
		local scale = model:GetAttribute("SkinScale")
		local height = model:GetAttribute("SkinHeight")
		local target = (type(height) == "number" and height or 4.5) * (type(scale) == "number" and scale or 1)
		local skin = template:Clone()
		local part: BasePart
		local size
		if skin:IsA("Model") then
			local box = skin.PrimaryPart :: BasePart
			skin:ScaleTo(target / box.Size.Y)
			part = box
			size = box.Size.Y
			skin:PivotTo(root.CFrame * CFrame.new(0, size / 2, 0))
		else
			part = skin :: MeshPart
			part.Size = part.Size * (target / part.Size.Y)
			size = part.Size.Y
			part.CFrame = root.CFrame * CFrame.new(0, size / 2, 0)
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root and not d:IsDescendantOf(skin) then
				if isLocal then
					d.Transparency = 1
				else
					d.LocalTransparencyModifier = 1
				end
			end
		end
		if isLocal then
			part.Anchored = true
			if skin:IsA("Model") then
				-- viewports don't run physics, so welds don't move parts: anchor them all where they are
				for _, d in skin:GetDescendants() do
					if d:IsA("BasePart") then
						d.Anchored = true
					end
				end
			end
		else
			part.Anchored = false
			-- a Weld (not a WeldConstraint) so the animator can bob and lunge it through C0
			local weld = Instance.new("Weld")
			weld.Name = "SkinWeld"
			weld.Part0 = root
			weld.Part1 = part
			weld.C0 = CFrame.new(0, size / 2, 0)
			weld.Parent = part
		end
		skin.Name = "SM64"
		skin.Parent = model
		model:SetAttribute("SkinReady", true)
	end)
end

-- switches between "mesh" and "parts" and re-skins every model in the world
function Skins.setMode(mode: string)
	Skins.mode = mode
	table.clear(templates)
	table.clear(Skins.failures)
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Skinned") then
			local old = d:FindFirstChild("SM64")
			if old then
				old:Destroy()
			end
			d:SetAttribute("Skinned", nil)
			d:SetAttribute("SkinReady", nil)
			Skins.apply(d)
		end
	end
end

-- skin every model in the world that has a SkinKey, now and as they appear
function Skins.start()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	folder = ReplicatedStorage:FindFirstChild("SM64Models") or ReplicatedStorage:WaitForChild("SM64Models", 3)
	if not folder then
		print("[SM64] no SM64Models folder: using the built-in models")
		return
	end
	print("[SM64] models found: " .. #folder:GetChildren() .. " files")
	local function check(inst: Instance)
		if inst:IsA("Model") and inst:GetAttribute("SkinKey") then
			Skins.apply(inst)
		end
	end
	for _, d in workspace:GetDescendants() do
		check(d)
	end
	workspace.DescendantAdded:Connect(check)
end

return Skins
