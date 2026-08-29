--!strict

-- Tagged UI effects share one scheduler. Hidden, clipped, disabled, and off-screen
-- objects keep their state but do not receive visual updates.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Observers = require(ReplicatedStorage.Shared.ClientModules.Utility.Observers)
local MainUI = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("HUD")

local SPIN_ROTATION_SPEED = 45
local RAINBOW_CYCLE_SECONDS = 2
local VISIBILITY_INTERVAL = 0.2
local shineInfo = TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.In, -1, false)
local hoverInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

type TweenEffect = {
	Tween: Tween,
	Playing: boolean,
}

local spins: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local rainbows: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local tweenEffects: { [GuiObject]: TweenEffect } = setmetatable({}, { __mode = "k" }) :: any
local scheduler: RBXScriptConnection? = nil
local visibilityElapsed = 0

local function intersects(
	firstPosition: Vector2,
	firstSize: Vector2,
	secondPosition: Vector2,
	secondSize: Vector2
): boolean
	return firstPosition.X < secondPosition.X + secondSize.X
		and firstPosition.X + firstSize.X > secondPosition.X
		and firstPosition.Y < secondPosition.Y + secondSize.Y
		and firstPosition.Y + firstSize.Y > secondPosition.Y
end

local function worldGuiOnScreen(gui: BillboardGui | SurfaceGui): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end

	local adornee = gui.Adornee
	local position: Vector3?
	if adornee and adornee:IsA("BasePart") then
		position = adornee.Position
	elseif adornee and adornee:IsA("Attachment") then
		position = adornee.WorldPosition
	elseif gui.Parent and gui.Parent:IsA("BasePart") then
		position = gui.Parent.Position
	elseif gui.Parent and gui.Parent:IsA("Attachment") then
		position = gui.Parent.WorldPosition
	end
	if not position then
		return false
	end

	local viewportPoint, onScreen = camera:WorldToViewportPoint(position)
	return onScreen and viewportPoint.Z > 0
end

local function isEffectivelyVisible(object: GuiObject): boolean
	if not object.Parent or not object.Visible or object.AbsoluteSize.X <= 0 or object.AbsoluteSize.Y <= 0 then
		return false
	end

	local objectPosition = object.AbsolutePosition
	local objectSize = object.AbsoluteSize
	local camera = Workspace.CurrentCamera
	if camera and not intersects(objectPosition, objectSize, Vector2.zero, camera.ViewportSize) then
		return false
	end
	local ancestor: Instance? = object.Parent
	while ancestor do
		if ancestor:IsA("GuiObject") then
			if not ancestor.Visible then
				return false
			end
			if ancestor:IsA("CanvasGroup") and ancestor.GroupTransparency >= 1 then
				return false
			end
			if ancestor.ClipsDescendants and not intersects(
				objectPosition,
				objectSize,
				ancestor.AbsolutePosition,
				ancestor.AbsoluteSize
			) then
				return false
			end
		elseif ancestor:IsA("ScreenGui") then
			if not ancestor.Enabled then
				return false
			end
		elseif ancestor:IsA("BillboardGui") or ancestor:IsA("SurfaceGui") then
			if not ancestor.Enabled or not worldGuiOnScreen(ancestor) then
				return false
			end
		end
		ancestor = ancestor.Parent
	end
	return true
end

local function hasEffects(): boolean
	return next(spins) ~= nil or next(rainbows) ~= nil or next(tweenEffects) ~= nil
end

local function ensureScheduler()
	if scheduler then
		return
	end
	scheduler = RunService.RenderStepped:Connect(function(deltaTime)
		local now = os.clock()
		for object in spins do
			if not object.Parent then
				spins[object] = nil
			elseif isEffectivelyVisible(object) then
				object.Rotation = (object.Rotation + SPIN_ROTATION_SPEED * deltaTime) % 360
			end
		end

		local rainbowColor = Color3.fromHSV((now / RAINBOW_CYCLE_SECONDS) % 1, 1, 1)
		for object in rainbows do
			if not object.Parent then
				rainbows[object] = nil
			elseif isEffectivelyVisible(object) then
				if object:IsA("ImageLabel") or object:IsA("ImageButton") then
					object.ImageColor3 = rainbowColor
				else
					object.BackgroundColor3 = rainbowColor
				end
			end
		end

		visibilityElapsed += deltaTime
		if visibilityElapsed >= VISIBILITY_INTERVAL then
			visibilityElapsed = 0
			for object, effect in tweenEffects do
				if not object.Parent then
					effect.Tween:Cancel()
					tweenEffects[object] = nil
				else
					local visible = isEffectivelyVisible(object)
					if visible ~= effect.Playing then
						effect.Playing = visible
						if visible then
							effect.Tween:Play()
						else
							effect.Tween:Pause()
						end
					end
				end
			end
		end

		if not hasEffects() and scheduler then
			scheduler:Disconnect()
			scheduler = nil
		end
	end)
end

local function registerTween(object: GuiObject, tween: Tween)
	tweenEffects[object] = {
		Tween = tween,
		Playing = false,
	}
	ensureScheduler()
end

Observers.observeTag("SpinUI", function(object: GuiObject)
	if not object:IsA("GuiObject") then
		return function() end
	end
	spins[object] = true
	ensureScheduler()
	return function()
		spins[object] = nil
	end
end, { MainUI })

Observers.observeTag("HoverUI", function(object: GuiObject)
	if not object:IsA("GuiObject") then
		return function() end
	end
	local originalPosition = object.Position
	local targetPosition = UDim2.new(
		originalPosition.X.Scale,
		originalPosition.X.Offset,
		originalPosition.Y.Scale - 0.075,
		originalPosition.Y.Offset
	)
	local tween = TweenService:Create(object, hoverInfo, { Position = targetPosition })
	registerTween(object, tween)
	return function()
		tweenEffects[object] = nil
		tween:Cancel()
		if object.Parent then
			object.Position = originalPosition
		end
	end
end, { MainUI, Workspace })

Observers.observeTag("Shiny", function(object: GuiObject)
	if not object:IsA("GuiObject") then
		return function() end
	end
	local originalPosition = object.Position
	object.Position = UDim2.fromScale(-0.5, 0.5)
	local tween = TweenService:Create(object, shineInfo, { Position = UDim2.fromScale(1.5, 0.5) })
	registerTween(object, tween)
	return function()
		tweenEffects[object] = nil
		tween:Cancel()
		if object.Parent then
			object.Position = originalPosition
		end
	end
end, { MainUI })

Observers.observeTag("Rainbow", function(object: GuiObject)
	if not object:IsA("GuiObject") then
		return function() end
	end
	rainbows[object] = true
	ensureScheduler()
	return function()
		rainbows[object] = nil
	end
end, { MainUI, Workspace })
