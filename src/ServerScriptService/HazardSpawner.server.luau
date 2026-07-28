local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CoinRewards = require(ReplicatedStorage:WaitForChild("CoinRewards"))
local KillFeedService = require(ServerScriptService:WaitForChild("KillFeedService"))
local RoundData = require(ReplicatedStorage:WaitForChild("RoundData"))
local matchResultsEvent = ReplicatedStorage:WaitForChild("MatchResultsEvent")

local COIN_ICON = "rbxassetid://73157782004178"
local XP_ICON = "rbxassetid://94843213797100"
local MIN_SURVIVAL_COINS = 5

local eliminationTimes = {}
local eliminationOrder = {}
local lastAlivePlayer = nil

local function calculateSurvivalRewards(survivalTime)
	local multiplier = 1 + (3 / (1 + math.exp(-0.05 * (survivalTime - 45))))
	local totalCoins = math.floor(survivalTime * multiplier)
	local totalXP = math.floor((survivalTime * 1.5) * multiplier)
	return totalCoins, totalXP
end

local function buildRewardsForPlayer(player)
	local rewards = {}
	local boostPercent = player:GetAttribute("FriendBoostPercent") or 0

	if RoundData.didPlay(player) then
		local surv = RoundData.survivorRewards[player] or { coins = 0, xp = 0, bonusCoins = 0 }
		local bonusCoins = surv.bonusCoins or 0
		table.insert(rewards, {
			type = "coins",
			icon = COIN_ICON,
			text = "Coins: " .. (surv.coins or 0),
		})
		table.insert(rewards, {
			type = "xp",
			icon = XP_ICON,
			text = "Exp: " .. (surv.xp or 0),
		})
		table.insert(rewards, {
			type = "friendBoost",
			icon = COIN_ICON,
			text = "Friend Boost: " .. bonusCoins,
		})
	end

	local spons = RoundData.sponsorResults[player]
	if spons then
		local avatarIcon = "rbxthumb://type=AvatarHeadShot&id=" .. spons.targetUserId .. "&w=48&h=48"
		local sponsorBonus = spons.bonusCoins or 0
		if spons.won == true then
			table.insert(rewards, {
				type = "cheer",
				icon = avatarIcon,
				targetUserId = spons.targetUserId,
				text = "Cheer: " .. spons.targetName .. " WON! +" .. (spons.coins or 0) .. " Coins",
			})
			table.insert(rewards, {
				type = "friendBoost",
				icon = COIN_ICON,
				text = "Friend Boost on Cheer (+" .. boostPercent .. "%): +" .. sponsorBonus,
			})
		else
			table.insert(rewards, {
				type = "cheer",
				icon = avatarIcon,
				targetUserId = spons.targetUserId,
				text = "Cheer: " .. spons.targetName .. " LOST! +0 Coins",
			})
			table.insert(rewards, {
				type = "friendBoost",
				icon = COIN_ICON,
				text = "Friend Boost on Cheer (+" .. boostPercent .. "%): +0",
			})
		end
	end

	return rewards
end

local arenaGrid = Workspace:WaitForChild("ArenaGrid")
local hazardCubeModel = ServerStorage:WaitForChild("HazardCube")
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local matchCompleteEvent = ServerStorage:WaitForChild("MatchComplete")

-- THE NEW REMOTE EVENT
local hazardVisualEvent = ReplicatedStorage:WaitForChild("HazardVisualEvent")

-- Teleport Locations
local lobbySpawn = Workspace:WaitForChild("LobbySpawn")
local arenaSpawn = Workspace:WaitForChild("ArenaSpawn")

local BASE_TILE_COLOR = BrickColor.new("Smoky grey")
local BASE_TARGET_CHANCE = 5
local TILE_RELEASE_COOLDOWN = 0.4

-- Anti-Camp Settings
local CAMP_TIME_LIMIT = 4.5 -- How many seconds they can stay in one spot before the game gets mad
local CAMP_RADIUS = 6 -- Studs (Roughly the width of 1 tile)
local campTracker = {}

local MIN_ACTIVE_HAZARDS = 4
local MAX_ACTIVE_HAZARDS_CAP = 32
local currentMaxActiveHazards = MIN_ACTIVE_HAZARDS
local currentMatchTime = 0
local activeHazardCount = 0

local reservedTiles = {}
local cachedArenaTiles = {}

local function getMaxActiveHazards(timePassed, maxMatchTime)
	if timePassed <= 2 then
		return MIN_ACTIVE_HAZARDS
	end
	local rampStartCount = 6
	local progress = (timePassed - 2) / (maxMatchTime - 2)
	return math.floor(rampStartCount + ((MAX_ACTIVE_HAZARDS_CAP - rampStartCount) * progress))
end

local function getTargetChance(activeCount, maxActive)
	local chaosFactor = 0
	if maxActive > 0 then
		chaosFactor = activeCount / maxActive
	end
	local campEase = 1 - (chaosFactor * 0.6)
	return math.max(1, math.floor(BASE_TARGET_CHANCE * campEase))
end

local function getAvailableTiles(tiles)
	local available = {}
	for _, tile in ipairs(tiles) do
		if not reservedTiles[tile] then
			table.insert(available, tile)
		end
	end
	return available
end

local function pickRandomAvailableTile(tiles)
	local available = getAvailableTiles(tiles)
	if #available == 0 then
		return nil
	end
	return available[math.random(1, #available)]
end

local function pickNearestAvailableTile(tiles, position)
	local bestTile = nil
	local shortestDistance = math.huge
	for _, tile in ipairs(tiles) do
		if not reservedTiles[tile] then
			local flatPos = Vector3.new(position.X, 0, position.Z)
			local flatTilePos = Vector3.new(tile.Position.X, 0, tile.Position.Z)
			local dist = (flatTilePos - flatPos).Magnitude
			if dist < shortestDistance then
				shortestDistance = dist
				bestTile = tile
			end
		end
	end
	return bestTile
end

local function reserveTile(tile)
	reservedTiles[tile] = true
end

local function releaseTile(tile)
	task.delay(TILE_RELEASE_COOLDOWN, function()
		reservedTiles[tile] = nil
	end)
end

local function getGridTiles(grid)
	local tiles = {}
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(tiles, child)
		end
	end
	return tiles
end

local function resetTile(tile)
	tile.BrickColor = BASE_TILE_COLOR
	tile.Color = BASE_TILE_COLOR.Color
	tile.Material = Enum.Material.Concrete
end

-- Helper function to count living players IN THE ARENA
local function getAliveCount()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true and player.Character and player.Character:FindFirstChild("Humanoid") then
			if player.Character.Humanoid.Health > 0 then
				count = count + 1
			end
		end
	end
	return count
end

local deathConnections = {}
local characterAddedConnections = {}

local function isAliveContestant(player)
	if not player or not player.Parent then
		return false
	end
	if player:GetAttribute("InArena") ~= true then
		return false
	end
	if player:GetAttribute("IsEliminated") == true then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local humanoid = character:FindFirstChild("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function getArenaFloorY(tiles, spawnY)
	local killFloor = Workspace:FindFirstChild("KillFloor")
	if killFloor and killFloor:IsA("BasePart") then
		return killFloor.Position.Y + (killFloor.Size.Y / 2)
	end
	local floorY = spawnY - 25
	for _, tile in ipairs(tiles) do
		local bottomY = tile.Position.Y - (tile.Size.Y / 2)
		floorY = math.min(floorY, bottomY - 8)
	end
	return floorY
end

local function checkFallEliminations(arenaFloorY)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChild("Humanoid")
			if root and humanoid and humanoid.Health > 0 and root.Position.Y < arenaFloorY then
				KillFeedService.setPendingCause(player, "fall")
				humanoid.Health = 0
			end
		end
	end
end

local respawningPlayers = {}

local function sendEliminatedToLobby(player)
	if not player or not player.Parent then return end
	if player:GetAttribute("IsEliminated") ~= true then return end
	if respawningPlayers[player] then return end

	respawningPlayers[player] = true

	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end
	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
		characterAddedConnections[player] = nil
	end

	local lobbySpawn = Workspace:FindFirstChild("LobbySpawn")
	if lobbySpawn and lobbySpawn:IsA("SpawnLocation") then
		player.RespawnLocation = lobbySpawn
	else
		player.RespawnLocation = nil
	end

	player:LoadCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and lobbySpawn then
		local spawnCF = lobbySpawn.CFrame * CFrame.new(0, 3, 0)
		character:PivotTo(spawnCF)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	task.delay(0.5, function() respawningPlayers[player] = nil end)
end

local function markArenaEliminated(player)
	if player:GetAttribute("InArena") ~= true then return end
	if player:GetAttribute("IsEliminated") == true then return end
	player:SetAttribute("IsEliminated", true)
	player:SetAttribute("CanSponsorThisRound", true)
	eliminationTimes[player] = survivalTimeValue.Value
	table.insert(eliminationOrder, player)
	KillFeedService.reportElimination(player)
end

local function bindArenaDeathTracking(player)
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end
	if characterAddedConnections[player] then
		characterAddedConnections[player]:Disconnect()
		characterAddedConnections[player] = nil
	end

	local function hookCharacter(character)
		if player:GetAttribute("IsEliminated") == true then return end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		if deathConnections[player] then
			deathConnections[player]:Disconnect()
		end
		deathConnections[player] = humanoid.Died:Connect(function()
			markArenaEliminated(player)
			sendEliminatedToLobby(player)
		end)
	end

	characterAddedConnections[player] = player.CharacterAdded:Connect(hookCharacter)
	if player.Character then
		hookCharacter(player.Character)
	end
end

local function getEliminatedCount()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") == true then
			count += 1
		end
	end
	return count
end

local function shouldEndMatch(playersAtStart, currentAlive)
	if playersAtStart <= 1 then
		return currentAlive == 0
	end
	if currentAlive <= 1 then
		return true
	end
	if getEliminatedCount() >= playersAtStart - 1 then
		return true
	end
	return false
end

local function updateLastAlivePlayer()
	local alivePlayers = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true then
			if player.Character then
				local humanoid = player.Character:FindFirstChild("Humanoid")
				if humanoid and humanoid.Health > 0 then
					table.insert(alivePlayers, player)
				end
			end
		end
	end
	if #alivePlayers == 1 then
		lastAlivePlayer = alivePlayers[1]
	end
end

local function resolveWinner(matchTime, playersAtStart)
	for _, player in ipairs(Players:GetPlayers()) do
		if isAliveContestant(player) and RoundData.didPlay(player) then
			return player
		end
	end

	if lastAlivePlayer and lastAlivePlayer.Parent and RoundData.didPlay(lastAlivePlayer) then
		return lastAlivePlayer
	end

	local bestPlayer = nil
	local bestTime = -1
	for player in pairs(RoundData.contestants) do
		local survivalTime = eliminationTimes[player] or matchTime
		if survivalTime > bestTime then
			bestTime = survivalTime
			bestPlayer = player
		end
	end
	if bestPlayer then
		return bestPlayer
	end

	if #eliminationOrder > 0 then
		return eliminationOrder[#eliminationOrder]
	end

	if playersAtStart == 1 then
		for player in pairs(RoundData.contestants) do
			return player
		end
	end

	return nil
end

local function awardSurvivalRewards(player, survivalTime)
	survivalTime = math.max(survivalTime, 1)
	local totalCoins, totalXP = calculateSurvivalRewards(survivalTime)
	totalCoins = math.max(totalCoins, MIN_SURVIVAL_COINS)
	local _, bonusCoins = CoinRewards.awardCoins(player, totalCoins)

	RoundData.survivorRewards[player] = {
		coins = totalCoins,
		bonusCoins = bonusCoins,
		xp = totalXP,
	}

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local xpVal = leaderstats:FindFirstChild("XP")
		if xpVal then
			xpVal.Value = xpVal.Value + totalXP
		end
	end
end

-- Teleport helper function
local function teleportPlayers(playersList, targetPart)
	for _, player in ipairs(playersList) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			-- Lift them slightly above the target part so they don't spawn stuck in the floor
			player.Character.HumanoidRootPart.CFrame = targetPart.CFrame * CFrame.new(0, 3, 0)
		end
	end
end

local function spawnHazard()
	if activeHazardCount >= currentMaxActiveHazards then return end
	if getAliveCount() == 0 then return end

	local tiles = cachedArenaTiles
	if #tiles == 0 then return end
	if #getAvailableTiles(tiles) == 0 then return end

	local targetChance = getTargetChance(activeHazardCount, currentMaxActiveHazards)
	local targetTile = nil

	-- ==========================================
	-- 1. PUNISH CAMPERS FIRST
	-- ==========================================
	local activeCampers = {}
	for playerName, data in pairs(campTracker) do
		if data.time >= CAMP_TIME_LIMIT then
			local p = Players:FindFirstChild(playerName)
			if p and p:GetAttribute("InArena") == true and p:GetAttribute("IsEliminated") ~= true then
				table.insert(activeCampers, p)
			end
		end
	end

	if #activeCampers > 0 then
		-- Pick a random camper and drop a block right on them!
		local doomedCamper = activeCampers[math.random(1, #activeCampers)]
		if doomedCamper.Character and doomedCamper.Character:FindFirstChild("HumanoidRootPart") then
			targetTile = pickNearestAvailableTile(tiles, doomedCamper.Character.HumanoidRootPart.Position)

			-- Reset their timer so we don't spam 50 blocks on them instantly
			campTracker[doomedCamper.Name].time = 0
			campTracker[doomedCamper.Name].pos = doomedCamper.Character.HumanoidRootPart.Position
		end
	end

	-- ==========================================
	-- 2. NORMAL RANDOM TARGETING (If nobody is camping)
	-- ==========================================
	if not targetTile and math.random(1, 100) <= targetChance then
		local arenaPlayers = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("InArena") == true and p:GetAttribute("IsEliminated") ~= true and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				table.insert(arenaPlayers, p)
			end
		end

		if #arenaPlayers > 0 then
			local randomPlayer = arenaPlayers[math.random(1, #arenaPlayers)]
			local character = randomPlayer.Character
			if character and character:FindFirstChild("HumanoidRootPart") then
				targetTile = pickNearestAvailableTile(tiles, character.HumanoidRootPart.Position)
			end
		end
	end

	if not targetTile then
		targetTile = pickRandomAvailableTile(tiles)
	end
	if not targetTile then return end

	activeHazardCount += 1
	reserveTile(targetTile)

	targetTile.Color = Color3.fromRGB(210, 40, 40)
	targetTile.Material = Enum.Material.Concrete

	-- === THE TIME-SYNCED DROP LOGIC ===
	local spawnHeight = 20
	local fallSpeed = 50
	local tileTopY = targetTile.Position.Y + (targetTile.Size.Y / 2)
	local distance = spawnHeight - (2) 
	local fallTime = distance / fallSpeed

	-- 1. Pick absolute timestamps to completely eliminate server drift
	local currentTime = workspace:GetServerTimeNow()
	local exactDropTimestamp = currentTime + 1
	local exactImpactTimestamp = exactDropTimestamp + fallTime

	-- 2. Fire the event IMMEDIATELY to give the clients a head start
	hazardVisualEvent:FireAllClients(targetTile, spawnHeight, fallTime, exactDropTimestamp)

	-- 3. The server waits EXACTLY until the impact millisecond
	local waitTime = exactImpactTimestamp - workspace:GetServerTimeNow()
	if waitTime > 0 then
		task.wait(waitTime)
	end

	-- Instantly reset the tile color the moment it hits the ground!
	resetTile(targetTile)

	-- 4. THE INSTANT MATH KILL (Bypasses physics engine lag completely)
	-- We draw an invisible math box exactly the size of the tile, extending 10 studs up
	local killRegionSize = Vector3.new(targetTile.Size.X - 0.5, 10, targetTile.Size.Z - 0.5) 
	local killRegionCFrame = targetTile.CFrame * CFrame.new(0, 5, 0)

	local partsInZone = workspace:GetPartBoundsInBox(killRegionCFrame, killRegionSize)
	for _, part in ipairs(partsInZone) do
		local character = part.Parent
		if character and character:FindFirstChild("Humanoid") then
			local player = Players:GetPlayerFromCharacter(character)
			-- Ensure they are an active player in the arena
			if player and player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true then
				KillFeedService.markHazardKill(player)
				character.Humanoid.Health = 0
			end
		end
	end

	-- 5. Spawn the invisible server hitbox just in case your other scripts need the "CanKill" attribute
	local serverHitbox = hazardCubeModel:Clone()
	serverHitbox:SetAttribute("CanKill", true)

	for _, part in ipairs(serverHitbox:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1 
			part.Anchored = true
			part.CanCollide = false
		end
	end

	local restingHeight = (serverHitbox.PrimaryPart and serverHitbox.PrimaryPart.Size.Y / 2) or 4
	serverHitbox:PivotTo(targetTile.CFrame * CFrame.new(0, tileTopY + restingHeight, 0))
	serverHitbox.Parent = Workspace

	task.wait(0.03) 

	if serverHitbox and serverHitbox.Parent then
		serverHitbox:Destroy()
	end

	releaseTile(targetTile)
	activeHazardCount -= 1
end

-- === THE MAIN GAME LOOP STATE MACHINE ===
while true do
	-- STATE 1: INTERMISSION
	local intermissionDuration = 15
	for i = intermissionDuration, 1, -1 do 
		survivalTimeValue.Value = i
		task.wait(1)
		if #Players:GetPlayers() < 1 then
			repeat task.wait(1) until #Players:GetPlayers() >= 1
		end
	end

	local activeContestants = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("IsAFK") then
			table.insert(activeContestants, player)
		end
	end

	if #activeContestants == 0 then
		continue
	end

	-- STATE 2: PREPARE ROUND
	RoundData.clear()
	table.clear(eliminationTimes)
	table.clear(eliminationOrder)
	table.clear(campTracker)
	lastAlivePlayer = nil
	teleportPlayers(activeContestants, arenaSpawn)

	for _, player in ipairs(activeContestants) do
		player:SetAttribute("IsEliminated", nil)
		player:SetAttribute("CanSponsorThisRound", nil)
		bindArenaDeathTracking(player)
		player:SetAttribute("InArena", true)
		player:SetAttribute("InPractice", nil)
	end

	for _, player in ipairs(activeContestants) do
		RoundData.markContestant(player)
	end

	local rollCallData = {}
	for _, player in ipairs(activeContestants) do
		local ability = player:GetAttribute("EquippedAbility") or "None"
		rollCallData[player.Name] = ability
	end

	local showRollCall = ReplicatedStorage:WaitForChild("ShowRollCall")
	for _, player in ipairs(activeContestants) do
		showRollCall:FireClient(player, rollCallData)
	end

	cachedArenaTiles = getGridTiles(arenaGrid)
	reservedTiles = {}

	local arenaFloorY = getArenaFloorY(cachedArenaTiles, arenaSpawn.Position.Y)

	survivalTimeValue.Value = 0
	local timePassed = 0
	local MAX_MATCH_TIME = 95 
	local startDelay = 0.15 
	local endDelay = 0.01  
	local playersAtStart = #activeContestants

	task.wait(4.5) 

	-- STATE 3: IN-GAME 
	while timePassed < MAX_MATCH_TIME do
		currentMatchTime = timePassed
		currentMaxActiveHazards = getMaxActiveHazards(timePassed, MAX_MATCH_TIME)

		task.spawn(spawnHazard)

		if timePassed >= 30 then
			task.spawn(spawnHazard)
		end

		if timePassed >= 70 then
			task.spawn(spawnHazard)
		end

		local currentDelay
		if timePassed <= 2 then
			currentDelay = 0.35
		else
			local progress = (timePassed - 2) / (MAX_MATCH_TIME - 2)
			currentDelay = startDelay - ((startDelay - endDelay) * progress)
		end

		local randomFuzz = math.random(-5, 5) / 100
		local finalDelay = math.clamp(currentDelay + randomFuzz, endDelay, 0.85)

		-- ==========================================
		-- ANTI-CAMP TRACKER UPDATE
		-- ==========================================
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("InArena") == true and p:GetAttribute("IsEliminated") ~= true and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				local currentPos = p.Character.HumanoidRootPart.Position
				local tracker = campTracker[p.Name]

				if not tracker then
					-- First time seeing this player, log their position
					campTracker[p.Name] = {pos = currentPos, time = 0}
				else
					-- Calculate flat distance (ignoring jumping)
					local dist = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(tracker.pos.X, 0, tracker.pos.Z)).Magnitude
					if dist <= CAMP_RADIUS then
						-- They are still in the same spot! Add time.
						tracker.time = tracker.time + finalDelay
					else
						-- They moved far enough! Reset their timer and log new spot.
						tracker.pos = currentPos
						tracker.time = 0
					end
				end
			end
		end
		-- ==========================================
		task.wait(finalDelay)
		timePassed = timePassed + finalDelay
		survivalTimeValue.Value = timePassed

		updateLastAlivePlayer()
		checkFallEliminations(arenaFloorY)
		local currentAlive = getAliveCount()
		if shouldEndMatch(playersAtStart, currentAlive) then
			break
		end
	end

	-- STATE 4: ROUND OVER & PAYOUTS
	local matchTime = survivalTimeValue.Value
	local winner = resolveWinner(matchTime, playersAtStart)
	RoundData.winner = winner

	if winner and winner.Parent then
		pcall(function()
			local PlayerStatsService = require(ServerScriptService:WaitForChild("PlayerStatsService"))
			PlayerStatsService.addWin(winner)
			winner:SetAttribute("StatWins", winner:FindFirstChild("TotalWins") and winner.TotalWins.Value or 0)
		end)
	end

	pcall(function()
		local PlayerStatsService = require(ServerScriptService:WaitForChild("PlayerStatsService"))
		for player in pairs(RoundData.contestants) do
			if player ~= winner and player.Parent then
				PlayerStatsService.resetWinStreak(player)
			end
		end
	end)

	local QuestService
	pcall(function()
		QuestService = require(ServerScriptService:WaitForChild("QuestService"))
	end)

	matchCompleteEvent:Fire()

	local playersToReturnToLobby = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true then
			table.insert(playersToReturnToLobby, player)

			if RoundData.didPlay(player) then
				local personalTime = eliminationTimes[player] or matchTime
				awardSurvivalRewards(player, personalTime)
				if QuestService then
					QuestService.onSurvival(player, personalTime)
				end
			end
		end
	end

	teleportPlayers(playersToReturnToLobby, lobbySpawn)

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("InArena", nil)
		player:SetAttribute("HasShield", nil)
		player:SetAttribute("InPractice", nil)
		player:SetAttribute("AbilityCooldownEnd", nil)
		player:SetAttribute("IsEliminated", nil)
		player:SetAttribute("CanSponsorThisRound", nil)

		if player.Character then
			local shieldVis = player.Character:FindFirstChild("ShieldVisual")
			if shieldVis then shieldVis:Destroy() end
		end
	end

	local resetClient = ReplicatedStorage:FindFirstChild("ResetClientSponsors")
	if resetClient then
		resetClient:FireAllClients()
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local viewMode = RoundData.isParticipant(player) and "participant" or "spectator"
		matchResultsEvent:FireClient(player, {
			viewMode = viewMode,
			winnerName = winner and winner.DisplayName or "Unknown",
			winnerUserId = winner and winner.UserId or 0,
			rewards = buildRewardsForPlayer(player),
		})
	end

	task.wait(2) 
end