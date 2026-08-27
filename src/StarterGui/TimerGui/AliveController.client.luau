local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local aliveStatusValue = ReplicatedStorage:WaitForChild("AliveStatus")
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local timerGui = script.Parent

local CORE_DIFFICULTY_TIME = 95
local DEFAULT_COLOR = Color3.new(1, 1, 1)
local URGENCY_COLOR = Color3.fromRGB(255, 90, 90)

local aliveLabel = timerGui:WaitForChild("AliveLabel")

local function ensureModeLabelOffset()
	local modeLabel = timerGui:FindFirstChild("ModeLabel")
	if not modeLabel then
		return
	end
	modeLabel.Position = UDim2.new(
		aliveLabel.Position.X.Scale,
		aliveLabel.Position.X.Offset,
		aliveLabel.Position.Y.Scale + aliveLabel.Size.Y.Scale + 0.006,
		aliveLabel.Position.Y.Offset
	)
	modeLabel.Size = UDim2.new(aliveLabel.Size.X.Scale, 0, aliveLabel.Size.Y.Scale * 0.9, 0)
end

local pulseToken = 0
local pulsing = false

local function stopPulse()
	pulseToken += 1
	pulsing = false
	aliveLabel.TextColor3 = DEFAULT_COLOR
end

local function startUrgencyPulse()
	if pulsing then
		return
	end
	pulsing = true
	pulseToken += 1
	local token = pulseToken
	task.spawn(function()
		while token == pulseToken and aliveLabel.Parent and aliveLabel.Visible do
			local tweenIn = TweenService:Create(
				aliveLabel,
				TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ TextColor3 = URGENCY_COLOR }
			)
			tweenIn:Play()
			tweenIn.Completed:Wait()
			if token ~= pulseToken then
				break
			end
			local tweenOut = TweenService:Create(
				aliveLabel,
				TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ TextColor3 = DEFAULT_COLOR }
			)
			tweenOut:Play()
			tweenOut.Completed:Wait()
		end
		if token == pulseToken then
			pulsing = false
		end
	end)
end

local function updateAlive()
	ensureModeLabelOffset()

	local text = aliveStatusValue.Value
	if typeof(text) ~= "string" or text == "" then
		aliveLabel.Visible = false
		aliveLabel.Text = ""
		stopPulse()
		return
	end

	aliveLabel.Text = text
	aliveLabel.Visible = true

	if survivalTimeValue.Value >= CORE_DIFFICULTY_TIME then
		startUrgencyPulse()
	else
		stopPulse()
	end
end

aliveStatusValue.Changed:Connect(updateAlive)
survivalTimeValue.Changed:Connect(function(newTime)
	if not aliveLabel.Visible then
		return
	end
	if newTime >= CORE_DIFFICULTY_TIME then
		startUrgencyPulse()
	else
		stopPulse()
	end
end)

task.spawn(function()
	for _ = 1, 40 do
		if timerGui:FindFirstChild("ModeLabel") then
			ensureModeLabelOffset()
			break
		end
		task.wait(0.1)
	end
end)

updateAlive()
