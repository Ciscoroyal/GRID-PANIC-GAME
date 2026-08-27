local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local EliminationService = require(ServerScriptService:WaitForChild("EliminationService"))

local killFloor = workspace:WaitForChild("KillFloor")
killFloor.CanCollide = false
killFloor.CanTouch = true

local killFloorTop = killFloor.Position.Y + (killFloor.Size.Y / 2)
local recent = {}

local function eliminateFromFall(player)
	if not player or not player.Parent then return end
	if recent[player] then return end

	recent[player] = true
	EliminationService.eliminate(player, { cause = "fall", respectShield = false })

	task.delay(0.5, function()
		recent[player] = nil
	end)
end

local function onKillFloorTouched(hit)
	local character = hit and hit.Parent
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		eliminateFromFall(player)
	end
end

killFloor.Touched:Connect(onKillFloorTouched)

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") ~= true then continue end
		if player:GetAttribute("IsEliminated") == true then continue end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root.Position.Y <= killFloorTop then
			eliminateFromFall(player)
		end
	end
end)
