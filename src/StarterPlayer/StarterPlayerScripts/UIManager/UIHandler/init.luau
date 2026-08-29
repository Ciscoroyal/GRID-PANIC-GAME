local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local HUD = PlayerGui:WaitForChild("HUD")
local Templates = script:WaitForChild("Templates")

local Fusion = require(script.Fusion)

local HoverSound = script:WaitForChild("Hover")
local ClickSound = script:WaitForChild("Click")
local CloseSound = script:WaitForChild("Close")
local OpenSound = script:WaitForChild("Open")

local Blur = Lighting:FindFirstChildOfClass("BlurEffect")

if not Blur then
	Blur = Instance.new("BlurEffect")
	Blur.Name = "UIBlur"
	Blur.Size = 0
	Blur.Parent = Lighting
end

local function derivedSound(name: string, playbackSpeed: number, volume: number): Sound
	local sound = ClickSound:Clone()
	sound.Name = name
	sound.PlaybackSpeed = playbackSpeed
	sound.Volume = volume
	sound.Parent = script

	return sound
end


local SpinTickSound = derivedSound("SpinTick", 1.35, 0.35)
local SpinRevealLow = derivedSound("SpinRevealLow", 0.72, 0.85)
local SpinRevealHigh = derivedSound("SpinRevealHigh", 1.8, 0.7)

local SHAKE_PRESETS = {
	Tiny   = { Intensity = 0.3, Duration = 0.15, Decay = 8 },
	Small  = { Intensity = 0.8, Duration = 0.25, Decay = 6 },
	Medium = { Intensity = 2.0, Duration = 0.4,  Decay = 5 },
	Heavy  = { Intensity = 5.0, Duration = 0.6,  Decay = 4 },
	Impact = { Intensity = 8.0, Duration = 0.3,  Decay = 10 },
}

local UI = {}

UI.DamageCounter = require(script.DamageCounter)
UI.NumberAnimator = require(script.NumberAnimator)
UI.Progression = require(script:WaitForChild("UIProgression"))
UI.Dialogue = require(script:WaitForChild("UIDialogue"))
UI.Notifications = require(script.NotificationHandler).new({
	holder = HUD:WaitForChild("Notification"),
	messageTemplate = Templates:WaitForChild("Message"),
	warningTemplate = Templates:WaitForChild("Warning"),
	successTemplate = Templates:WaitForChild("Success")
})

UI.DamageCounter.Setup(Templates:WaitForChild("DamageCounter"))

local scope = Fusion.scoped(Fusion)

local connectionsByOwner = {}
local buttonSprings = {}
local activeShakes = {}
local activeFOVTween: Tween? = nil

local baseFOV: number? = nil

local function dropConnections(owner: Instance)
	local connections = connectionsByOwner[owner]
	if not connections then
		return
	end

	connectionsByOwner[owner] = nil

	for _, connection in connections do
		connection:Disconnect()
	end
end

local function storeConnection(owner: Instance, connection: RBXScriptConnection)
	local connections = connectionsByOwner[owner]

	if not connections then
		connections = {}
		connectionsByOwner[owner] = connections

		owner.Destroying:Once(function()
			dropConnections(owner)
		end)
	end

	table.insert(connections, connection)
end

function UI.setupButton(button: GuiButton, onClick: (() -> ())?)
	button:SetAttribute("UIButtonBound", true)
	dropConnections(button)

	local spring = buttonSprings[button]

	if not spring then
		local buttonScope = Fusion.innerScope(scope)
		local value = buttonScope:Value(button.Size)
		buttonScope:Hydrate(button)({ Size = buttonScope:Spring(value, 18, 0.5) })

		spring = { Value = value, BaseSize = button.Size }
		buttonSprings[button] = spring

		button.Destroying:Once(function()
			Fusion.doCleanup(buttonScope)
			buttonSprings[button] = nil
		end)
	end

	local base = spring.BaseSize

	storeConnection(button, button.MouseButton1Up:Connect(function()
		spring.Value:set(UDim2.fromScale(base.X.Scale * 0.85, base.Y.Scale * 0.85))

		task.delay(0.1, function()
			spring.Value:set(base)
		end)

		if button.Name ~= "Close" then ClickSound:Play() else CloseSound:Play() end

		if onClick then
			task.spawn(onClick)
		end
	end))

	storeConnection(button, button.MouseEnter:Connect(function()
		spring.Value:set(UDim2.fromScale(base.X.Scale * 1.05, base.Y.Scale * 1.05))
		HoverSound:Play()
	end))

	storeConnection(button, button.MouseLeave:Connect(function()
		spring.Value:set(base)
	end))
end

local PANEL_Z = 51
local DIM_TRANSPARENCY = 0.45
local DIM_BLUR = 14
local OPEN_SCALE = 0.65
local CLOSE_SCALE = 0

local OPEN_TWEEN = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local CLOSE_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SWAP_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local DIM_IN_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DIM_OUT_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local panelStates = {}
local activeTweens = {}
local liftedNav = {}
local activePanel: GuiObject? = nil
local dimmer: TextButton? = nil

local function play(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local previous = activeTweens[instance]

	if previous then
		previous:Cancel()
	end

	local tween = TweenService:Create(instance, info, goal)
	activeTweens[instance] = tween

	tween.Completed:Once(function()
		if activeTweens[instance] == tween then
			activeTweens[instance] = nil
		end
	end)

	tween:Play()

	return tween
end

local function scaleOf(guiObject: GuiObject): UIScale
	local uiScale = guiObject:FindFirstChild("UIPanelScale")

	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIPanelScale"
		uiScale.Parent = guiObject
	end

	return uiScale :: UIScale
end

local function getDimmer(parent: Instance): TextButton
	if dimmer and dimmer.Parent == parent then
		return dimmer
	end

	if dimmer then
		dimmer:Destroy()
	end

	local frame = Instance.new("TextButton")
	frame.Name = "PanelDim"
	frame.Text = ""
	frame.AutoButtonColor = false
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(60, 60)
	frame.BackgroundColor3 = Color3.new()
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = PANEL_Z - 1
	frame.Visible = false
	frame:SetAttribute("UIButtonBound", true)
	frame.Parent = parent

	frame.MouseButton1Click:Connect(function()
		if activePanel then
			UI.CloseFrame(activePanel)
		end
	end)

	dimmer = frame

	return frame
end

local function setNavLifted(lifted: boolean)
	for guiObject, homeZIndex in liftedNav do
		guiObject.ZIndex = if lifted then PANEL_Z + 1 else homeZIndex
	end
end

function UI.KeepAbovePanels(guiObject: GuiObject)
	if not guiObject or liftedNav[guiObject] ~= nil then
		return
	end

	liftedNav[guiObject] = guiObject.ZIndex

	guiObject.Destroying:Once(function()
		liftedNav[guiObject] = nil
	end)
end

local function stateOf(panel: GuiObject)
	local state = panelStates[panel]

	if not state then
		state = { Token = 0, Home = panel.Position, ZIndex = panel.ZIndex }
		panelStates[panel] = state

		panel.Destroying:Once(function()
			panelStates[panel] = nil
		end)
	end

	return state
end

local function closePanel(panel: GuiObject, swapping: boolean?)
	local state = panelStates[panel]

	if not state or not panel.Visible then
		return
	end

	state.Token += 1
	local token = state.Token

	if activePanel == panel then
		activePanel = nil
	end

	local info = if swapping then SWAP_TWEEN else CLOSE_TWEEN
	local uiScale = scaleOf(panel)
	local scaleTween = play(uiScale, info, { Scale = CLOSE_SCALE })

	scaleTween.Completed:Once(function(playbackState)
		if playbackState ~= Enum.PlaybackState.Completed or state.Token ~= token then
			return
		end

		panel.Visible = false
		panel.Position = state.Home
		panel.ZIndex = state.ZIndex
		uiScale.Scale = 1
	end)

	if swapping then
		return
	end

	CloseSound:Play()
	setNavLifted(false)
	play(Blur, DIM_OUT_TWEEN, { Size = 0 })

	if dimmer then
		local fading = dimmer

		play(fading, DIM_OUT_TWEEN, { BackgroundTransparency = 1 }).Completed:Once(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed and not activePanel then
				fading.Visible = false
			end
		end)
	end
end

local function openPanel(panel: GuiObject, _origin: GuiObject?)
	local parent = panel.Parent
	if not parent then
		return
	end

	if activePanel == panel and panel.Visible then
		return
	end

	if activePanel and activePanel ~= panel then
		closePanel(activePanel, true)
	end

	local state = stateOf(panel)
	local wasVisible = panel.Visible
	state.Token += 1

	activePanel = panel

	local dim = getDimmer(parent)
	dim.Visible = true
	setNavLifted(true)

	play(dim, DIM_IN_TWEEN, { BackgroundTransparency = DIM_TRANSPARENCY })
	play(Blur, DIM_IN_TWEEN, { Size = DIM_BLUR })

	local uiScale = scaleOf(panel)

	if not wasVisible then
		uiScale.Scale = OPEN_SCALE
	end

	panel.Position = state.Home
	panel.Rotation = 0
	panel.ZIndex = PANEL_Z
	panel.Visible = true

	play(uiScale, OPEN_TWEEN, { Scale = 1 })
	play(panel, OPEN_TWEEN, { Position = state.Home })

	OpenSound:Play()
end

function UI.OpenFrame(frame: GuiObject, origin: GuiObject?)
	if frame then
		openPanel(frame, origin)
	end
end

function UI.CloseFrame(frame: GuiObject)
	if frame then
		closePanel(frame)
	end
end

function UI.ActivePanel(): GuiObject?
	return activePanel
end

function UI.CloseAllFrames()
	if activePanel then
		closePanel(activePanel)
	end
end

function UI.ToggleFrame(frame: GuiObject, origin: GuiObject?)
	if not frame then
		return
	end

	if activePanel == frame then
		closePanel(frame)
	else
		openPanel(frame, origin)
	end
end

function UI.ChangeText(label: TextLabel, text: string)
	if not label then
		return
	end

	label.Text = text

	local shadow = label:FindFirstChildOfClass("TextLabel")
	if shadow then
		shadow.Text = text
	end
end

local gradientFolder: Instance? = nil

local function gradientsFolder(): Instance?
	if gradientFolder and gradientFolder.Parent then
		return gradientFolder
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	gradientFolder = assets and assets:FindFirstChild("Gradients") or nil

	return gradientFolder
end

function UI.GetGradient(name: string): UIGradient?
	local folder = gradientsFolder()
	local found = folder and folder:FindFirstChild(name)

	return (found and found:IsA("UIGradient")) and found or nil
end

function UI.ApplyGradient(guiObject: GuiObject?, name: string, keepRotation: boolean?): boolean
	if not guiObject then
		return false
	end

	local source = UI.GetGradient(name)
	if not source then
		return false
	end

	local target = guiObject:FindFirstChildWhichIsA("UIGradient")

	if not target then
		target = source:Clone()
		target.Parent = guiObject

		return true
	end

	target.Color = source.Color
	target.Transparency = source.Transparency
	target.Offset = source.Offset

	if not keepRotation then
		target.Rotation = source.Rotation
	end

	return true
end

local function effectScaleOf(guiObject: GuiObject): UIScale
	local uiScale = guiObject:FindFirstChild("UIEffectScale")

	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "UIEffectScale"
		uiScale.Parent = guiObject
	end

	return uiScale :: UIScale
end

function UI.Pulse(guiObject: GuiObject?, startScale: number?, duration: number?): Tween?
	if not guiObject then
		return nil
	end

	local uiScale = effectScaleOf(guiObject)
	uiScale.Scale = startScale or 0.8

	return play(
		uiScale,
		TweenInfo.new(duration or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
end

function UI.Flash(guiObject: GuiObject?, color: Color3, duration: number?)
	if not guiObject then
		return
	end

	duration = duration or 0.4

	local flash = Instance.new("Frame")
	flash.Name = "UIFlash"
	flash.Active = false
	flash.AnchorPoint = Vector2.new(0.5, 0.5)
	flash.Position = UDim2.fromScale(0.5, 0.5)
	flash.Size = UDim2.fromScale(1.05, 1.25)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 0.2
	flash.BorderSizePixel = 0
	flash.ZIndex = guiObject.ZIndex + 8
	flash.Parent = guiObject

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.25, 0)
	corner.Parent = flash

	play(
		flash,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromScale(1.8, 2.1),
			BackgroundTransparency = 1,
		}
	)

	task.delay(duration + 0.05, function()
		if flash.Parent then
			flash:Destroy()
		end
	end)
end

function UI.Burst(guiObject: GuiObject?, color: Color3, count: number?)
	if not guiObject then
		return
	end

	count = math.max(1, math.floor(count or 16))

	for index = 1, count do
		local particle = Instance.new("Frame")
		local size = math.random(6, 13)

		particle.Name = "UIBurst"
		particle.Active = false
		particle.AnchorPoint = Vector2.new(0.5, 0.5)
		particle.Position = UDim2.fromScale(0.5, 0.5)
		particle.Size = UDim2.fromOffset(size, size)
		particle.Rotation = math.random(0, 90)
		particle.BackgroundColor3 = if index % 4 == 0 then Color3.new(1, 1, 1) else color
		particle.BackgroundTransparency = 0
		particle.BorderSizePixel = 0
		particle.ZIndex = guiObject.ZIndex + 10
		particle.Parent = guiObject

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.25, 0)
		corner.Parent = particle

		local angle = (index / count) * math.pi * 2 + math.random() * 0.35
		local distance = math.random(65, 150)
		local x = math.cos(angle) * distance
		local y = math.sin(angle) * distance
		local travelTime = 0.35 + math.random() * 0.25
		local delayTime = math.random() * 0.08

		task.delay(delayTime, function()
			if not particle.Parent then
				return
			end

			play(
				particle,
				TweenInfo.new(travelTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{
					Position = UDim2.new(0.5, x, 0.5, y),
					Size = UDim2.fromOffset(0, 0),
					Rotation = particle.Rotation + math.random(90, 240),
					BackgroundTransparency = 1,
				}
			)

			task.delay(travelTime + 0.05, function()
				if particle.Parent then
					particle:Destroy()
				end
			end)
		end)
	end
end

function UI.PlaySpinTick(progress: number?)
	progress = math.clamp(progress or 0, 0, 1)
	SpinTickSound:Stop()
	SpinTickSound.TimePosition = 0
	SpinTickSound.PlaybackSpeed = 1.15 + progress * 0.75
	SpinTickSound.Volume = 0.28 + progress * 0.2
	SpinTickSound:Play()
end

function UI.PlaySpinReveal()
	SpinRevealLow:Stop()
	SpinRevealLow.TimePosition = 0
	SpinRevealLow:Play()

	task.delay(0.07, function()
		SpinRevealHigh:Stop()
		SpinRevealHigh.TimePosition = 0
		SpinRevealHigh:Play()
	end)
end

function UI.ShakeText(label: TextLabel, intensity: number?, duration: number?, owner: Instance?): RBXScriptConnection
	intensity = intensity or 2

	local basePosition = label.Position
	local elapsed = 0

	local connection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		elapsed += deltaTime

		if duration and elapsed >= duration then
			connection:Disconnect()
			label.Position = basePosition
			return
		end

		label.Position = basePosition
			+ UDim2.fromOffset(
				(math.random() * 2 - 1) * intensity,
				(math.random() * 2 - 1) * intensity
			)
	end)

	if owner then
		storeConnection(owner, connection)
	end

	return connection
end

function UI.SetBar(bar: Frame, fillFraction: number, duration: number?)
	fillFraction = math.clamp(fillFraction, 0, 1)

	TweenService:Create(
		bar,
		TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.new(fillFraction, 0, 1, 0) }
	):Play()
end

function UI.SetFOV(targetFOV: number, duration: number?)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	if not baseFOV then
		baseFOV = camera.FieldOfView
	end

	if activeFOVTween then
		activeFOVTween:Cancel()
	end

	activeFOVTween = TweenService:Create(
		camera,
		TweenInfo.new(duration or 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ FieldOfView = targetFOV }
	)
	activeFOVTween:Play()
end

function UI.ResetFOV(duration: number?)

	if not baseFOV then
		return
	end

	UI.SetFOV(baseFOV, duration or 0.4)
end

function UI.SetBaseFOV(fov: number)
	baseFOV = fov
end

function UI.ShakeCamera(preset: string, intensityMultiplier: number?)
	local settings = SHAKE_PRESETS[preset]

	if not settings then
		warn("[UIHandler] Unknown shake preset: " .. tostring(preset))
		return
	end

	table.insert(activeShakes, {
		Intensity = settings.Intensity * (intensityMultiplier or 1),
		Duration = settings.Duration,
		Elapsed = 0,
		Decay = settings.Decay,
	})
end

RunService.RenderStepped:Connect(function(deltaTime)
	if #activeShakes == 0 then
		return
	end

	local totalOffset = Vector3.zero

	for index = #activeShakes, 1, -1 do
		local shake = activeShakes[index]
		shake.Elapsed += deltaTime

		if shake.Elapsed >= shake.Duration then
			table.remove(activeShakes, index)
		else
			local falloff = math.exp(-shake.Decay * (shake.Elapsed / shake.Duration))
			local magnitude = shake.Intensity * falloff

			totalOffset += Vector3.new(
				(math.random() * 2 - 1) * magnitude,
				(math.random() * 2 - 1) * magnitude,
				0
			)
		end
	end

	local camera = workspace.CurrentCamera
	if camera then
		camera.CFrame = camera.CFrame * CFrame.new(totalOffset)
	end
end)

function UI.setupViewport(viewportFrame: ViewportFrame, subject: Instance?, options: { [string]: any }?)
	for _, child in viewportFrame:GetChildren() do
		if child:IsA("Camera") or child:IsA("WorldModel") or child:IsA("Model") or child:IsA("BasePart") then
			child:Destroy()
		end
	end

	if not subject then
		return
	end

	options = options or {}

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame

	local clone = subject:Clone()
	clone.Parent = worldModel

	local function configurePart(part: BasePart)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end

	local cf, size

	if clone:IsA("BasePart") then
		configurePart(clone)
		clone.CFrame = CFrame.new() * (options.Rotation or CFrame.new())
		cf, size = clone.CFrame, clone.Size
	elseif clone:IsA("Model") then
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				configurePart(descendant)
			end
		end

		cf, size = clone:GetBoundingBox()

		if options.Center then
			clone:PivotTo(CFrame.new(-cf.Position) * clone:GetPivot())

			if options.Rotation then
				clone:PivotTo(options.Rotation * clone:GetPivot())
			end

			cf, size = clone:GetBoundingBox()
		end
	else
		worldModel:Destroy()
		return
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = options.FieldOfView or 28
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	local maxSize = math.max(size.X, size.Y, size.Z, 0.1)
	local distance = (maxSize / 2) / math.tan(math.rad(camera.FieldOfView) / 2)
	distance *= options.DistanceScale or 1.45

	local target = cf.Position + (options.TargetOffset or Vector3.zero)
	local offset = options.CameraOffset or Vector3.new(0.12, 0.12, 1)

	camera.CFrame = CFrame.lookAt(
		target + Vector3.new(maxSize * offset.X, maxSize * offset.Y, distance * offset.Z),
		target
	)
end

return UI
