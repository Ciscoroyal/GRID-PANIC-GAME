--[[
	Coins and fans burst from the centre of the screen and fly into their
	counters, which tick up as each one lands.

	MenuController normally writes these labels straight to the new value the
	instant leaderstats changes. This script marks the two frames "BurstOwned"
	so MenuController leaves them alone, and drives the number itself so it
	climbs with the icons instead of jumping ahead of them.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local menuGui = script.Parent


local MIN_ICONS = 5
local MAX_ICONS = 14

-- One icon per this many units, between the min and max above.
local UNITS_PER_ICON = 12

local ICON_SIZE = 54 -- pixels at 1080p, scaled below
local SPREAD = 0.16 -- how far from centre they scatter, in screen fraction
local FLIGHT_MIN, FLIGHT_MAX = 0.45, 0.75
local STAGGER = 0.045

--[[
	Claim the two counters before MenuController's currency binder runs, so it
	never fights us for the label. Done synchronously: these frames are
	siblings of this script and exist the moment the GUI is cloned.
]]
local moneyFrame = menuGui:FindFirstChild("Money")
local fansFrame = menuGui:FindFirstChild("Fans")
if moneyFrame then
	moneyFrame:SetAttribute("BurstOwned", true)
end
if fansFrame then
	fansFrame:SetAttribute("BurstOwned", true)
end

--[[
	Icons live in their own ScreenGui so they draw over everything and are not
	clipped or reordered by whatever the menu is doing. Its inset settings
	match MenuGui's so AbsolutePosition means the same thing in both.
]]
local burstGui = playerGui:FindFirstChild("CurrencyBurstGui")
if not burstGui then
	burstGui = Instance.new("ScreenGui")
	burstGui.Name = "CurrencyBurstGui"
	burstGui.ResetOnSpawn = false
	burstGui.IgnoreGuiInset = false
	burstGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	burstGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	burstGui.Parent = playerGui
end
--[[
	Set every run, not just on creation, so a GUI left over from an earlier
	session is lifted too. The lobby panels sit at DisplayOrder 70; at 61 the
	icons flew behind an open Rewards or Store window, which is exactly when a
	payout is most likely to happen.
]]
burstGui.DisplayOrder = 100

--[[
	One blip per icon landing, rising slightly across the burst so a payout
	reads as a run rather than a flat repeat. Up to 14 fire in a row, so the
	volume is deliberately low.
]]
local function playPickupSound(index, total)
	local progress = total > 1 and ((index - 1) / (total - 1)) or 0
	Audio.play("CoinPickup", {
		pitch = 0.94 + (progress * 0.22),
		pitchJitter = 0.03,
	})
end

-- The frames carry two stacked "Title" labels (face and shadow); write to both.
local function setCounterText(frame, value)
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("TextLabel") and d.Name == "Title" then
			d.Text = tostring(value)
		end
	end
end

local function getIconImage(frame)
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("ImageLabel") and d.Image ~= "" then
			return d.Image
		end
	end
	return ""
end

local function centreOf(frame)
	return frame.AbsolutePosition + (frame.AbsoluteSize / 2)
end

--[[
	One currency. `frame` is the counter, `valueObject` the leaderstats entry.

	`accounted` is the last value we have folded into a burst; `displayed` is
	what the label currently reads. Keeping them apart means a payout that
	arrives mid-flight is measured against the real total, not against the
	half-climbed number on screen.
]]
local function bindBurst(frame, valueObject)
	if not frame or not valueObject then
		return
	end

	local iconImage = getIconImage(frame)
	local displayed = valueObject.Value
	local accounted = valueObject.Value
	local busy = false
	local queued = 0

	setCounterText(frame, displayed)

	local function runBurst(gained)
		local start = displayed
		local target = start + gained

		local iconCount = math.clamp(math.floor(gained / UNITS_PER_ICON), MIN_ICONS, MAX_ICONS)
		local perIcon = gained / iconCount
		local awarded = 0

		local viewport = burstGui.AbsoluteSize
		local centre = Vector2.new(viewport.X / 2, viewport.Y / 2)
		local scale = math.clamp(viewport.Y / 1080, 0.75, 1.4)
		local iconPixels = ICON_SIZE * scale

		local landed = 0
		for i = 1, iconCount do
			local icon = Instance.new("ImageLabel")
			icon.Name = "BurstIcon"
			icon.BackgroundTransparency = 1
			icon.Image = iconImage
			icon.Size = UDim2.fromOffset(iconPixels, iconPixels)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.ZIndex = 10

			-- Scatter around the centre, then fall into the counter.
			local angle = math.random() * math.pi * 2
			local radius = SPREAD * viewport.Y * (0.35 + math.random() * 0.65)
			local startPos = centre + Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
			icon.Position = UDim2.fromOffset(startPos.X, startPos.Y)
			icon.Parent = burstGui

			local flight = FLIGHT_MIN + math.random() * (FLIGHT_MAX - FLIGHT_MIN)

			task.delay((i - 1) * STAGGER, function()
				if not icon.Parent then
					return
				end

				-- Small pop outward first so they do not all read as one blob.
				local pop = TweenService:Create(icon, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(iconPixels * 1.25, iconPixels * 1.25),
				})
				pop:Play()

				-- Recomputed here: the counter can move if the layout shifts.
				local destination = centreOf(frame)
				local fly = TweenService:Create(icon, TweenInfo.new(flight, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
					Position = UDim2.fromOffset(destination.X, destination.Y),
					Size = UDim2.fromOffset(iconPixels * 0.55, iconPixels * 0.55),
					ImageTransparency = 0.15,
				})
				fly:Play()

				fly.Completed:Once(function()
					icon:Destroy()
					landed += 1

					-- Tick the counter up as each one arrives; the last one
					-- snaps to the exact total so rounding cannot drift.
					if landed >= iconCount then
						displayed = target
					else
						awarded += perIcon
						displayed = math.floor(start + awarded)
					end
					setCounterText(frame, displayed)
					playPickupSound(landed, iconCount)

					-- A little kick on the counter as it takes the hit.
					local bump = frame:FindFirstChild("BurstScale")
					if not bump then
						bump = Instance.new("UIScale")
						bump.Name = "BurstScale"
						bump.Parent = frame
					end
					bump.Scale = 1.08
					TweenService:Create(bump, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Scale = 1,
					}):Play()
				end)
			end)
		end

		-- Wait out the whole flight before releasing the label.
		local total = (iconCount * STAGGER) + FLIGHT_MAX + 0.5
		local deadline = os.clock() + total
		while landed < iconCount and os.clock() < deadline do
			task.wait(0.05)
		end

		displayed = target
		setCounterText(frame, displayed)
	end

	valueObject:GetPropertyChangedSignal("Value"):Connect(function()
		local delta = valueObject.Value - accounted
		accounted = valueObject.Value

		-- Losses (spending) and no-ops just snap; only earnings get the show.
		if delta <= 0 then
			queued = 0
			displayed = valueObject.Value
			setCounterText(frame, displayed)
			return
		end

		if busy then
			queued += delta
			return
		end

		busy = true
		task.spawn(function()
			runBurst(delta)
			while queued > 0 do
				local pending = queued
				queued = 0
				runBurst(pending)
			end
			busy = false
			-- Re-sync in case anything snapped while we were animating.
			displayed = accounted
			setCounterText(frame, displayed)
		end)
	end)
end

task.spawn(function()
	local leaderstats = localPlayer:WaitForChild("leaderstats", 20)
	local coins = leaderstats and leaderstats:WaitForChild("Coins", 20)
	bindBurst(menuGui:WaitForChild("Money", 20), coins)
end)

task.spawn(function()
	local fans = localPlayer:WaitForChild("AllTimeFans", 20)
	bindBurst(menuGui:WaitForChild("Fans", 20), fans)
end)
