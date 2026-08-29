
local Players = game:GetService("Players")

local station = script.Parent
local player = Players.LocalPlayer
local debounce = false

station.Touched:Connect(function(hit)
	if debounce then return end
	local character = hit.Parent
	if character ~= player.Character then return end

	local tool = character:FindFirstChild("Squeegee")
	if not tool then return end

	local refillEvent = tool:FindFirstChild("Refill")
	if refillEvent then
		debounce = true
		refillEvent:Fire()
		task.wait(0.5)
		debounce = false
	end
end)
