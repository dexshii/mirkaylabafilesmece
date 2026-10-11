-- Puts SM64 meshes on units, enemies, statues and UI models when ReplicatedStorage.SM64Models exists (a private
-- build made with tools/sm64_import --luau). Each mesh is built once on this client with EditableMesh and
-- EditableImage, then cloned onto every model whose "SkinKey" attribute names it; the model's own parts are hidden.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local Skins = {}

local folder = ReplicatedStorage:FindFirstChild("SM64Models")
local templates: { [string]: MeshPart | false } = {}
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

local function build(key: string): MeshPart?
	local module = folder and folder:FindFirstChild(key)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local data = require(module) :: any
	if data.alias then
		return Skins.template(data.alias)
	end
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
	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
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

-- the mesh for a key, built on first use (yields); nil when there is none
function Skins.template(key: string): MeshPart?
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
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if type(key) ~= "string" or not root or not root:IsA("BasePart") then
		return
	end
	model:SetAttribute("Skinned", true)
	task.spawn(function()
		local template = Skins.template(key)
		if not template or not model.Parent then
			return
		end
		local scale = model:GetAttribute("SkinScale")
		local height = model:GetAttribute("SkinHeight")
		local target = (type(height) == "number" and height or 4.5) * (type(scale) == "number" and scale or 1)
		local part = template:Clone()
		part.Size = template.Size * (target / template.Size.Y)
		part.CFrame = root.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				if isLocal then
					d.Transparency = 1
				else
					d.LocalTransparencyModifier = 1
				end
			end
		end
		if isLocal then
			part.Anchored = true
		else
			part.Anchored = false
			-- a Weld (not a WeldConstraint) so the animator can bob and lunge it through C0
			local weld = Instance.new("Weld")
			weld.Name = "SkinWeld"
			weld.Part0 = root
			weld.Part1 = part
			weld.C0 = CFrame.new(0, part.Size.Y / 2, 0)
			weld.Parent = part
		end
		part.Parent = model
		model:SetAttribute("SkinReady", true)
	end)
end

-- skin every model in the world that has a SkinKey, now and as they appear
function Skins.start()
	if not folder then
		return
	end
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
