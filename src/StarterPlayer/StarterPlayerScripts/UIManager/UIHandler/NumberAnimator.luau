local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FormatNumber = require(ReplicatedStorage.Shared.FormatNumber)

local STEP_TIME = 0.05
local COMPACT_ABOVE = 10000
local STEPS_PER_COUNT = 15

local NumberAnimator = {}

NumberAnimator.GameLoaded = false

local animating = {}

local function changeText(label: TextLabel, text: string)
	if not label then
		return
	end

	label.Text = text

	local nested = label:FindFirstChildOfClass("TextLabel")
	if nested then
		nested.Text = text
	end
end

local function renderValue(isCurrency: boolean?, label: TextLabel, value: number)
	if isCurrency and value > COMPACT_ABOVE then
		changeText(label, FormatNumber.FormatCompact(value, 1, 2))
	else
		changeText(label, FormatNumber.FormatInt(value))
	end
end

local function playSound(name: string)
	local sound = script:FindFirstChild(name)

	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

function NumberAnimator.SetInstant(label: TextLabel, amount: number, isCurrency: boolean?)
	if not label then
		return
	end

	animating[label] = nil
	renderValue(isCurrency, label, math.floor((tonumber(amount) or 0) + 0.5))
end

function NumberAnimator.Animate(label: TextLabel, newAmount: number, oldAmount: number, isCurrency: boolean?)
	if not label or not oldAmount then
		warn("[NumberAnimator] Animate needs a label and a starting amount")
		return
	end

	newAmount = math.floor(newAmount + 0.5)

	if not NumberAnimator.GameLoaded then
		renderValue(isCurrency, label, newAmount)
		animating[label] = nil
		return
	end

	local state = animating[label]

	if not state then
		state = { displayed = oldAmount, running = false, baseSize = label.Size }
		animating[label] = state
	end

	local previous = state.displayed
	state.target = newAmount

	if newAmount == previous then
		renderValue(isCurrency, label, newAmount)
		return
	end

	if newAmount < previous then
		playSound("Purchase")
	end

	if state.running then
		return
	end

	state.running = true

	local base = state.baseSize

	TweenService:Create(
		label,
		TweenInfo.new(0.8, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ Size = UDim2.new(base.X.Scale * 1.05, base.X.Offset, base.Y.Scale * 1.05, base.Y.Offset) }
	):Play()

	task.spawn(function()
		while true do
			local current = animating[label]

			if not current or current.displayed == current.target then
				break
			end

			local difference = current.target - current.displayed
			local step = math.max(1, math.ceil(math.abs(difference) / STEPS_PER_COUNT))

			if difference > 0 then
				current.displayed = math.min(current.displayed + step, current.target)

				if isCurrency then
					playSound("Cash")
				end
			else
				current.displayed = math.max(current.displayed - step, current.target)
			end

			renderValue(isCurrency, label, current.displayed)
			task.wait(STEP_TIME)
		end

		local finished = animating[label]
		if finished then
			finished.running = false
		end

		TweenService:Create(
			label,
			TweenInfo.new(0.15, Enum.EasingStyle.Bounce, Enum.EasingDirection.In),
			{ Size = base }
		):Play()
	end)
end

return NumberAnimator
