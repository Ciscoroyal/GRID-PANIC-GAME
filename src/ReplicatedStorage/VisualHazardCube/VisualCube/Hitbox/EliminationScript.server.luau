local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local EliminationService = require(ServerScriptService:WaitForChild("EliminationService"))
local block = script.Parent

local triggered = false

local function eliminatePlayer(player)
	EliminationService.eliminate(player, { cause = "hazard", respectShield = true })
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
		eliminatePlayer(player)
	end
end

block.Touched:Connect(tryHitPart)

task.spawn(function()
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local model = block:FindFirstAncestorWhichIsA("Model") or block.Parent
	overlapParams.FilterDescendantsInstances = {model}

	for _ = 1, 40 do
		if triggered or not block.Parent or not canStillKill() then return end

		for _, hit in ipairs(workspace:GetPartsInPart(block, overlapParams)) do
			tryHitPart(hit)
			if triggered then return end
		end

		task.wait(0.1)
	end
end)
