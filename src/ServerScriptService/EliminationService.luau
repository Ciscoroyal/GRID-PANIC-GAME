local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local KillFeedService = require(ServerScriptService:WaitForChild("KillFeedService"))
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")

local EliminationService = {}

local teleporting = {}
local eliminatedCallbacks = {}
local SHIELD_BREAK_IMMUNITY = 1.0 -- seconds; stops multi-hit hazards from killing after shield breaks

function EliminationService.onEliminated(callback)
	if typeof(callback) == "function" then
		table.insert(eliminatedCallbacks, callback)
	end
end

local function getLobbySpawn()
	local lobbySpawn = Workspace:FindFirstChild("LobbySpawn")
	if lobbySpawn and (lobbySpawn:IsA("SpawnLocation") or lobbySpawn:IsA("BasePart")) then
		return lobbySpawn
	end
	return nil
end

local function clearShield(player, character)
	player:SetAttribute("HasShield", nil)
	if character then
		local shieldVis = character:FindFirstChild("ShieldVisual")
		if shieldVis then
			shieldVis:Destroy()
		end
	end
end

function EliminationService.teleportToLobby(player)
	if not player or not player.Parent then
		return false
	end
	if teleporting[player] then
		return false
	end

	teleporting[player] = true

	local lobbySpawn = getLobbySpawn()
	if lobbySpawn and lobbySpawn:IsA("SpawnLocation") then
		player.RespawnLocation = lobbySpawn
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Soft return: keep the living character and move them to lobby
	if character and root and humanoid and humanoid.Health > 0 then
		local spawnCF = (lobbySpawn and lobbySpawn.CFrame or root.CFrame) * CFrame.new(0, 3, 0)
		character:PivotTo(spawnCF)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = game:GetService("StarterPlayer").CharacterWalkSpeed
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
		humanoid.AutoRotate = true
		player:SetAttribute("InPractice", nil)
		task.delay(0.5, function()
			teleporting[player] = nil
		end)
		return true
	end

	-- Fallback if character is already dead/missing
	player:LoadCharacter()
	character = player.Character or player.CharacterAdded:Wait()
	root = character:WaitForChild("HumanoidRootPart", 10)
	humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and lobbySpawn then
		character:PivotTo(lobbySpawn.CFrame * CFrame.new(0, 3, 0))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	player:SetAttribute("InPractice", nil)
	task.delay(0.5, function()
		teleporting[player] = nil
	end)
	return true
end

--[[
	opts = {
		cause = "hazard" | "fall" | "water" | nil,
		respectShield = boolean (default true),
	}
	Survival rewards are granted at match end by HazardSpawner.
]]
function EliminationService.eliminate(player, opts)
	opts = opts or {}
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if not player.Parent then
		return false
	end
	if player:GetAttribute("InArena") ~= true then
		return false
	end
	if player:GetAttribute("IsEliminated") == true then
		return false
	end

	local character = player.Character
	local respectShield = opts.respectShield
	if respectShield == nil then
		respectShield = true
	end

	local now = os.clock()
	local immunityUntil = player:GetAttribute("ShieldBreakImmunityUntil")
	if respectShield and typeof(immunityUntil) == "number" and now < immunityUntil then
		return false
	end

	if respectShield and player:GetAttribute("HasShield") == true then
		clearShield(player, character)
		player:SetAttribute("ShieldBreakImmunityUntil", now + SHIELD_BREAK_IMMUNITY)
		vfxEvent:FireClient(player, "LightShake")
		return false
	end

	player:SetAttribute("IsEliminated", true)
	player:SetAttribute("CanSponsorThisRound", true)
	clearShield(player, character)

	if opts.cause == "hazard" then
		KillFeedService.markHazardKill(player)
	elseif opts.cause == "fall" or opts.cause == "water" then
		KillFeedService.setPendingCause(player, opts.cause)
	end

	KillFeedService.reportElimination(player)
	vfxEvent:FireClient(player, "HeavyShake")

	for _, callback in ipairs(eliminatedCallbacks) do
		pcall(callback, player, opts.cause)
	end

	EliminationService.teleportToLobby(player)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	teleporting[player] = nil
end)

return EliminationService
