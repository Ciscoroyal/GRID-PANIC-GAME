local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeData = require(ReplicatedStorage:WaitForChild("GameModeData"))
local localPlayer = Players.LocalPlayer
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local showRollCall = ReplicatedStorage:WaitForChild("ShowRollCall")
local currentGameMode = ReplicatedStorage:WaitForChild("CurrentGameMode")
local timerGui = script.Parent

local timerLabel = timerGui:FindFirstChildWhichIsA("TextLabel")
if not timerLabel then
	return
end

local modeLabel = timerGui:FindFirstChild("ModeLabel")
if not modeLabel then
	modeLabel = timerLabel:Clone()
	modeLabel.Name = "ModeLabel"
	local aliveLabel = timerGui:FindFirstChild("AliveLabel")
	if aliveLabel then
		modeLabel.Position = UDim2.new(
			aliveLabel.Position.X.Scale,
			aliveLabel.Position.X.Offset,
			aliveLabel.Position.Y.Scale + aliveLabel.Size.Y.Scale + 0.006,
			aliveLabel.Position.Y.Offset
		)
		modeLabel.Size = UDim2.new(aliveLabel.Size.X.Scale, 0, aliveLabel.Size.Y.Scale * 0.9, 0)
	else
		modeLabel.Position = UDim2.new(timerLabel.Position.X.Scale, timerLabel.Position.X.Offset, timerLabel.Position.Y.Scale + timerLabel.Size.Y.Scale + 0.008, timerLabel.Position.Y.Offset)
	end
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
	task.delay(3.2, function()
		rollCallActive = false
	end)
end)

local function modeDisplayName(modeId)
	if typeof(modeId) ~= "string" or modeId == "" then
		return nil
	end
	local mode = GameModeData.getById(modeId)
	return (mode and mode.displayName) or string.upper(modeId)
end

local function updateMode()
	if localPlayer:GetAttribute("InPractice") == true then
		modeLabel.Text = "PRACTICE"
	elseif localPlayer:GetAttribute("InArena") == true then
		modeLabel.Text = modeDisplayName(currentGameMode.Value) or "SURVIVAL"
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
currentGameMode.Changed:Connect(updateMode)

task.spawn(function()
	while modeLabel.Parent do
		updateMode()
		task.wait(0.25)
	end
end)

updateMode()
