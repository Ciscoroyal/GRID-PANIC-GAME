local ReplicatedStorage = game:GetService("ReplicatedStorage")

local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local timerGui = script.Parent

local timerLabels = {}
for _, child in ipairs(timerGui:GetChildren()) do
	if child:IsA("TextLabel") and child.Name ~= "ModeLabel" then
		local timerScript = child:FindFirstChildOfClass("LocalScript")
		if timerScript then
			timerScript:Destroy()
		end
		table.insert(timerLabels, child)
	end
end

local function updateDisplay(newTime)
	local seconds = math.floor(newTime)
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	local text = string.format("%d:%02d", minutes, remainingSeconds)

	for _, label in ipairs(timerLabels) do
		label.Text = text
	end
end

survivalTimeValue.Changed:Connect(updateDisplay)
updateDisplay(survivalTimeValue.Value)
