local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local afkEvent = ReplicatedStorage:WaitForChild("AFKEvent")
local practiceEvent = ReplicatedStorage:WaitForChild("PracticeEvent")

local afkTagTemplate = ServerStorage:WaitForChild("AFKTag")

local STAND_DURATION = 2
local platformCheckInterval = 0.1
local standingPlayers = {}

local function hideDefaultNameTag(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
end

local function updateAfkTag(player)
	local character = player.Character
	if not character then
		return
	end

	hideDefaultNameTag(character)

	-- Attach to body root so StudsOffset is relative to the character, not the head mesh.
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local existing = root:FindFirstChild("AFKTag") or character:FindFirstChild("AFKTag", true)
	if existing then
		existing:Destroy()
	end

	if player:GetAttribute("IsAFK") == true then
		local tag = afkTagTemplate:Clone()
		tag.Name = "AFKTag"
		tag.Adornee = root
		tag.Enabled = true
		-- Keep on the body (HRP center), not floating above the head.
		tag.StudsOffset = Vector3.zero
		tag.StudsOffsetWorldSpace = Vector3.zero
		tag.Parent = root
	end
end

afkEvent.OnServerEvent:Connect(function(player, isAFK)
	player:SetAttribute("IsAFK", isAFK == true)
	updateAfkTag(player)
end)

local function getFirstGridTile(grid)
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("BasePart") then
			return child
		end
	end
	return nil
end

local function teleportToPractice(player)
	if player:GetAttribute("InArena") == true then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local tile = getFirstGridTile(Workspace:FindFirstChild("WarmUpGrid"))
	if not tile then return false end
	player:SetAttribute("InPractice", true)
	root.CFrame = tile.CFrame * CFrame.new(0, 5, 0)
	return true
end

local function teleportToLobby(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local lobbySpawn = Workspace:FindFirstChild("LobbySpawn")
	if not lobbySpawn then return false end
	player:SetAttribute("InPractice", nil)
	root.CFrame = lobbySpawn.CFrame * CFrame.new(0, 3, 0)
	return true
end

practiceEvent.OnServerEvent:Connect(function(player, goToPractice)
	if goToPractice then teleportToPractice(player) else teleportToLobby(player) end
end)

local function getPlayerFromHit(hit)
	local character = hit and hit.Parent
	if not character then return nil end
	if not character:FindFirstChildOfClass("Humanoid") then return nil end
	return Players:GetPlayerFromCharacter(character)
end

local function isPlayerOnPlatform(player, platform)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local localPos = platform.CFrame:PointToObjectSpace(root.Position)
	local halfSize = platform.Size * 0.5
	return math.abs(localPos.X) <= halfSize.X + 2 and math.abs(localPos.Z) <= halfSize.Z + 2 and localPos.Y >= -4 and localPos.Y <= halfSize.Y + 8
end

local function beginStandingCheck(player, platform)
	if standingPlayers[player] then return end
	local sessionId = {}
	standingPlayers[player] = sessionId
	task.spawn(function()
		local elapsed = 0
		while standingPlayers[player] == sessionId do
			if not isPlayerOnPlatform(player, platform) then standingPlayers[player] = nil return end
			if elapsed >= STAND_DURATION then standingPlayers[player] = nil teleportToPractice(player) return end
			 task.wait(platformCheckInterval)
			elapsed = elapsed + platformCheckInterval
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			updateAfkTag(player)
		end)
	end)

	player:GetAttributeChangedSignal("IsAFK"):Connect(function()
		updateAfkTag(player)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function()
		task.defer(function()
			updateAfkTag(player)
		end)
	end)

	player:GetAttributeChangedSignal("IsAFK"):Connect(function()
		updateAfkTag(player)
	end)

	if player.Character then
		task.defer(function()
			updateAfkTag(player)
		end)
	end
end

local arena = Workspace:FindFirstChild("arena")
local practicePlatform = arena and arena:FindFirstChild("PracticePlatform")
if practicePlatform then
	practicePlatform.Touched:Connect(function(hit)
		local player = getPlayerFromHit(hit)
		if player then beginStandingCheck(player, practicePlatform) end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	standingPlayers[player] = nil
end)
