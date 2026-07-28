local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local block = script.Parent
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")

local notified = {}

local function tryHitPart(hit)
	local character = hit:FindFirstAncestorWhichIsA("Model")
	if not character or not character:FindFirstChild("Humanoid") then return end

	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character.Humanoid

	if player and player:GetAttribute("InPractice") == true and humanoid.Health > 0 and not notified[player] then
		notified[player] = true
		vfxEvent:FireClient(player, "PracticeHit", "You were hit by a practice block!")
	end
end

block.Touched:Connect(tryHitPart)

task.spawn(function()
	local hazardModel = block:FindFirstAncestorWhichIsA("Model") or block.Parent
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {hazardModel}

	for _ = 1, 40 do
		if not block.Parent then return end

		for _, hit in ipairs(workspace:GetPartsInPart(block, overlapParams)) do
			tryHitPart(hit)
		end

		task.wait(0.1)
	end
end)