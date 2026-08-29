local TweenService = game:GetService("TweenService")

local NotificationHandler = {}
NotificationHandler.__index = NotificationHandler

export type NotifyOptions = {
	kind: string?,
	duration: number?,
	key: string?,
}

export type Config = {
	holder: GuiObject,
	template: GuiObject?,
	messageTemplate: GuiObject?,
	warningTemplate: GuiObject?,
	successTemplate: GuiObject?,
	maxVisible: number?,
	defaultDuration: number?,
	duplicateExtendSeconds: number?,
	tweenIn: TweenInfo?,
	tweenOut: TweenInfo?,
	tweenPulse: TweenInfo?,
	messageNames: { string }?,
	countNames: { string }?,
	progressNames: { string }?,
	kindNames: { string }?,
}

type FadeTarget = {
	instance: Instance,
	property: string,
	value: number,
}

type CachedRefs = {
	message: Instance?,
	count: Instance?,
	progress: GuiObject?,
	kind: Instance?,
}

type NotificationRecord = {
	frame: GuiObject,
	refs: CachedRefs,
	fadeTargets: { FadeTarget },
	message: string,
	kind: string,
	key: string,
	count: number,
	layoutOrder: number,
	deadline: number,
	totalLifetime: number,
	removing: boolean,
	expireThread: thread?,
	progressTween: Tween?,
	baseSize: UDim2,
	progressBaseSize: UDim2?,
}

local DEFAULTS = {
	maxVisible = 6,
	defaultDuration = 4,
	duplicateExtendSeconds = 2.5,
	tweenIn = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	tweenOut = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	tweenPulse = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	messageNames = { "Message", "Text", "Title", "Label" },
	countNames = { "Count", "Multiplier", "StackCount" },
	progressNames = { "Progress", "TimerBar", "TimeBar" },
	kindNames = { "Kind", "Type", "NotificationType" },
}

local VALID_KINDS = {
	message = true,
	warning = true,
	success = true,
}

local function mergeConfig(config: Config): any
	assert(config, "NotificationHandler.new requires a config table.")
	assert(config.holder, "NotificationHandler.new requires config.holder.")
	assert(
		config.template or config.messageTemplate or config.warningTemplate or config.successTemplate,
		"NotificationHandler.new requires a template."
	)

	local merged = table.clone(DEFAULTS)

	for key, value in config :: any do
		merged[key] = value
	end

	return merged
end

local function normalizeKind(kind: string?): string
	local lowered = string.lower(kind or "message")

	if VALID_KINDS[lowered] then
		return lowered
	end

	return "message"
end

local function isTextObject(instance: Instance?): boolean
	return instance ~= nil
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function findFirst(root: Instance, names: { string }): Instance?
	for _, name in names do
		local found = root:FindFirstChild(name, true)

		if found then
			return found
		end
	end

	return nil
end

local function setText(instance: Instance?, text: string)
	if not isTextObject(instance) then
		return
	end

	(instance :: TextLabel).Text = text

	local nested = instance:FindFirstChildOfClass("TextLabel")
	if nested then
		nested.Text = text
	end
end

local function getTemplate(config: any, kind: string): GuiObject
	return config[kind .. "Template"] or config.template or config.messageTemplate or config.successTemplate or config.warningTemplate 
end

local function makeKey(message: string, kind: string, customKey: string?): string
	return customKey or kind .. ":" .. message
end

local function tween(instance: Instance, info: TweenInfo, properties: { [string]: any }): Tween
	local created = TweenService:Create(instance, info, properties)
	created:Play()

	return created
end

local function playKindSound(kind: string)
	local sound = script:FindFirstChild(kind)

	if not sound or not sound:IsA("Sound") then
		return
	end

	local pitchShift = sound:FindFirstChildOfClass("PitchShiftSoundEffect")
	if pitchShift then
		pitchShift.Octave = 1 + math.random(0, 3) / 100
	end

	sound:Play()
end

local function scaledSize(size: UDim2, ratio: number): UDim2
	return UDim2.new(size.X.Scale * ratio, size.X.Offset * ratio, size.Y.Scale, size.Y.Offset)
end

local function cacheRefs(frame: GuiObject, config: any): CachedRefs
	local progress = findFirst(frame, config.progressNames)

	return {
		message = findFirst(frame, config.messageNames),
		count = findFirst(frame, config.countNames),
		progress = progress and progress:IsA("GuiObject") and progress or nil,
		kind = findFirst(frame, config.kindNames),
	}
end

local function cacheFadeTargets(frame: GuiObject): { FadeTarget }
	local targets = {}

	table.insert(targets, {
		instance = frame,
		property = "BackgroundTransparency",
		value = frame.BackgroundTransparency,
	})

	for _, descendant in frame:GetDescendants() do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			table.insert(targets, {
				instance = descendant,
				property = "TextTransparency",
				value = descendant.TextTransparency,
			})
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			table.insert(targets, {
				instance = descendant,
				property = "ImageTransparency",
				value = descendant.ImageTransparency,
			})
		elseif descendant:IsA("UIStroke") then
			table.insert(targets, {
				instance = descendant,
				property = "Transparency",
				value = descendant.Transparency,
			})
		elseif descendant:IsA("GuiObject") then
			table.insert(targets, {
				instance = descendant,
				property = "BackgroundTransparency",
				value = descendant.BackgroundTransparency,
			})
		end
	end

	return targets
end

local function setFade(targets: { FadeTarget }, value: number)
	for _, target in targets do
		target.instance[target.property] = value
	end
end

local function tweenFade(targets: { FadeTarget }, info: TweenInfo, visible: boolean)
	for _, target in targets do
		tween(target.instance, info, {
			[target.property] = visible and target.value or 1,
		})
	end
end

function NotificationHandler.new(config: Config)
	local self = setmetatable({}, NotificationHandler)

	self.config = mergeConfig(config)
	self.holder = self.config.holder
	self.activeByKey = {}
	self.active = {}
	self.nextLayoutOrder = 0
	self.destroyed = false

	return self
end

function NotificationHandler:_nextOrder(): number
	self.nextLayoutOrder += 1

	return self.nextLayoutOrder
end

function NotificationHandler:_setNewest(record: NotificationRecord)
	record.layoutOrder = self:_nextOrder()
	record.frame.LayoutOrder = record.layoutOrder

	for index, item in self.active do
		if item == record then
			table.remove(self.active, index)
			break
		end
	end

	table.insert(self.active, record)
end

function NotificationHandler:_applyText(record: NotificationRecord)
	local countText = ""
	if record.count > 1 then
		countText = "[x" .. record.count .. "]"
	end

	setText(record.refs.kind, record.kind)

	if isTextObject(record.refs.count) then
		(record.refs.count :: TextLabel).Visible = record.count > 1
		setText(record.refs.count, countText)
		setText(record.refs.message, record.message)
		return
	end

	local suffix = ""
	if countText ~= "" then
		suffix = " " .. countText
	end

	setText(record.refs.message, record.message .. suffix)
end

function NotificationHandler:_playProgress(record: NotificationRecord)
	if record.progressTween then
		record.progressTween:Cancel()
		record.progressTween = nil
	end

	local progress = record.refs.progress
	local baseSize = record.progressBaseSize

	if not progress or not baseSize then
		return
	end

	local remaining = math.max(record.deadline - os.clock(), 0)
	local ratio = math.clamp(remaining / record.totalLifetime, 0, 1)
	progress.Size = scaledSize(baseSize, ratio)

	record.progressTween = tween(
		progress,
		TweenInfo.new(remaining, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Size = scaledSize(baseSize, 0) }
	)
end

function NotificationHandler:_scheduleRemoval(record: NotificationRecord)
	if record.expireThread then
		task.cancel(record.expireThread)
		record.expireThread = nil
	end

	record.expireThread = task.delay(math.max(record.deadline - os.clock(), 0), function()
		record.expireThread = nil

		if not record.removing then
			self:_remove(record)
		end
	end)
end

function NotificationHandler:_animateIn(record: NotificationRecord)
	local frame = record.frame
	frame.Visible = true
	frame.ClipsDescendants = true
	frame.Size = UDim2.new(record.baseSize.X.Scale, record.baseSize.X.Offset, 0, 0)

	setFade(record.fadeTargets, 1)
	tween(frame, self.config.tweenIn, { Size = record.baseSize })
	tweenFade(record.fadeTargets, self.config.tweenIn, true)
end

function NotificationHandler:_pulse(record: NotificationRecord)
	local baseSize = record.baseSize
	local bigger = UDim2.new(baseSize.X.Scale, baseSize.X.Offset + 6, baseSize.Y.Scale, baseSize.Y.Offset)
	local grow = tween(record.frame, self.config.tweenPulse, { Size = bigger })

	local connection
	connection = grow.Completed:Connect(function()
		connection:Disconnect()

		if record.frame.Parent and not record.removing then
			tween(record.frame, self.config.tweenPulse, { Size = baseSize })
		end
	end)
end

function NotificationHandler:_remove(record: NotificationRecord)
	if record.removing then
		return
	end

	record.removing = true
	self.activeByKey[record.key] = nil

	if record.expireThread then
		task.cancel(record.expireThread)
		record.expireThread = nil
	end

	if record.progressTween then
		record.progressTween:Cancel()
		record.progressTween = nil
	end

	for index, item in self.active do
		if item == record then
			table.remove(self.active, index)
			break
		end
	end

	local outTween = tween(record.frame, self.config.tweenOut, {
		Size = UDim2.new(record.baseSize.X.Scale, record.baseSize.X.Offset, 0, 0),
	})

	tweenFade(record.fadeTargets, self.config.tweenOut, false)

	local connection
	connection = outTween.Completed:Connect(function()
		connection:Disconnect()
		record.frame:Destroy()
	end)
end

function NotificationHandler:_trimOverflow()
	while #self.active > self.config.maxVisible do
		self:_remove(self.active[1])
	end
end

function NotificationHandler:Notify(
	message: string,
	kindOrOptions: (string | NotifyOptions)?,
	duration: number?,
	noSound: boolean?
): NotificationRecord
	assert(typeof(message) == "string", "Notification message must be a string.")

	local options: NotifyOptions = {}

	if typeof(kindOrOptions) == "table" then
		options = kindOrOptions :: NotifyOptions
	else
		options.kind = kindOrOptions :: string?
		options.duration = duration
	end

	local kind = normalizeKind(options.kind)
	local lifetime = math.max(options.duration or self.config.defaultDuration, 0.5)
	local key = makeKey(message, kind, options.key)
	local existing = self.activeByKey[key]

	if existing and not existing.removing then
		existing.count += 1
		existing.deadline += self.config.duplicateExtendSeconds
		existing.totalLifetime += self.config.duplicateExtendSeconds

		self:_setNewest(existing)
		self:_applyText(existing)

		if not noSound then
			playKindSound(kind)
		end

		self:_playProgress(existing)
		self:_scheduleRemoval(existing)
		self:_pulse(existing)

		return existing
	end

	local template = getTemplate(self.config, kind)
	assert(template, "No notification template is configured for " .. kind .. ".")

	local frame = template:Clone()
	frame.Name = template.Name .. "_Notification"
	frame.Parent = self.holder

	local record: NotificationRecord = {
		frame = frame,
		refs = cacheRefs(frame, self.config),
		fadeTargets = cacheFadeTargets(frame),
		message = message,
		kind = kind,
		key = key,
		count = 1,
		layoutOrder = self:_nextOrder(),
		deadline = os.clock() + lifetime,
		totalLifetime = lifetime,
		removing = false,
		expireThread = nil,
		progressTween = nil,
		baseSize = frame.Size,
		progressBaseSize = nil,
	}

	if record.refs.progress then
		record.progressBaseSize = record.refs.progress.Size
	end

	frame.LayoutOrder = record.layoutOrder
	self.activeByKey[key] = record
	table.insert(self.active, record)

	self:_applyText(record)

	if not noSound then
		playKindSound(kind)
	end

	self:_animateIn(record)
	self:_playProgress(record)
	self:_scheduleRemoval(record)
	self:_trimOverflow()

	return record
end

function NotificationHandler:Message(message: string, duration: number?): NotificationRecord
	return self:Notify(message, "message", duration)
end

function NotificationHandler:Warning(message: string, duration: number?, noSound: boolean?): NotificationRecord
	return self:Notify("[!] " .. message, "warning", duration, noSound)
end

function NotificationHandler:Success(message: string, duration: number?, noSound: boolean?): NotificationRecord
	return self:Notify( message, "success", duration, noSound)
end
function NotificationHandler:Clear()
	for index = #self.active, 1, -1 do
		self:_remove(self.active[index])
	end
end

function NotificationHandler:Destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true

	for index = #self.active, 1, -1 do
		local record = self.active[index]

		if record.expireThread then
			task.cancel(record.expireThread)
		end

		if record.progressTween then
			record.progressTween:Cancel()
		end

		record.frame:Destroy()
	end

	table.clear(self.active)
	table.clear(self.activeByKey)
end

return NotificationHandler
