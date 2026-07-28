local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CoinRewards = require(ReplicatedStorage:WaitForChild("CoinRewards"))
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
		player:SetAttribute("IsEliminated", true)
		player:SetAttribute("CanSponsorThisRound", true)
		humanoid.Health = 0
		vfxEvent:FireClient(player, "HeavyShake")

		local t = ReplicatedStorage:WaitForChild("SurvivalTime").Value
		local multiplier = 1 + (3 / (1 + math.exp(-0.05 * (t - 45))))
		local totalPayout = math.floor(t * multiplier)
		local totalXP = math.floor((t * 1.5) * multiplier)

		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			local xpVal = leaderstats:FindFirstChild("XP")
			CoinRewards.awardCoins(player, totalPayout)
			if xpVal then xpVal.Value = xpVal.Value + totalXP end
		end

	end
end

local hazardModel = block:FindFirstAncestorWhichIsA("Model") or block.Parent

local function canStillKill()
	if not hazardModel or not hazardModel.Parent then
		return false
	end
	return hazardModel:GetAttribute("CanKill") ~= false
end

local function tryHitPart(hit)
	if triggered or not canStillKill() then return end

	local character = hit:FindFirstAncestorWhichIsA("Model")
	if not character or not character:FindFirstChild("Humanoid") then return end

	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character.Humanoid

	if player and player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true and humanoid.Health > 0 then
		triggered = true
		eliminatePlayer(player, character, humanoid)
	end
end

block.Touched:Connect(tryHitPart)

task.spawn(function()
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local hazardModel = block:FindFirstAncestorWhichIsA("Model") or block.Parent
	overlapParams.FilterDescendantsInstances = {hazardModel}

	for _ = 1, 40 do
		if triggered or not block.Parent or not canStillKill() then return end

		for _, hit in ipairs(workspace:GetPartsInPart(block, overlapParams)) do
			tryHitPart(hit)
			if triggered then return end
		end

		task.wait(0.1)
	end
end)