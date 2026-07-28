local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local block = script.Parent
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")

local triggered = false

local function eliminatePlayer(player, character, humanoid)
	if player:GetAttribute("HasShield") == true then
		player:SetAttribute("HasShield", nil)
		local shieldVis = character:FindFirstChild("ShieldVisual")
		if shieldVis then shieldVis:Destroy() end
		vfxEvent:FireClient(player, "LightShake")
	else
		humanoid.Health = 0
		vfxEvent:FireClient(player, "HeavyShake")
		print("Practice hazard eliminated " .. player.Name)
	end

	if block.Parent then
		block:Destroy()
	end
end

local function tryHitPart(hit)
	if triggered then return end

	local character = hit:FindFirstAncestorWhichIsA("Model")
	if not character or not character:FindFirstChild("Humanoid") then return end

	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character.Humanoid

	if player and player:GetAttribute("InPractice") == true and humanoid.Health > 0 then
		triggered = true
		eliminatePlayer(player, character, humanoid)
	end
end

block.Touched:Connect(tryHitPart)

task.spawn(function()
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {block.Parent}

	for _ = 1, 40 do
		if triggered or not block.Parent then return end

		for _, hit in ipairs(workspace:GetPartsInPart(block, overlapParams)) do
			tryHitPart(hit)
			if triggered then return end
		end

		task.wait(0.05)
	end
end)