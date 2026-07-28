local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local showRollCall = ReplicatedStorage:WaitForChild("ShowRollCall")
local timerGui = script.Parent

local timerLabel = timerGui:FindFirstChildWhichIsA("TextLabel")
if not timerLabel then
	return
end

local modeLabel = timerGui:FindFirstChild("ModeLabel")
if not modeLabel then
	modeLabel = timerLabel:Clone()
	modeLabel.Name = "ModeLabel"
	modeLabel.Position = UDim2.new(timerLabel.Position.X.Scale, timerLabel.Position.X.Offset, timerLabel.Position.Y.Scale + timerLabel.Size.Y.Scale + 0.008, timerLabel.Position.Y.Offset)
	modeLabel.Text = "LOBBY"
	modeLabel.Parent = timerGui

	local modeScript = modeLabel:FindFirstChildOfClass("LocalScript")
	if modeScript then
		modeScript:Destroy()
	end
end

local rollCallActive = false

showRollCall.OnClientEvent:Connect(function()
	rollCallActive = true
	task.delay(4.5, function()
		rollCallActive = false
	end)
end)

local function updateMode()
	if localPlayer:GetAttribute("InPractice") == true then
		modeLabel.Text = "PRACTICE"
	elseif localPlayer:GetAttribute("InArena") == true then
		modeLabel.Text = "SURVIVAL"
	elseif rollCallActive then
		modeLabel.Text = "ROLL CALL"
	elseif survivalTimeValue.Value >= 1 and survivalTimeValue.Value <= 15 then
		modeLabel.Text = "INTERMISSION"
	else
		modeLabel.Text = "LOBBY"
	end
end

survivalTimeValue.Changed:Connect(updateMode)
localPlayer:GetAttributeChangedSignal("InArena"):Connect(updateMode)
localPlayer:GetAttributeChangedSignal("InPractice"):Connect(updateMode)

task.spawn(function()
	while modeLabel.Parent do
		updateMode()
		task.wait(0.25)
	end
end)

updateMode()
