-- Brings the SM64 models to life on this client by moving each skin's Weld (see Skins); the server's models and
-- hitboxes are untouched.
--   units: drop in with a bounce when placed, breathe and look around, wind up and lunge at each attack, and jump
--          with a full spin when upgraded
--   enemies: hop and waddle along the path; bosses stomp slower and heavier; all shrink away in a spin when killed
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Animator = {}

type Entry = {
	weld: Weld,
	skin: Instance,
	base: CFrame,
	height: number,
	phase: number,
	kind: string,
	lunge: number,
	drop: number,
	spin: number,
}

local tracked: { [Model]: Entry } = {}

local function kindOf(model: Model): string
	local parent = model.Parent
	if parent and parent.Name == "Enemies" then
		local scale = model:GetAttribute("SkinScale")
		return (type(scale) == "number" and scale >= 2) and "boss" or "enemy"
	end
	return "unit"
end

-- a quick copy of a killed enemy's mesh that spins, shrinks and fades where it died
local function poof(e: Entry)
	local skin = e.skin
	if not skin:IsA("MeshPart") then
		return
	end
	local ghost = skin:Clone()
	for _, d in ghost:GetChildren() do
		d:Destroy()
	end
	ghost.Anchored = true
	ghost.Parent = workspace
	local size = ghost.Size
	local cf = ghost.CFrame
	TweenService:Create(ghost, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Size = size * 0.05,
		CFrame = cf * CFrame.new(0, size.Y * 0.4, 0) * CFrame.Angles(0, math.pi * 1.5, 0),
		Transparency = 0.6,
	}):Play()
	task.delay(0.4, function()
		ghost:Destroy()
	end)
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	local skin = model:FindFirstChild("SM64")
	local weld = skin and skin:FindFirstChild("SkinWeld", true)
	if not skin or not weld or not weld:IsA("Weld") then
		return
	end
	local kind = kindOf(model)
	local entry: Entry = {
		weld = weld,
		skin = skin,
		base = weld.C0,
		height = weld.C0.Y * 2,
		phase = math.random() * 10,
		kind = kind,
		lunge = 0,
		-- units placed in battle drop in; statues and enemies appear as they are
		drop = (kind == "unit" and model:GetAttribute("TowerId") ~= nil) and 1 or 0,
		spin = 0,
	}
	tracked[model] = entry
	if kind == "unit" then
		model:GetAttributeChangedSignal("Level"):Connect(function()
			entry.spin = 1
		end)
	else
		model.AncestryChanged:Connect(function(_, parent)
			if not parent and tracked[model] then
				tracked[model] = nil
				pcall(poof, entry)
			end
		end)
	end
end

-- the unit with this tower id attacks
function Animator.attack(towerId: number)
	for model, e in tracked do
		if e.kind == "unit" and model:GetAttribute("TowerId") == towerId then
			e.lunge = 1
			return
		end
	end
end

local function bounceOut(t: number): number
	-- 0 -> 1 with a bounce at the end
	if t < 0.6 then
		return (t / 0.6) ^ 2
	end
	local k = (t - 0.8) / 0.2
	return 1 - 0.12 * (1 - k * k)
end

function Animator.start()
	workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") then
			-- skins are added a moment after the model appears
			task.delay(0.1, function()
				if inst:GetAttribute("SkinReady") then
					track(inst)
				end
			end)
			inst:GetAttributeChangedSignal("SkinReady"):Connect(function()
				track(inst)
			end)
		end
	end)
	for _, d in workspace:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("SkinReady") then
			track(d)
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for model, e in tracked do
			if not model.Parent or not e.weld.Parent then
				tracked[model] = nil
				continue
			end
			local h = e.height
			local p = t + e.phase
			local cf
			if e.kind == "enemy" then
				local hop = math.abs(math.sin(p * 9)) * 0.12 * h
				cf = CFrame.new(0, hop, 0) * CFrame.Angles(0, 0, math.sin(p * 9) * 0.14)
			elseif e.kind == "boss" then
				local stomp = math.abs(math.sin(p * 4)) * 0.05 * h
				cf = CFrame.new(0, stomp, 0) * CFrame.Angles(math.sin(p * 4) * 0.04, 0, math.sin(p * 4) * 0.07)
			else
				local breathe = math.sin(p * 2.2) * 0.03 * h
				-- now and then the unit glances to the side
				local glance = math.clamp(math.sin(p * 0.45) * 3, -1, 1) * 0.25
				cf = CFrame.new(0, breathe, 0) * CFrame.Angles(0, glance + math.sin(p * 1.1) * 0.05, 0)
				if e.drop > 0 then
					e.drop = math.max(0, e.drop - dt * 2.5)
					local k = bounceOut(1 - e.drop)
					cf = CFrame.new(0, (1 - k) * h * 1.6, 0) * CFrame.Angles(0, (1 - k) * math.pi, 0) * cf
				end
				if e.spin > 0 then
					e.spin = math.max(0, e.spin - dt * 1.8)
					local k = 1 - e.spin
					cf = CFrame.new(0, math.sin(k * math.pi) * h * 0.6, 0) * CFrame.Angles(0, k * math.pi * 2, 0) * cf
				end
				if e.lunge > 0 then
					e.lunge = math.max(0, e.lunge - dt * 4.5)
					local k = 1 - e.lunge
					-- wind up (lean back) for the first third, then strike forward and recover
					local back = k < 0.3 and math.sin(k / 0.3 * math.pi / 2) or math.max(0, 1 - (k - 0.3) / 0.15)
					local strike = k < 0.3 and 0 or math.sin((k - 0.3) / 0.7 * math.pi)
					cf = cf
						* CFrame.new(0, strike * 0.15 * h, -strike * 0.45 * h + back * 0.1 * h)
						* CFrame.Angles(-strike * 0.45 + back * 0.25, 0, 0)
				end
			end
			e.weld.C0 = e.base * cf
		end
	end)
end

return Animator
