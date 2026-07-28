local ReplicatedStorage = game:GetService("ReplicatedStorage")
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local textLabel = script.Parent

-- This function updates the text every time the invisible stopwatch changes
survivalTimeValue.Changed:Connect(function(newTime)
	-- math.floor chops off all the messy decimals so it looks like a clean timer
	local seconds = math.floor(newTime)

	-- This formats the number into a classic clock layout (e.g., 0:45, 1:20)
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60

	-- string.format ensures single-digit seconds always have a zero (0:05 instead of 0:5)
	textLabel.Text = string.format("%d:%02d", minutes, remainingSeconds)
end)