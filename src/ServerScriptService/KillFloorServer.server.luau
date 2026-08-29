local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EliminationService = require(ServerScriptService:WaitForChild("EliminationService"))
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")

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

-- =========================================================
-- PRACTICE ARENA FALL
-- The KillFloor part does not extend over the practice arena, so practice
-- falls get their own height threshold. Death here mirrors an arena fall:
-- the character survives, takes the heavy shake, and is put back where it
-- belongs — the practice grid rather than the lobby.
-- =========================================================
local warmUpGrid = workspace:WaitForChild("WarmUpGrid")
local environment = workspace:FindFirstChild("Environment")
local practiceBase = environment and environment:FindFirstChild("Practice Base")

local PRACTICE_FALL_MARGIN = 6

local function getFirstPracticeTile()
	for _, child in ipairs(warmUpGrid:GetChildren()) do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

local function getPracticeFloorY()
	if practiceBase and practiceBase:IsA("BasePart") then
		return practiceBase.Position.Y - (practiceBase.Size.Y / 2) - PRACTICE_FALL_MARGIN
	end
	local tile = getFirstPracticeTile()
	if tile then
		return tile.Position.Y - 15
	end
	return -math.huge
end

local practiceFloorY = getPracticeFloorY()
local recentPracticeFall = {}

local function practiceFall(player)
	if not player or not player.Parent then return end
	if recentPracticeFall[player] then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local tile = getFirstPracticeTile()
	if not (root and humanoid and tile) then return end

	recentPracticeFall[player] = true

	character:PivotTo(tile.CFrame * CFrame.new(0, 5, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.Health = humanoid.MaxHealth
	vfxEvent:FireClient(player, "HeavyShake")

	task.delay(0.6, function()
		recentPracticeFall[player] = nil
	end)
end

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		if player:GetAttribute("InPractice") == true then
			if root.Position.Y <= practiceFloorY then
				practiceFall(player)
			end
			continue
		end

		if player:GetAttribute("InArena") ~= true then continue end
		if player:GetAttribute("IsEliminated") == true then continue end
		if root.Position.Y <= killFloorTop then
			eliminateFromFall(player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	recentPracticeFall[player] = nil
	recent[player] = nil
end)
