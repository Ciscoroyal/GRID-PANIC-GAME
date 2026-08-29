local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))

local UIHelpers = {}

--[[
	Every button and panel in the game goes through bindButtonHover and
	animatePanelOpen/Close, so hooking the sounds here covers the whole UI from
	one place. A button that makes its own noise (a vote option, say) sets the
	NoClickSound attribute to opt out of the generic click.

	Required lazily: this module is only ever used on the client, but the
	require is deferred so nothing breaks if that ever changes.
]]
local audio = nil
local function playUISound(name, opts)
	if not RunService:IsClient() then
		return
	end
	if audio == nil then
		local ok, result = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Audio", 10))
		end)
		audio = ok and result or false
	end
	if audio then
		audio.play(name, opts)
	end
end

--[[
	Button feel.

	Hover eases out softly. Press is fast and linear-ish so it lands the instant
	the mouse goes down. Release uses Back so the button pops back rather than
	drifting - that snap is what makes a click feel like it registered.
]]
local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RELEASE_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- A leaf button is the thing you actually aim at, so it gets the full reaction.
-- A container button (a list row that holds its own Claim/Play button) only
-- shifts slightly, because a whole row swelling under the cursor reads as a
-- glitch rather than as feedback.
local LEAF_HOVER, LEAF_PRESS = 1.07, 0.94
local ROW_HOVER, ROW_PRESS = 1.015, 0.99

--[[
	How far toward black a pressed image dips.

	This is a press cue, not a hover one: nearly every icon in this game is full
	colour artwork drawn at ImageColor3 = white, so lifting it toward white on
	hover would be invisible. Dipping it on press reads clearly on white art and
	gives the button the "pushed in" feel that scale alone does not.
]]
local PRESS_DARKEN = 0.16

--[[
	Bindings are tracked in a table rather than an attribute on the instance.
	Clone() copies attributes, so a template that had been bound handed
	"already bound" to every card cloned from it and those cards silently got no
	feedback at all. A table keyed by the instance cannot be inherited.
]]
local bindings = setmetatable({}, { __mode = "k" })

function UIHelpers.prepareImageLabel(imageLabel)
	if not imageLabel then
		return
	end
	imageLabel.BackgroundTransparency = 1
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.Visible = true
end

function UIHelpers.setAvatarImage(imageLabel, userId)
	UIHelpers.prepareImageLabel(imageLabel)
	imageLabel.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"

	if not userId then
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok and imageLabel.Parent then
			imageLabel.Image = content
		end
	end)
end

function UIHelpers.setAbilityImage(imageLabel, abilityName)
	UIHelpers.prepareImageLabel(imageLabel)

	local abilityInfo = AbilityData[abilityName]
	if abilityInfo and abilityInfo.ImageId and abilityInfo.ImageId ~= "" then
		imageLabel.Image = abilityInfo.ImageId
		imageLabel.Visible = true
	else
		imageLabel.Image = ""
		imageLabel.Visible = false
	end
end

local function getOrCreateUIScale(parent, name)
	local scale = name and parent:FindFirstChild(name) or parent:FindFirstChildOfClass("UIScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end
	--[[
		Roblox applies only one UIScale per object. Adding a second under a
		different name would leave it silently inert, so reuse whatever is
		already there instead of stacking.
	]]
	local existing = parent:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	scale = Instance.new("UIScale")
	if name then
		scale.Name = name
	end
	scale.Scale = 1
	scale.Parent = parent
	return scale
end

local function tweenScale(scale, value, info)
	TweenService:Create(scale, info or HOVER_INFO, { Scale = value }):Play()
end

--[[
	The image a press should dip, if any. Only ImageColor3 is touched: several
	controllers drive BackgroundColor3 to signal state (a Claim button going
	gold then grey), and restoring a colour captured before that change would
	undo their work.
]]
local function getTintTarget(visual)
	if (visual:IsA("ImageButton") or visual:IsA("ImageLabel"))
		and visual.Image ~= "" and visual.ImageTransparency < 1 then
		return visual
	end
	for _, d in ipairs(visual:GetChildren()) do
		if (d:IsA("ImageLabel") or d:IsA("ImageButton"))
			and d.Image ~= "" and d.ImageTransparency < 1 and d.Visible then
			return d
		end
	end
	return nil
end

-- Walk up to the nearest ancestor that also has feedback bound to it.
local function findBoundAncestor(instance)
	local parent = instance.Parent
	while parent and parent:IsA("GuiObject") do
		if bindings[parent] then
			return parent
		end
		parent = parent.Parent
	end
	return nil
end

-- Does anything bound live inside this one? Then it is a row, not a target.
local function hasBoundDescendant(instance)
	for _, d in ipairs(instance:GetDescendants()) do
		if bindings[d] then
			return true
		end
	end
	return false
end

-- Soft hover / press feedback. `hitTarget` receives input; `visual` is animated.
function UIHelpers.bindButtonHover(hitTarget, opts)
	opts = opts or {}
	if not hitTarget or not hitTarget:IsA("GuiObject") then
		return
	end
	if bindings[hitTarget] then
		return
	end

	local visual = opts.visual or hitTarget
	if not visual:IsA("GuiObject") then
		visual = hitTarget
	end

	local scale = getOrCreateUIScale(visual, "HoverUIScale")
	scale.Scale = 1

	if hitTarget:IsA("GuiButton") then
		hitTarget.AutoButtonColor = false
	end

	local hovering = false
	local pressed = false
	local suppressed = false
	local tint = nil
	local baseTint = nil
	-- When a real mouse-down was last seen, used to tell a desktop click from a
	-- touch tap. Far enough in the past that the first tap is not mistaken for
	-- the tail of a click.
	local lastDownAt = -math.huge

	--[[
		Row or target is decided per hover, not at bind time: parents and children
		bind in whatever order their controller happens to build them, so asking
		the question up front gives the wrong answer half the time.
	]]
	local function scales()
		if hasBoundDescendant(hitTarget) then
			return ROW_HOVER, ROW_PRESS
		end
		return opts.hoverScale or LEAF_HOVER, opts.pressScale or LEAF_PRESS
	end

	local function restoreTint()
		if tint and baseTint then
			TweenService:Create(tint, HOVER_INFO, { ImageColor3 = baseTint }):Play()
		end
		tint, baseTint = nil, nil
	end

	local function applyTint()
		-- Captured on the press rather than at bind time, so a card whose artwork
		-- was swapped since binding still dips from its current colour.
		tint = getTintTarget(visual)
		if not tint then
			return
		end
		baseTint = tint.ImageColor3
		TweenService:Create(tint, PRESS_INFO, {
			ImageColor3 = baseTint:Lerp(Color3.new(0, 0, 0), PRESS_DARKEN),
		}):Play()
	end

	local function toIdle()
		tweenScale(scale, 1, HOVER_INFO)
		restoreTint()
	end

	local function toHover()
		if suppressed then
			return
		end
		local hoverScale = scales()
		tweenScale(scale, hoverScale, HOVER_INFO)
		restoreTint()
	end

	local function toPress()
		pressed = true
		local _, pressScale = scales()
		tweenScale(scale, pressScale, PRESS_INFO)
		if not tint then
			applyTint()
		end
	end

	local function toRelease()
		pressed = false
		if hovering and not suppressed then
			tweenScale(scale, (scales()), RELEASE_INFO)
		else
			tweenScale(scale, 1, RELEASE_INFO)
			restoreTint()
		end
	end

	local binding
	binding = {
		-- Called by a child so the row underneath stops reacting; without this the
		-- two UIScales multiply and the button you are aiming at jumps.
		setSuppressed = function(value)
			if suppressed == value then
				return
			end
			suppressed = value
			if suppressed then
				toIdle()
			elseif hovering then
				toHover()
			end
		end,
		-- Called when a panel closes, so nothing is left frozen mid-hover.
		reset = function()
			hovering, pressed, suppressed = false, false, false
			scale.Scale = 1
			restoreTint()
		end,
	}
	bindings[hitTarget] = binding

	local function setAncestorSuppressed(value)
		local ancestor = findBoundAncestor(hitTarget)
		local entry = ancestor and bindings[ancestor]
		if entry then
			entry.setSuppressed(value)
		end
	end

	hitTarget.MouseEnter:Connect(function()
		hovering = true
		setAncestorSuppressed(true)
		toHover()
		-- Throttled: sweeping the cursor across a list would otherwise fire one
		-- sound per row per frame.
		playUISound("ButtonHover", { throttle = 0.06 })
	end)

	hitTarget.MouseLeave:Connect(function()
		hovering = false
		pressed = false
		setAncestorSuppressed(false)
		toIdle()
	end)

	if hitTarget:IsA("GuiButton") then
		hitTarget.MouseButton1Down:Connect(function()
			lastDownAt = os.clock()
			toPress()
		end)
		hitTarget.MouseButton1Up:Connect(toRelease)
		hitTarget.MouseButton1Click:Connect(function()
			--[[
				Touch sends no MouseEnter and no press pair, so a tap would have no
				visual reaction at all. Synthesise one - but only when no real
				mouse-down just happened. MouseButton1Up fires before this and
				clears `pressed`, so testing that flag alone would fire a second
				press cycle after every desktop click.
			]]
			if os.clock() - lastDownAt > 0.5 then
				toPress()
				task.delay(0.08, toRelease)
			end
			if hitTarget:GetAttribute("NoClickSound") ~= true then
				playUISound("ButtonClick", { throttle = 0.05 })
			end
		end)
	end
end

-- Put every bound button under `root` back to rest.
function UIHelpers.resetHoversUnder(root)
	if not root then
		return
	end
	local entry = bindings[root]
	if entry then
		entry.reset()
	end
	for _, d in ipairs(root:GetDescendants()) do
		local child = bindings[d]
		if child then
			child.reset()
		end
	end
end

function UIHelpers.bindHoversUnder(root, opts)
	if not root then
		return
	end
	if root:IsA("GuiButton") then
		UIHelpers.bindButtonHover(root, opts)
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("GuiButton") then
			UIHelpers.bindButtonHover(desc, opts)
		end
	end
end

function UIHelpers.animatePanelOpen(frame, opts)
	opts = opts or {}
	if not frame or not frame:IsA("GuiObject") then
		return
	end

	local center = opts.center or UDim2.new(0.5, 0, 0.5, 0)
	local startPos = opts.startPos or UDim2.new(0.5, 0, 0.56, 0)
	local duration = opts.duration or 0.35

	-- Invalidate any in-flight close callback
	frame:SetAttribute("CloseToken", (frame:GetAttribute("CloseToken") or 0) + 1)

	-- Only on a real open: switching tabs re-runs this on an already-open panel.
	-- Throttled because several controllers close or open together off the same
	-- attribute change, and three copies of one whoosh reads as a glitch.
	if not frame.Visible then
		playUISound("PanelOpen", { throttle = 0.15 })
	end

	frame.Visible = true
	frame.Position = startPos

	local scale = getOrCreateUIScale(frame, "PanelUIScale")
	scale.Scale = 0.96
	TweenService:Create(
		scale,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	frame:TweenPosition(
		center,
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Back,
		duration,
		true
	)
end

function UIHelpers.animatePanelClose(frame, opts, onDone)
	opts = opts or {}
	if not frame or not frame:IsA("GuiObject") then
		if onDone then onDone() end
		return
	end
	if not frame.Visible then
		if onDone then onDone() end
		return
	end

	local endPos = opts.endPos or UDim2.new(0.5, 0, 0.56, 0)
	local duration = opts.duration or 0.2
	local token = (frame:GetAttribute("CloseToken") or 0) + 1
	frame:SetAttribute("CloseToken", token)

	--[[
		Hiding a frame does not fire MouseLeave on the buttons inside it, so a
		panel closed while the cursor sat on a button used to reopen with that
		button still grown and tinted. Put them all back to rest.
	]]
	UIHelpers.resetHoversUnder(frame)

	playUISound("PanelClose", { throttle = 0.15 })

	local scale = frame:FindFirstChild("PanelUIScale")
	if scale and scale:IsA("UIScale") then
		TweenService:Create(
			scale,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.96 }
		):Play()
	end

	frame:TweenPosition(
		endPos,
		Enum.EasingDirection.In,
		Enum.EasingStyle.Quad,
		duration,
		true,
		function()
			if frame:GetAttribute("CloseToken") ~= token then
				return
			end
			frame.Visible = false
			if onDone then
				onDone()
			end
		end
	)
end

return UIHelpers
