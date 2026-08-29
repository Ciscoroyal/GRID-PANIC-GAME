local TweenService = game:GetService("TweenService")

local MAX_POOL = 30
local DURATION = 1
local FLOAT_HEIGHT = 2
local SPREAD = 3
local COMBINE_WINDOW = 0.15

local FLOAT_TWEEN = TweenInfo.new(DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local POP_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local LABEL_NAMES = { "Amount", "Damage", "Text", "Label" }

local STYLES = {
	damage = {
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 127)),
			ColorSequenceKeypoint.new(0.46, Color3.fromRGB(255, 0, 127)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		stroke = Color3.fromRGB(24, 0, 0),
		prefix = "-",
	},
	critical = {
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 170, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
		}),
		stroke = Color3.fromRGB(60, 0, 0),
		prefix = "CRIT ",
	},
	heal = {
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(85, 255, 0)),
		}),
		stroke = Color3.fromRGB(10, 72, 34),
		prefix = "+",
	},
	shield = {
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 255)),
		}),
		stroke = Color3.fromRGB(8, 42, 79),
		prefix = "",
	},
	miss = {
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(242, 247, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(145, 155, 171)),
		}),
		stroke = Color3.fromRGB(30, 34, 44),
		prefix = "",
	},
}

local DamageCounter = {}

local template = nil
local parent = nil
local pool = {}
local activeByKey = {}
local targetIds = {}
local nextTargetId = 0

local function findLabel(gui)
	for _, name in LABEL_NAMES do
		local found = gui:FindFirstChild(name, true)

		if found and found:IsA("TextLabel") then
			return found
		end
	end

	return gui:FindFirstChildWhichIsA("TextLabel", true)
end

local function getTargetPart(target)
	if target:IsA("BasePart") or target:IsA("Attachment") then
		return target
	end

	if target:IsA("Model") then
		return target.PrimaryPart
			or target:FindFirstChild("HumanoidRootPart")
			or target:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function getTargetKey(target, kind)
	local id = targetIds[target]

	if not id then
		nextTargetId += 1
		id = nextTargetId
		targetIds[target] = id
	end

	return tostring(id) .. ":" .. kind
end

local function cancelItem(item)
	for _, tween in item.tweens do
		tween:Cancel()
	end

	table.clear(item.tweens)

	if item.thread then
		if coroutine.status(item.thread) == "suspended" then
			task.cancel(item.thread)
		end

		item.thread = nil
	end
end

local function release(item)
	cancelItem(item)

	if item.key and activeByKey[item.key] == item then
		activeByKey[item.key] = nil
	end

	item.gui.Enabled = false
	item.gui.Adornee = nil
	item.gui.Size = item.baseSize
	item.gui.StudsOffsetWorldSpace = item.baseOffset
	item.inUse = false
	item.key = nil
	item.amount = 0
	item.combineUntil = 0
end

local function cloneItem()
	local gui = template:Clone()
	gui.Enabled = false
	gui.Parent = parent

	local label = findLabel(gui)
	local styled = label and label:FindFirstChildWhichIsA("TextLabel")
	local stroke = styled and styled:FindFirstChildWhichIsA("UIStroke") or nil
	local gradient = styled and styled:FindFirstChildWhichIsA("UIGradient") or nil
	local scale = nil

	if label then
		scale = label:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale", label)
	end

	return {
		gui = gui,
		label = label,
		stroke = stroke,
		gradient = gradient,
		scale = scale,
		baseSize = gui.Size,
		baseOffset = gui.StudsOffsetWorldSpace,
		tweens = {},
		thread = nil,
		inUse = false,
		key = nil,
		amount = 0,
		combineUntil = 0,
	}
end

local function takeItem()
	for _, item in pool do
		if not item.inUse then
			return item
		end
	end

	if #pool < MAX_POOL then
		local item = cloneItem()
		table.insert(pool, item)
		return item
	end

	local item = pool[1]
	release(item)

	return item
end

local function play(item, instance, tweenInfo, goal)
	local tween = TweenService:Create(instance, tweenInfo, goal)
	table.insert(item.tweens, tween)
	tween:Play()

	return tween
end

local function scaledSize(size, scale)
	return UDim2.new(size.X.Scale * scale, size.X.Offset * scale, size.Y.Scale * scale, size.Y.Offset * scale)
end

local function setText(item, amount, kind)
	local style = STYLES[kind] or STYLES.damage
	local label = item.label

	if not label then
		return
	end

	if typeof(amount) == "number" then
		label.Text = style.prefix .. tostring(math.floor(math.abs(amount) + 0.5))
	else
		label.Text = tostring(amount)
	end

	local nested = label:FindFirstChildOfClass("TextLabel")
	if nested then
		nested.Text = label.Text
	end

	label.TextTransparency = 0

	if item.gradient then
		item.gradient.Color = style.gradient
	end

	if item.stroke then
		item.stroke.Color = style.stroke
		item.stroke.Transparency = 0
	end
end

local function animate(item)
	cancelItem(item)

	local side = (math.random() - 0.5) * SPREAD
	local depth = (math.random() - 0.5) * SPREAD
	local startOffset = item.baseOffset + Vector3.new(side * 0.25, 0, depth * 0.25)
	local endOffset = startOffset + Vector3.new(side, FLOAT_HEIGHT, depth)

	item.gui.Enabled = true
	item.gui.StudsOffsetWorldSpace = startOffset

	if item.label then
		item.label.TextTransparency = 0
	end

	if item.stroke then
		item.stroke.Transparency = 0
	end

	if item.scale then
		item.scale.Scale = 0.65
		play(item, item.scale, POP_TWEEN, { Scale = 1 })
	else
		item.gui.Size = scaledSize(item.baseSize, 0.75)
		play(item, item.gui, POP_TWEEN, { Size = item.baseSize })
	end

	play(item, item.gui, FLOAT_TWEEN, { StudsOffsetWorldSpace = endOffset })

	if item.label then
		play(item, item.label, FADE_TWEEN, { TextTransparency = 1 })
	end

	if item.stroke then
		play(item, item.stroke, FADE_TWEEN, { Transparency = 1 })
	end

	item.thread = task.delay(DURATION, function()
		item.thread = nil
		release(item)
	end)
end

function DamageCounter.Setup(billboardTemplate, cloneParent)
	assert(
		billboardTemplate and billboardTemplate:IsA("BillboardGui"),
		"DamageCounter.Setup needs a BillboardGui template."
	)

	template = billboardTemplate
	parent = cloneParent or billboardTemplate.Parent

	assert(parent, "DamageCounter.Setup needs a parent for the clones.")

	template.Enabled = false
end

function DamageCounter.Show(target, amount, kind)
	assert(template, "Call DamageCounter.Setup(template) before showing damage.")

	kind = kind or "damage"

	if not target then
		return nil
	end

	local adornee = getTargetPart(target)
	if not adornee then
		return nil
	end

	local key = getTargetKey(target, kind)
	local now = os.clock()
	local existing = activeByKey[key]

	if existing and existing.inUse and typeof(amount) == "number" and now <= existing.combineUntil then
		existing.amount += amount
		existing.combineUntil = now + COMBINE_WINDOW

		setText(existing, existing.amount, kind)
		animate(existing)

		return existing
	end

	local item = takeItem()
	item.inUse = true
	item.gui.Adornee = adornee
	item.gui.Parent = adornee
	item.key = key
	item.amount = typeof(amount) == "number" and amount or 0
	item.combineUntil = now + COMBINE_WINDOW
	activeByKey[key] = item

	setText(item, amount, kind)
	animate(item)

	return item
end

function DamageCounter.Damage(target, amount, critical)
	return DamageCounter.Show(target, amount, critical and "critical" or "damage")
end

function DamageCounter.Heal(target, amount)
	return DamageCounter.Show(target, amount, "heal")
end

function DamageCounter.Shield(target, amount)
	return DamageCounter.Show(target, amount, "shield")
end

function DamageCounter.Miss(target)
	return DamageCounter.Show(target, "MISS", "miss")
end

function DamageCounter.Clear()
	for _, item in pool do
		if item.inUse then
			release(item)
		end
	end
end

return DamageCounter
