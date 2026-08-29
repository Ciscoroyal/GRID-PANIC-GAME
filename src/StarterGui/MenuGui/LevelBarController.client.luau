--[[
	The always-visible level bar above the Daily Task panel.

	It mirrors the bar on the Rewards > Level page: current level on the left,
	next level on the right, progress between them. XP icons burst from the
	centre of the screen and the fill only advances as each one lands, so the
	gain is something you watch rather than a number that has already changed by
	the time you look.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local menuGui = script.Parent

local levelStateEvent = ReplicatedStorage:WaitForChild("LevelStateEvent")

-- Placeholder art until a proper XP icon exists; swap this one id.
local XP_ICON = "rbxassetid://94843213797100"

local MIN_ICONS, MAX_ICONS = 4, 12
local XP_PER_ICON = 25
local ICON_SIZE = 46
local SPREAD = 0.14
local FLIGHT_MIN, FLIGHT_MAX = 0.45, 0.8
local STAGGER = 0.05

local BAR_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP_INFO = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local bar = menuGui:WaitForChild("LevelBar", 15)
if not bar then
	return
end

local track = bar:WaitForChild("Track")
local fill = track:WaitForChild("Groove"):WaitForChild("Fill")
local xpText = track:WaitForChild("XPText")
local levelBadge = bar:WaitForChild("LevelBadge")
local nextBadge = bar:WaitForChild("NextBadge")

--[[
	Icons live in their own ScreenGui above MenuGui so they are never clipped by
	the panels they fly over.
]]
local burstGui = playerGui:FindFirstChild("XPBurstGui")
if not burstGui then
	burstGui = Instance.new("ScreenGui")
	burstGui.Name = "XPBurstGui"
	burstGui.ResetOnSpawn = false
	burstGui.IgnoreGuiInset = false
	burstGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	burstGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	burstGui.Parent = playerGui
end
-- Above the lobby panels (70) so XP earned while a menu is open is visible.
burstGui.DisplayOrder = 101

local function setBadgeText(badge, text)
	local face = badge:FindFirstChild("Face")
	local label = face and face:FindFirstChild("LevelNumber")
	while label and label:IsA("TextLabel") do
		label.Text = text
		label = label:FindFirstChild("Title")
	end
end

local function popBadge(badge)
	local scale = badge:FindFirstChild("PopScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "PopScale"
		scale.Parent = badge
	end
	scale.Scale = 1.35
	TweenService:Create(scale, POP_INFO, { Scale = 1 }):Play()
end

local function formatXP(n)
	n = math.floor(tonumber(n) or 0)
	local s = tostring(n)
	while true do
		local updated, count = s:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
		s = updated
		if count == 0 then
			break
		end
	end
	return s
end

local shown = nil -- the snapshot the bar is currently displaying
local busy = false
local pending = nil

local function paint(snapshot, progressOverride, xpOverride)
	setBadgeText(levelBadge, tostring(snapshot.level or 1))
	setBadgeText(nextBadge, snapshot.isMax and "MAX" or tostring((snapshot.level or 1) + 1))

	if snapshot.isMax then
		xpText.Text = "MAX LEVEL"
		return 1
	end

	local into = xpOverride or snapshot.xpIntoLevel or 0
	local need = snapshot.xpForNext or 1
	xpText.Text = string.format("%s / %s", formatXP(into), formatXP(need))
	return progressOverride or math.clamp(snapshot.progress or 0, 0, 1)
end

local function snapTo(snapshot)
	local progress = paint(snapshot)
	fill.Size = UDim2.fromScale(progress, 1)
end

local function burstInto(snapshot, gainedXP)
	local viewport = burstGui.AbsoluteSize
	local centre = Vector2.new(viewport.X / 2, viewport.Y / 2)
	local scale = math.clamp(viewport.Y / 1080, 0.75, 1.4)
	local pixels = ICON_SIZE * scale

	local count = math.clamp(math.floor(gainedXP / XP_PER_ICON), MIN_ICONS, MAX_ICONS)
	local startProgress = shown and (shown.isMax and 1 or math.clamp(shown.progress or 0, 0, 1)) or 0
	local endProgress = snapshot.isMax and 1 or math.clamp(snapshot.progress or 0, 0, 1)
	local startXP = shown and shown.xpIntoLevel or 0
	local endXP = snapshot.xpIntoLevel or 0
	local levelledUp = shown and snapshot.level and shown.level and snapshot.level > shown.level

	local landed = 0
	for i = 1, count do
		local icon = Instance.new("ImageLabel")
		icon.Name = "XPIcon"
		icon.BackgroundTransparency = 1
		icon.Image = XP_ICON
		icon.Size = UDim2.fromOffset(pixels, pixels)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.ZIndex = 10

		local angle = math.random() * math.pi * 2
		local radius = SPREAD * viewport.Y * (0.35 + math.random() * 0.65)
		local from = centre + Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
		icon.Position = UDim2.fromOffset(from.X, from.Y)
		icon.Parent = burstGui

		local flight = FLIGHT_MIN + math.random() * (FLIGHT_MAX - FLIGHT_MIN)

		task.delay((i - 1) * STAGGER, function()
			if not icon.Parent then
				return
			end
			TweenService:Create(icon, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(pixels * 1.25, pixels * 1.25),
			}):Play()

			-- Recomputed per icon: the bar can move if the layout shifts.
			local target = track.AbsolutePosition + (track.AbsoluteSize / 2)
			local fly = TweenService:Create(icon, TweenInfo.new(flight, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
				Position = UDim2.fromOffset(target.X, target.Y),
				Size = UDim2.fromOffset(pixels * 0.5, pixels * 0.5),
				ImageTransparency = 0.15,
			})
			fly:Play()

			fly.Completed:Once(function()
				icon:Destroy()
				landed += 1
				local t = landed / count

				if levelledUp then
					--[[
						Crossing a level: run the old bar out to full on the way,
						then switch to the new level and fill from empty. Tweening
						straight to the new value would slide the bar backwards.
					]]
					if t < 0.5 then
						local p = startProgress + ((1 - startProgress) * (t / 0.5))
						TweenService:Create(fill, BAR_INFO, { Size = UDim2.fromScale(p, 1) }):Play()
					else
						if fill.Size.X.Scale > endProgress then
							paint(snapshot)
							fill.Size = UDim2.fromScale(0, 1)
							popBadge(levelBadge)
							popBadge(nextBadge)
						end
						local p = endProgress * ((t - 0.5) / 0.5)
						TweenService:Create(fill, BAR_INFO, { Size = UDim2.fromScale(p, 1) }):Play()
					end
				else
					local p = startProgress + ((endProgress - startProgress) * t)
					local xp = startXP + ((endXP - startXP) * t)
					paint(snapshot, p, xp)
					TweenService:Create(fill, BAR_INFO, { Size = UDim2.fromScale(p, 1) }):Play()
				end

				local bump = track:FindFirstChild("BurstScale")
				if not bump then
					bump = Instance.new("UIScale")
					bump.Name = "BurstScale"
					bump.Parent = track
				end
				bump.Scale = 1.06
				TweenService:Create(bump, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
			end)
		end)
	end

	-- Wait out the flight, then settle on the exact figures.
	local deadline = os.clock() + (count * STAGGER) + FLIGHT_MAX + 0.6
	while landed < count and os.clock() < deadline do
		task.wait(0.05)
	end
	snapTo(snapshot)
end

local function apply(snapshot)
	if typeof(snapshot) ~= "table" then
		return
	end

	local gained = 0
	if shown and snapshot.totalXP and shown.totalXP then
		gained = snapshot.totalXP - shown.totalXP
	end

	-- First paint, or XP went down/sideways: just show the truth.
	if not shown or gained <= 0 then
		shown = snapshot
		snapTo(snapshot)
		return
	end

	if busy then
		pending = snapshot
		return
	end

	busy = true
	task.spawn(function()
		burstInto(snapshot, gained)
		shown = snapshot
		while pending do
			local nextSnapshot = pending
			pending = nil
			local moreGained = (nextSnapshot.totalXP or 0) - (shown.totalXP or 0)
			if moreGained > 0 then
				burstInto(nextSnapshot, moreGained)
			end
			shown = nextSnapshot
			snapTo(nextSnapshot)
		end
		busy = false
	end)
end

levelStateEvent.OnClientEvent:Connect(apply)

-- Hidden during a match, like the rest of the lobby furniture.
local function updateVisibility()
	local inMatch = localPlayer:GetAttribute("InArena") == true
		and localPlayer:GetAttribute("IsEliminated") ~= true
	bar.Visible = not inMatch
end
localPlayer:GetAttributeChangedSignal("InArena"):Connect(updateVisibility)
localPlayer:GetAttributeChangedSignal("IsEliminated"):Connect(updateVisibility)
updateVisibility()

-- Ask for the current state so the bar is populated on join.
task.spawn(function()
	task.wait(1)
	levelStateEvent:FireServer()
end)
