-- The summon animation: a Power Star spins up in a burst of rays whose colour climbs toward the best rarity
-- pulled (blue for Rare, gold for Legendary, rainbow for Mythic), flashes, and the units are revealed: one big
-- spinning model for a single summon, or cards flipping over one by one for a 10x. Click to skip ahead.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = game.ReplicatedStorage.Shared
local Rarities = require(Shared.Rarities)
local Progression = require(Shared.Progression)

local Ui = require(script.Parent.Ui)
local Audio = require(script.Parent.Audio)
local Store = require(script.Parent.Store)

local SummonFx = {}

local C = Ui.Colors
local WHITE = Color3.new(1, 1, 1)

local function tween(inst: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(90, 230, 90)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(70, 180, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(180, 90, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 170)),
})

-- a ring of rays around the centre of `parent`; returns the holder (rotate it) and the rays
local function rays(parent: Instance, count: number, length: number, color: Color3, z: number): (Frame, { Frame })
	local holder = Ui.new("Frame", {
		Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
	local list = {}
	-- each ray is a line through the centre: a GuiObject rotates about its own middle
	for i = 1, count do
		local ray = Ui.new("Frame", {
			Size = UDim2.fromOffset(i % 2 == 0 and 26 or 46, length * 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(0, 0),
			Rotation = i / count * 180,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = holder,
		}, {
			Ui.new("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.42, 0.25),
					NumberSequenceKeypoint.new(0.5, 0.6),
					NumberSequenceKeypoint.new(0.58, 0.25),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		table.insert(list, ray)
	end
	return holder, list
end

local function burst(parent: Instance, color: Color3, count: number, z: number)
	for _ = 1, count do
		local size = math.random(8, 18)
		local p = Ui.new("Frame", {
			Size = UDim2.fromOffset(size, size),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = math.random() < 0.3 and WHITE or color,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = parent,
		}, { Ui.corner(3) })
		local a = math.random() * math.pi * 2
		local d = math.random(220, 520)
		local t = math.random(50, 110) / 100
		tween(p, t, {
			Position = UDim2.new(0.5, math.cos(a) * d, 0.5, math.sin(a) * d),
			BackgroundTransparency = 1,
			Rotation = 45 + math.random(-180, 180),
		})
		task.delay(t, function()
			p:Destroy()
		end)
	end
end

local MYTHIC = Rarities.Info.Mythic.rank
local LEGENDARY = Rarities.Info.Legendary.rank

local function rarityColor(r: string): Color3
	return Rarities.Info[r].color
end

-- plays the animation for summon results ({ unitId, rarity, grades }); calls done when the player closes it
function SummonFx.play(results: { any }, done: () -> ())
	local best = results[1]
	for _, r in results do
		if Rarities.Info[r.rarity].rank > Rarities.Info[best.rarity].rank then
			best = r
		end
	end
	local bestRank = Rarities.Info[best.rarity].rank

	local gui = Ui.new("ScreenGui", {
		Name = "SummonFx",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 30,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	local root = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(8, 4, 20), BackgroundTransparency = 1, Parent = gui })
	Ui.new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(40, 20, 90), Color3.fromRGB(6, 3, 16)),
		Rotation = 90,
		Parent = root,
	})
	-- everything but the background and rays sits on a 1280x760 stage in the middle of the screen, scaled to fit
	local stage = Ui.new("Frame", {
		Size = UDim2.fromOffset(1280, 760),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = root,
	})
	local scale = Ui.new("UIScale", { Parent = stage })
	local cam = workspace.CurrentCamera
	scale.Scale = math.clamp(math.min(cam.ViewportSize.X / 1280, cam.ViewportSize.Y / 760), 0.5, 1.25)
	tween(root, 0.3, { BackgroundTransparency = 0 })

	local connections: { RBXScriptConnection } = {}
	local holder, rayList = rays(root, 9, 1400, WHITE, 2)
	local spinSpeed = 30
	local shake = 0
	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			holder.Rotation += spinSpeed * dt
			if shake > 0 then
				stage.Position = UDim2.new(0.5, math.random(-shake, shake), 0.5, math.random(-shake, shake))
			else
				stage.Position = UDim2.fromScale(0.5, 0.5)
			end
		end)
	)
	local function colorRays(color: Color3?, rainbow: boolean?)
		for _, r in rayList do
			if rainbow then
				r.BackgroundColor3 = WHITE
				local g = r:FindFirstChild("Rainbow") or Ui.new("UIGradient", { Name = "Rainbow", Color = RAINBOW, Parent = r })
				g.Rotation = 0
			elseif color then
				tween(r, 0.25, { BackgroundColor3 = color })
			end
		end
	end

	-- the star
	local glow = Ui.new("Frame", {
		Size = UDim2.fromOffset(220, 220),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.6,
		ZIndex = 3,
		Parent = stage,
	}, { Ui.round() })
	local star = Ui.icon("star", "⭐", { Size = UDim2.fromOffset(190, 190), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), MaxText = 150, ZIndex = 4, Parent = stage })
	local starScale = Ui.new("UIScale", { Scale = 0.1, Parent = star })
	tween(starScale, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
	local caption = Ui.title({
		Text = "SUMMONING...",
		Size = UDim2.fromOffset(600, 50),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.5, 150),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxText = 40,
		Outline = 3,
		ZIndex = 5,
		Parent = stage,
	})
	Ui.text({
		Text = "click to skip",
		Size = UDim2.fromOffset(300, 24),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = C.muted,
		MaxText = 18,
		ZIndex = 5,
		Parent = stage,
	})

	local skipped = false
	local skipButton = Ui.new("TextButton", { Text = "", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20, Parent = root })
	skipButton.Activated:Connect(function()
		skipped = true
	end)
	local function wait(t: number)
		local start = os.clock()
		while os.clock() - start < t and not skipped do
			task.wait()
		end
	end

	-- the build-up: each stage the pull reaches turns the rays and glow a rarer colour
	Audio.music("music_summon", 0.4)
	local stages = {
		{ rank = 1, color = Color3.fromRGB(230, 230, 255), text = "SUMMONING..." },
		{ rank = 2, color = rarityColor("Rare"), text = "RARE...?" },
		{ rank = 3, color = rarityColor("Epic"), text = "EPIC!" },
		{ rank = 4, color = rarityColor("Legendary"), text = "LEGENDARY!?" },
		{ rank = 5, color = rarityColor("Mythic"), text = "M Y T H I C ! ! !" },
	}
	for i, st in stages do
		if st.rank > bestRank or skipped then
			break
		end
		colorRays(st.color, st.rank == MYTHIC)
		tween(glow, 0.25, { BackgroundColor3 = st.color, Size = UDim2.fromOffset(220 + i * 50, 220 + i * 50) })
		caption.Text = st.text
		caption.TextColor3 = st.color
		Ui.pop(caption)
		burst(root, st.color, 10 + i * 8, 4)
		Audio.play("power_meter", { pitch = 0.9 + i * 0.12, gap = 0.1 })
		spinSpeed = 30 + i * 50
		shake = (i - 1) * 3
		tween(star, 0.6, { Rotation = star.Rotation + 360 }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
		tween(starScale, 0.3, { Scale = 1 + i * 0.12 }, Enum.EasingStyle.Back)
		wait(i == 1 and 0.9 or 0.75)
	end
	skipped = false
	skipButton:Destroy()

	-- flash
	shake = 0
	local flash = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, ZIndex = 15, Parent = root })
	tween(flash, 0.6, { BackgroundTransparency = 1 })
	task.delay(0.6, function()
		flash:Destroy()
	end)
	burst(root, rarityColor(best.rarity), 40, 6)
	Audio.play("star_appears", { volume = 1 })
	if bestRank >= MYTHIC then
		task.delay(0.4, Audio.play, "voice_yahoo", { gap = 1 })
	elseif bestRank == LEGENDARY then
		task.delay(0.4, Audio.play, "voice_yippee", { gap = 1 })
	end
	star:Destroy()
	glow:Destroy()
	caption:Destroy()
	spinSpeed = 18
	colorRays(rarityColor(best.rarity), bestRank == MYTHIC)

	-- reveal (whatever goes wrong in it, the close button below still appears)
	local revealed, revealError = pcall(function()
		local banner = ({ "NICE PULL!", "RARE PULL!", "EPIC PULL!", "LEGENDARY!", "MYTHIC!!!" })[bestRank]
		local title = Ui.title({
			Text = banner,
			Size = UDim2.fromOffset(700, 70),
			Position = UDim2.new(0.5, 0, 0.5, -280),
			AnchorPoint = Vector2.new(0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = rarityColor(best.rarity),
			MaxText = 64,
			Outline = 4,
			ZIndex = 8,
			Parent = stage,
		})
		if bestRank == MYTHIC then
			title.TextColor3 = WHITE
			Ui.spin(Ui.new("UIGradient", { Color = RAINBOW, Parent = title }), 120)
		end
		Ui.pop(title)

		local function gradeRow(parent: Instance, grades: any, props: { [string]: any })
			local row = Ui.new("Frame", props, { Ui.list(Enum.FillDirection.Horizontal, 4, Enum.HorizontalAlignment.Center) })
			row.BackgroundTransparency = 1
			row.Parent = parent
			local g = grades or Progression.DefaultGrades
			for _, k in { "d", "s", "r" } do
				Ui.gradeBadge(g[k], { Size = UDim2.fromOffset(40, 22), MaxText = 18, ZIndex = 9, Parent = row })
			end
			return row
		end

		if #results == 1 then
			local r = results[1]
			local vp = Ui.viewport(r.unitId, {
				Size = UDim2.fromOffset(380, 380),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, -20),
				ZIndex = 8,
				Parent = stage,
			}, true)
			Ui.pop(vp)
			local name = Ui.title({
				Text = Ui.unitName(r.unitId),
				Size = UDim2.fromOffset(600, 50),
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.5, 160),
				TextXAlignment = Enum.TextXAlignment.Center,
				MaxText = 44,
				Outline = 3,
				ZIndex = 9,
				Parent = stage,
			})
			Ui.pop(name, 0.1)
			Ui.chip(r.rarity, rarityColor(r.rarity), { Size = UDim2.fromOffset(150, 28), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 212), ZIndex = 9, Parent = stage })
			gradeRow(root, r.grades, { Size = UDim2.fromOffset(200, 24), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 248) })
		else
			local grid = Ui.new("Frame", {
				Size = UDim2.fromOffset(5 * 150, 2 * 214),
				Position = UDim2.new(0.5, 0, 0.5, 10),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 8,
				Parent = stage,
			}, {
				Ui.new("UIGridLayout", {
					CellSize = UDim2.fromOffset(138, 202),
					CellPadding = UDim2.fromOffset(12, 12),
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			})
			local cards = {}
			for i, r in results do
				local slot = Ui.new("Frame", { LayoutOrder = i, BackgroundTransparency = 1, ZIndex = 8, Parent = grid })
				-- face down: a purple card with a star
				local back = Ui.new("Frame", {
					Size = UDim2.new(1, 0, 1, -28),
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0),
					BackgroundColor3 = WHITE,
					ZIndex = 8,
					Parent = slot,
				}, { Ui.corner(12), Ui.stroke(C.ink, 3), Ui.gradient(Color3.fromRGB(150, 90, 255), Color3.fromRGB(60, 30, 140)) })
				Ui.icon("star", "⭐", { Size = UDim2.fromOffset(70, 70), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), MaxText = 50, ZIndex = 9, Parent = back })
				Ui.pop(slot, i * 0.03)
				cards[i] = { slot = slot, back = back, r = r }
			end
			task.wait(0.4)
			for _, c in cards do
				local rank = Rarities.Info[c.r.rarity].rank
				-- flip: squash the back flat, then grow the unit card out of it
				local t = tween(c.back, 0.12, { Size = UDim2.new(0, 0, 1, -28) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				t.Completed:Wait()
				c.back:Destroy()
				local card = Ui.unitCard(c.slot, { unitId = c.r.unitId, level = 1 }, UDim2.new(1, 0, 1, -28))
				card.AnchorPoint = Vector2.new(0.5, 0)
				card.Position = UDim2.fromScale(0.5, 0)
				card.Size = UDim2.new(0, 0, 1, -28)
				tween(card, 0.16, { Size = UDim2.new(1, 0, 1, -28) }, Enum.EasingStyle.Back)
				Ui.chip(c.r.rarity, rarityColor(c.r.rarity), { Size = UDim2.fromOffset(100, 22), Position = UDim2.new(0.5, -50, 0, -11), ZIndex = 12, Parent = card })
				gradeRow(c.slot, c.r.grades, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24) })
				if rank >= Rarities.Info.Epic.rank then
					-- legendary and mythic cards glow and burst
					local stroke = card:FindFirstChildWhichIsA("UIStroke") :: UIStroke
					stroke.Color = rarityColor(c.r.rarity)
					stroke.Thickness = 4
					task.spawn(function()
						while stroke.Parent do
							tween(stroke, 0.5, { Thickness = 7 }).Completed:Wait()
							tween(stroke, 0.5, { Thickness = 3 }).Completed:Wait()
						end
					end)
					Audio.play(rank >= MYTHIC and "red_coin" or "one_up", { gap = 0.05 })
					local pos = c.slot.AbsolutePosition + c.slot.AbsoluteSize / 2 - stage.AbsolutePosition - stage.AbsoluteSize / 2
					for _ = 1, 14 do
						local p = Ui.new("Frame", {
							Size = UDim2.fromOffset(10, 10),
							AnchorPoint = Vector2.new(0.5, 0.5),
							Position = UDim2.new(0.5, pos.X / scale.Scale, 0.5, pos.Y / scale.Scale),
							Rotation = 45,
							BackgroundColor3 = rarityColor(c.r.rarity),
							BorderSizePixel = 0,
							ZIndex = 13,
							Parent = stage,
						})
						local a = math.random() * math.pi * 2
						tween(p, 0.6, { Position = p.Position + UDim2.fromOffset(math.cos(a) * 120, math.sin(a) * 120), BackgroundTransparency = 1 })
						task.delay(0.6, function()
							p:Destroy()
						end)
					end
					shake = 4
					task.delay(0.15, function()
						shake = 0
					end)
					task.wait(0.35)
				else
					Audio.play("coin", { volume = 0.5, gap = 0.03 })
					task.wait(0.12)
				end
			end
		end

	end)
	if not revealed then
		warn("[SummonFx] " .. tostring(revealError))
	end

	local ok = Ui.button("AWESOME!", C.green, function()
		for _, c in connections do
			c:Disconnect()
		end
		tween(root, 0.2, { BackgroundTransparency = 1 })
		gui:Destroy()
		Audio.followBattle(Store.battle)
		done()
	end, { Size = UDim2.fromOffset(240, 58), Position = UDim2.new(0.5, 0, 1, -90), AnchorPoint = Vector2.new(0.5, 0), MaxText = 30, ZIndex = 14, Parent = stage })
	ok.Font = Ui.TitleFont
	Ui.pop(ok)
end

return SummonFx
