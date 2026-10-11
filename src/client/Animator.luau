-- Brings the SM64 models to life on this client: units and statues breathe and sway, enemies hop and waddle along
-- the path (bosses stomp slower and heavier), and a unit lunges at its target each time it attacks. It moves the
-- skin's Weld (see Skins), so the server's models and hitboxes are untouched.
local RunService = game:GetService("RunService")

local Animator = {}

type Entry = { weld: Weld, base: CFrame, height: number, phase: number, kind: string, lunge: number }

local tracked: { [Model]: Entry } = {}

local function kindOf(model: Model): string
	local parent = model.Parent
	if parent and parent.Name == "Enemies" then
		local scale = model:GetAttribute("SkinScale")
		return (type(scale) == "number" and scale >= 2) and "boss" or "enemy"
	end
	return "unit"
end

local function track(model: Model)
	if tracked[model] then
		return
	end
	local skin = model:FindFirstChild("SM64")
	local weld = skin and skin:FindFirstChild("SkinWeld", true)
	if not weld or not weld:IsA("Weld") then
		return
	end
	tracked[model] = {
		weld = weld,
		base = weld.C0,
		height = weld.C0.Y * 2,
		phase = math.random() * 10,
		kind = kindOf(model),
		lunge = 0,
	}
end

-- a quick lunge toward the target for the unit with this tower id
function Animator.attack(towerId: number)
	for model, e in tracked do
		if e.kind == "unit" and model:GetAttribute("TowerId") == towerId then
			e.lunge = 1
			return
		end
	end
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
				cf = CFrame.new(0, stomp, 0) * CFrame.Angles(0, 0, math.sin(p * 4) * 0.07)
			else
				local breathe = math.sin(p * 2.2) * 0.03 * h
				cf = CFrame.new(0, breathe, 0) * CFrame.Angles(0, math.sin(p * 1.1) * 0.08, 0)
				if e.lunge > 0 then
					e.lunge = math.max(0, e.lunge - dt * 5)
					local k = math.sin(e.lunge * math.pi)
					cf = cf * CFrame.new(0, k * 0.12 * h, -k * 0.35 * h) * CFrame.Angles(-k * 0.35, 0, 0)
				end
			end
			e.weld.C0 = e.base * cf
		end
	end)
end

return Animator
