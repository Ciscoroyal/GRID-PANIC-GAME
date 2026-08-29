--!strict

-- UIProgression
-- Pooled 2D icon feedback, UI transfers, bursts, and ordinary screen bars.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

assert(RunService:IsClient(), "UIProgression can only run on the client")

local systems = ReplicatedStorage:WaitForChild("Systems")
local shared = ReplicatedStorage:WaitForChild("Shared")
local ImageConfig = require(shared:WaitForChild("ImageConfig"))
local SoundConfig = require(shared:WaitForChild("SoundConfig"))
local SoundController = require(systems:WaitForChild("SoundController"))
local localPlayer = Players.LocalPlayer

local feedbackTemplate = script:WaitForChild("Feedbacktemp")
local progressionTemplate = script:WaitForChild("ProgressionTemp")
assert(feedbackTemplate:IsA("GuiObject"), "UIProgression.Feedbacktemp must be a GuiObject")
assert(progressionTemplate:IsA("GuiObject"), "UIProgression.ProgressionTemp must be a GuiObject")

export type UITarget = Vector2 | UDim2 | GuiObject

export type FeedbackBatch = {
	Count: number,
	Remaining: number,
	Arrived: number,
	Completed: boolean,
}

export type TransferOptions = {
	Duration: number?,
	Stagger: number?,
	StartRadius: number?,
	Curve: number?,
	RandomStart: boolean?,
	Icon: string?,
	Text: string?,
	Template: "Progression" | "Feedback"?,
	Size: UDim2?,
	Fade: boolean?,
	FadeStart: number?,
	AnimateEndpoint: boolean?,
	BounceTarget: GuiObject?,
	EndpointScale: number?,
	PlaySound: boolean?,
	Sound: string?,
	SoundOptions: SoundController.StepProgressiveOptions?,
	FillBar: GuiObject?,
	FillDirection: "LeftToRight" | "RightToLeft" | "TopToBottom" | "BottomToTop"?,
	CurrentValue: number?,
	NewValue: number?,
	MaxValue: number?,
	TextRoot: Instance?,
	ValueFormat: string?,
	MaxFormat: string?,
	LevelFormat: string?,
	OnEach: ((index: number, item: GuiObject) -> ())?,
	OnComplete: ((batch: FeedbackBatch) -> ())?,
}

export type BurstOptions = {
	Count: number?,
	MinCount: number?,
	MaxCount: number?,
	Origin: UITarget?,
	Duration: number?,
	Stagger: number?,
	BurstRadius: number?,
	Icon: string?,
	Text: string?,
	Template: "Progression" | "Feedback"?,
	Size: UDim2?,
	Fade: boolean?,
	FadeStart: number?,
	PlaySound: boolean?,
	Sound: string?,
	SoundOptions: SoundController.StepProgressiveOptions?,
	OnEach: ((index: number, item: GuiObject) -> ())?,
	OnComplete: ((batch: FeedbackBatch) -> ())?,
}

export type BarOptions = {
	Duration: number?,
	FillDirection: "LeftToRight" | "RightToLeft" | "TopToBottom" | "BottomToTop"?,
	TextRoot: Instance?,
	ValueFormat: string?,
	MaxFormat: string?,
	LevelFormat: string?,
	PlaySound: boolean?,
	Sound: string?,
	SoundOptions: SoundController.StepProgressiveOptions?,
	SoundSteps: number?,
	OnComplete: ((newValue: number, maxValue: number) -> ())?,
}

type Layout = {
	Size: UDim2,
	Position: UDim2,
	AnchorPoint: Vector2,
}

local UIProgression = {}

local pools: { [string]: { GuiObject } } = {
	Feedback = {},
	Progression = {},
}
local motions: { any } = {}
local barMotions: { [GuiObject]: any } = {}
local barLayouts: { [GuiObject]: Layout } = setmetatable({}, { __mode = "k" }) :: any
local bounces: { [GuiObject]: any } = {}
local scheduler: RBXScriptConnection? = nil
local overlay: Frame? = nil
local nextSequence = 0

local function readNumber(name: string, fallback: number): number
	local value = script:FindFirstChild(name)
	return if value and value:IsA("NumberValue") then value.Value else fallback
end

local function sequenceId(): string
	nextSequence += 1
	return "UIProgression_" .. nextSequence
end

local function safeCall(callback: any, ...: any)
	if type(callback) ~= "function" then
		return
	end
	local arguments = table.pack(...)
	task.spawn(function()
		local ok, message = xpcall(function()
			callback(table.unpack(arguments, 1, arguments.n))
		end, debug.traceback)
		if not ok then
			warn("[UIProgression] Callback failed:\n" .. message)
		end
	end)
end

local function getOverlay(): Frame
	if overlay and overlay.Parent then
		return overlay
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui")
	local screen = playerGui:FindFirstChild("UIProgressionOverlay")
	if not screen then
		local created = Instance.new("ScreenGui")
		created.Name = "UIProgressionOverlay"
		created.DisplayOrder = 1000
		created.IgnoreGuiInset = true
		created.ResetOnSpawn = false
		created.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		created.Parent = playerGui
		screen = created
	end
	assert(screen:IsA("ScreenGui"), "PlayerGui.UIProgressionOverlay must be a ScreenGui")

	local effects = screen:FindFirstChild("Effects")
	if not effects then
		local created = Instance.new("Frame")
		created.Name = "Effects"
		created.BackgroundTransparency = 1
		created.Size = UDim2.fromScale(1, 1)
		created.Parent = screen
		effects = created
	end
	assert(effects:IsA("Frame"), "UIProgressionOverlay.Effects must be a Frame")
	overlay = effects
	return effects
end

local function screenSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1920, 1080)
end

local function screenPosition(target: UITarget?): Vector2
	if target == nil then
		return screenSize() * 0.5
	end
	local kind = typeof(target)
	if kind == "Vector2" then
		return target :: Vector2
	elseif kind == "UDim2" then
		local position = target :: UDim2
		local size = screenSize()
		return Vector2.new(
			position.X.Scale * size.X + position.X.Offset,
			position.Y.Scale * size.Y + position.Y.Offset
		)
	end
	local gui = target :: GuiObject
	return gui.AbsolutePosition + gui.AbsoluteSize * 0.5
end

local function findIcon(root: Instance): ImageLabel?
	local icon = root:FindFirstChild("Icon", true)
	if icon and icon:IsA("ImageLabel") then
		return icon
	end
	return root:FindFirstChildWhichIsA("ImageLabel", true)
end

local function findText(root: Instance): TextLabel?
	local label = root:FindFirstChild("Mult", true)
	if label and label:IsA("TextLabel") then
		return label
	end
	return root:FindFirstChildWhichIsA("TextLabel", true)
end

local function templateFor(kind: "Progression" | "Feedback"): GuiObject
	return if kind == "Feedback" then feedbackTemplate else progressionTemplate
end

local function acquire(kind: "Progression" | "Feedback"): (GuiObject, ImageLabel, TextLabel?)
	local template = templateFor(kind)
	local item = table.remove(pools[kind])
	if not item then
		item = template:Clone()
	end

	item.Name = template.Name
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.BackgroundTransparency = template.BackgroundTransparency
	item.Rotation = 0
	item.Size = template.Size
	item.Visible = true

	local icon = findIcon(item)
	local templateIcon = findIcon(template)
	assert(icon and templateIcon, template:GetFullName() .. " must contain an ImageLabel named Icon")
	icon.Image = templateIcon.Image
	icon.ImageColor3 = templateIcon.ImageColor3
	icon.ImageTransparency = templateIcon.ImageTransparency

	local label = findText(item)
	local templateLabel = findText(template)
	if label and templateLabel then
		label.Text = templateLabel.Text
		label.TextColor3 = templateLabel.TextColor3
		label.TextTransparency = templateLabel.TextTransparency
	end

	item.Parent = getOverlay()
	return item, icon, label
end

local function release(item: GuiObject, kind: "Progression" | "Feedback")
	item.Visible = false
	item.Parent = nil
	local maxPool = math.max(0, math.floor(readNumber("MaxPool", 96)))
	if #pools.Feedback + #pools.Progression < maxPool then
		table.insert(pools[kind], item)
	else
		item:Destroy()
	end
end

local function playProgressive(data: any)
	if not data.PlaySound then
		return
	end
	local sound = SoundConfig.Get(data.SoundName)
	if sound then
		SoundController.PlayProgressive2D(sound, data.SequenceId, data.SoundOptions)
	end
end

local function scaleUDim(value: UDim, multiplier: number): UDim
	return UDim.new(value.Scale * multiplier, math.round(value.Offset * multiplier))
end

local function addUDim(left: UDim, right: UDim): UDim
	return UDim.new(left.Scale + right.Scale, left.Offset + right.Offset)
end

local function subtractUDim(left: UDim, right: UDim): UDim
	return UDim.new(left.Scale - right.Scale, left.Offset - right.Offset)
end

local function layoutFor(bar: GuiObject): Layout
	local layout = barLayouts[bar]
	if not layout then
		layout = {
			Size = bar.Size,
			Position = bar.Position,
			AnchorPoint = bar.AnchorPoint,
		}
		barLayouts[bar] = layout
	end
	return layout
end

local function setBarFraction(bar: GuiObject, fraction: number, direction: string)
	local layout = layoutFor(bar)
	local amount = math.clamp(fraction, 0, 1)
	local size = layout.Size
	local position = layout.Position
	local anchor = layout.AnchorPoint

	if direction == "RightToLeft" then
		local right = addUDim(position.X, scaleUDim(size.X, 1 - anchor.X))
		bar.AnchorPoint = Vector2.new(1, anchor.Y)
		bar.Position = UDim2.new(right, position.Y)
		bar.Size = UDim2.new(scaleUDim(size.X, amount), size.Y)
	elseif direction == "BottomToTop" then
		local bottom = addUDim(position.Y, scaleUDim(size.Y, 1 - anchor.Y))
		bar.AnchorPoint = Vector2.new(anchor.X, 1)
		bar.Position = UDim2.new(position.X, bottom)
		bar.Size = UDim2.new(size.X, scaleUDim(size.Y, amount))
	elseif direction == "TopToBottom" then
		local top = subtractUDim(position.Y, scaleUDim(size.Y, anchor.Y))
		bar.AnchorPoint = Vector2.new(anchor.X, 0)
		bar.Position = UDim2.new(position.X, top)
		bar.Size = UDim2.new(size.X, scaleUDim(size.Y, amount))
	else
		local left = subtractUDim(position.X, scaleUDim(size.X, anchor.X))
		bar.AnchorPoint = Vector2.new(0, anchor.Y)
		bar.Position = UDim2.new(left, position.Y)
		bar.Size = UDim2.new(scaleUDim(size.X, amount), size.Y)
	end
end

local function formatted(pattern: string, current: number, maximum: number): string
	local text = string.gsub(pattern, "{current}", tostring(math.round(current)))
	return string.gsub(text, "{max}", tostring(math.round(maximum)))
end

local function updateLabels(root: Instance, current: number, maximum: number, options: any)
	for _, name in { "Max", "Level", "Value" } do
		local label = root:FindFirstChild(name, true)
		if label and label:IsA("TextLabel") then
			local pattern = options[name .. "Format"] or options.ValueFormat or "{current}/{max}"
			label.Text = formatted(pattern, current, maximum)
		end
	end
end

local function bounce(target: GuiObject, amount: number)
	local scale = target:FindFirstChild("UIProgressionScale")
	if scale and not scale:IsA("UIScale") then
		scale = nil
	end
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "UIProgressionScale"
		scale.Parent = target
	end
	local previous = bounces[target]
	bounces[target] = {
		Scale = scale,
		Base = if previous then previous.Base else scale.Scale,
		Amount = amount,
		StartedAt = os.clock(),
		Duration = 0.24,
	}
end

local function makeBatch(count: number, options: any): any
	return {
		Count = count,
		Remaining = count,
		Arrived = 0,
		Completed = false,
		PlaySound = options.PlaySound ~= false,
		SoundName = options.Sound or options.Icon or "Default",
		SoundOptions = options.SoundOptions,
		SequenceId = sequenceId(),
		AnimateEndpoint = options.AnimateEndpoint ~= false,
		BounceTarget = options.BounceTarget,
		EndpointScale = options.EndpointScale or readNumber("EndpointScale", 1.12),
		FillBar = options.FillBar,
		FillDirection = options.FillDirection or "LeftToRight",
		CurrentValue = options.CurrentValue or 0,
		NewValue = options.NewValue or 0,
		MaxValue = options.MaxValue,
		TextRoot = options.TextRoot,
		ValueFormat = options.ValueFormat,
		MaxFormat = options.MaxFormat,
		LevelFormat = options.LevelFormat,
		OnEach = options.OnEach,
		OnComplete = options.OnComplete,
	}
end

local function arrived(entry: any)
	local batch = entry.Batch
	batch.Arrived += 1
	batch.Remaining -= 1
	playProgressive(batch)

	if batch.BounceTarget and batch.AnimateEndpoint then
		bounce(batch.BounceTarget, batch.EndpointScale - 1)
	end

	if batch.FillBar and batch.MaxValue and batch.MaxValue > 0 then
		local ratio = batch.Arrived / batch.Count
		local value = batch.CurrentValue + (batch.NewValue - batch.CurrentValue) * ratio
		setBarFraction(batch.FillBar, value / batch.MaxValue, batch.FillDirection)
		updateLabels(batch.TextRoot or batch.FillBar.Parent, value, batch.MaxValue, batch)
	end

	safeCall(batch.OnEach, batch.Arrived, entry.Item)
	release(entry.Item, entry.Kind)

	if batch.Remaining <= 0 then
		batch.Completed = true
		safeCall(batch.OnComplete, batch)
	end
end

local function hasWork(): boolean
	return #motions > 0 or next(barMotions) ~= nil or next(bounces) ~= nil
end

local function ensureScheduler()
	if scheduler then
		return
	end
	scheduler = RunService.Heartbeat:Connect(function()
		local now = os.clock()

		for index = #motions, 1, -1 do
			local entry = motions[index]
			if now < entry.StartedAt then
				continue
			end
			local alpha = math.clamp((now - entry.StartedAt) / entry.Duration, 0, 1)
			local eased = 1 - (1 - alpha) ^ 3
			local endPosition = entry.EndPosition
			if entry.EndTarget then
				local ok, livePosition = pcall(screenPosition, entry.EndTarget)
				if ok then
					endPosition = livePosition
				end
			end
			local inverse = 1 - eased
			local position = inverse ^ 2 * entry.StartPosition
				+ 2 * inverse * eased * entry.ControlPosition
				+ eased ^ 2 * endPosition
			entry.Item.Position = UDim2.fromOffset(position.X, position.Y)
			entry.Item.Rotation = entry.Rotation * alpha

			if entry.Fade then
				local fadeAlpha = math.clamp(
					(alpha - entry.FadeStart) / math.max(0.001, 1 - entry.FadeStart),
					0,
					1
				)
				entry.Icon.ImageTransparency = entry.BaseImageTransparency
					+ (1 - entry.BaseImageTransparency) * fadeAlpha
				if entry.Text then
					entry.Text.TextTransparency = entry.BaseTextTransparency
						+ (1 - entry.BaseTextTransparency) * fadeAlpha
				end
			end

			if alpha >= 1 then
				motions[index] = motions[#motions]
				motions[#motions] = nil
				arrived(entry)
			end
		end

		for bar, motion in barMotions do
			if not bar.Parent then
				barMotions[bar] = nil
				continue
			end
			local alpha = math.clamp((now - motion.StartedAt) / motion.Duration, 0, 1)
			local eased = 1 - (1 - alpha) ^ 2
			local value = motion.StartValue + (motion.EndValue - motion.StartValue) * eased
			setBarFraction(bar, value / motion.MaxValue, motion.Direction)
			updateLabels(motion.TextRoot, value, motion.MaxValue, motion.Options)

			if motion.PlaySound then
				local desired = math.floor(alpha * motion.SoundSteps)
				while motion.PlayedSteps < desired do
					motion.PlayedSteps += 1
					playProgressive(motion)
				end
			end

			if alpha >= 1 then
				barMotions[bar] = nil
				safeCall(motion.OnComplete, motion.EndValue, motion.MaxValue)
			end
		end

		for target, data in bounces do
			if not target.Parent or not data.Scale.Parent then
				bounces[target] = nil
				continue
			end
			local alpha = math.clamp((now - data.StartedAt) / data.Duration, 0, 1)
			data.Scale.Scale = data.Base + data.Amount * math.sin(alpha * math.pi)
			if alpha >= 1 then
				data.Scale.Scale = data.Base
				bounces[target] = nil
			end
		end

		if not hasWork() and scheduler then
			scheduler:Disconnect()
			scheduler = nil
		end
	end)
end

function UIProgression.PlayTransfer(
	startTarget: UITarget?,
	endTarget: UITarget,
	count: number,
	options: TransferOptions?
): FeedbackBatch
	local settings = options or {}
	count = math.max(1, math.floor(count))
	local endPosition = screenPosition(endTarget)
	local duration = math.max(0.05, settings.Duration or readNumber("DefaultDuration", 0.8))
	local stagger = math.max(0, settings.Stagger or readNumber("DefaultStagger", 0.055))
	local radius = settings.StartRadius or 90
	local curve = settings.Curve or 120
	local kind = settings.Template or (if settings.Text ~= nil then "Feedback" else "Progression")
	local batch = makeBatch(count, settings)
	if typeof(endTarget) == "Instance" and (endTarget :: Instance):IsA("GuiObject") and not batch.BounceTarget then
		batch.BounceTarget = endTarget
	end

	for index = 1, count do
		local item, icon, label = acquire(kind)
		icon.Image = ImageConfig.Resolve(settings.Icon or "Default")
		if settings.Text ~= nil and label then
			label.Text = settings.Text
		end
		if settings.Size then
			item.Size = settings.Size
		end

		local startPosition: Vector2
		if startTarget == nil or settings.RandomStart then
			local size = screenSize()
			startPosition = Vector2.new(math.random() * size.X, math.random() * size.Y)
		else
			startPosition = screenPosition(startTarget)
			local angle = math.random() * math.pi * 2
			startPosition += Vector2.new(math.cos(angle), math.sin(angle)) * math.random() * radius
		end

		local midpoint = (startPosition + endPosition) * 0.5
		local side = if math.random() < 0.5 then -1 else 1
		item.Position = UDim2.fromOffset(startPosition.X, startPosition.Y)
		table.insert(motions, {
			Item = item,
			Icon = icon,
			Text = label,
			Kind = kind,
			Batch = batch,
			StartPosition = startPosition,
			ControlPosition = midpoint + Vector2.new(side * curve * (0.5 + math.random()), -curve),
			EndPosition = endPosition,
			EndTarget = endTarget,
			StartedAt = os.clock() + (index - 1) * stagger * (0.75 + math.random() * 0.5),
			Duration = duration * (0.84 + math.random() * 0.32),
			Rotation = math.random(-220, 220),
			Fade = settings.Fade == true,
			FadeStart = settings.FadeStart or readNumber("FadeStart", 0.65),
			BaseImageTransparency = icon.ImageTransparency,
			BaseTextTransparency = if label then label.TextTransparency else 0,
		})
	end

	ensureScheduler()
	return batch
end

function UIProgression.PlayBurst(options: BurstOptions?): FeedbackBatch
	local settings = options or {}
	local minimum = math.max(1, math.floor(settings.MinCount or 10))
	local maximum = math.max(minimum, math.floor(settings.MaxCount or 18))
	local count = math.max(1, math.floor(settings.Count or math.random(minimum, maximum)))
	local origin = screenPosition(settings.Origin)
	local viewport = screenSize()
	local duration = math.max(0.2, settings.Duration or 1.15)
	local kind = settings.Template or (if settings.Text ~= nil then "Feedback" else "Progression")
	local batch = makeBatch(count, settings)
	batch.AnimateEndpoint = false
	batch.BounceTarget = nil

	for index = 1, count do
		local item, icon, label = acquire(kind)
		icon.Image = ImageConfig.Resolve(settings.Icon or "Default")
		if settings.Text ~= nil and label then
			label.Text = settings.Text
		end
		if settings.Size then
			item.Size = settings.Size
		end

		local angle = math.random() * math.pi * 2
		local radius = settings.BurstRadius or 420
		local control = origin + Vector2.new(
			math.cos(angle) * radius * (0.45 + math.random()),
			-math.abs(math.sin(angle)) * radius - 80
		)
		local endPosition = Vector2.new(
			math.clamp(
				control.X + math.random(-math.floor(radius * 0.9), math.floor(radius * 0.9)),
				-40,
				viewport.X + 40
			),
			viewport.Y + 80
		)
		item.Position = UDim2.fromOffset(origin.X, origin.Y)
		table.insert(motions, {
			Item = item,
			Icon = icon,
			Text = label,
			Kind = kind,
			Batch = batch,
			StartPosition = origin,
			ControlPosition = control,
			EndPosition = endPosition,
			EndTarget = nil,
			StartedAt = os.clock() + (index - 1) * (settings.Stagger or 0.018),
			Duration = duration * (0.8 + math.random() * 0.45),
			Rotation = math.random(-540, 540),
			Fade = settings.Fade ~= false,
			-- Bursts fade for most of their downward fall instead of disappearing at the edge.
			FadeStart = settings.FadeStart or 0.35,
			BaseImageTransparency = icon.ImageTransparency,
			BaseTextTransparency = if label then label.TextTransparency else 0,
		})
	end

	ensureScheduler()
	return batch
end

function UIProgression.AnimateBar(
	bar: GuiObject,
	currentValue: number,
	newValue: number,
	maxValue: number,
	options: BarOptions?
)
	assert(maxValue > 0, "maxValue must be greater than zero")
	local settings = options or {}
	local duration = math.max(0.01, settings.Duration or readNumber("BarDuration", 0.45))
	local increasing = newValue > currentValue
	local soundSteps = math.max(1, math.floor(
		settings.SoundSteps or math.min(readNumber("DefaultSoundSteps", 8), math.max(1, math.ceil(newValue - currentValue)))
	))

	barMotions[bar] = {
		StartedAt = os.clock(),
		Duration = duration,
		StartValue = currentValue,
		EndValue = newValue,
		MaxValue = maxValue,
		Direction = settings.FillDirection or "LeftToRight",
		TextRoot = settings.TextRoot or bar.Parent,
		Options = settings,
		PlaySound = increasing and settings.PlaySound ~= false,
		SoundName = settings.Sound or "BarFill",
		SoundOptions = settings.SoundOptions,
		SequenceId = sequenceId(),
		SoundSteps = soundSteps,
		PlayedSteps = 0,
		OnComplete = settings.OnComplete,
	}
	setBarFraction(bar, currentValue / maxValue, settings.FillDirection or "LeftToRight")
	updateLabels(settings.TextRoot or bar.Parent, currentValue, maxValue, settings)
	ensureScheduler()
end

function UIProgression.CancelBar(bar: GuiObject)
	barMotions[bar] = nil
end

function UIProgression.ClearPool()
	for _, selectedPool in pools do
		for _, item in selectedPool do
			item:Destroy()
		end
		table.clear(selectedPool)
	end
end

function UIProgression.DestroyAll()
	for _, entry in motions do
		release(entry.Item, entry.Kind)
	end
	table.clear(motions)
	table.clear(barMotions)
	for target, data in bounces do
		if data.Scale and data.Scale.Parent then
			data.Scale.Scale = data.Base
		end
		bounces[target] = nil
	end
	if scheduler then
		scheduler:Disconnect()
		scheduler = nil
	end
	if overlay and overlay.Parent and overlay.Parent:IsA("ScreenGui") then
		overlay.Parent:Destroy()
	end
	overlay = nil
	UIProgression.ClearPool()
end

return UIProgression
