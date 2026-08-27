local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local CoinRewards = require(ReplicatedStorage:WaitForChild("CoinRewards"))
local KillFeedService = require(ServerScriptService:WaitForChild("KillFeedService"))
local EliminationService = require(ServerScriptService:WaitForChild("EliminationService"))
local RoundData = require(ReplicatedStorage:WaitForChild("RoundData"))
local LevelService = require(ServerScriptService:WaitForChild("LevelService"))
local VoteService = require(ServerScriptService:WaitForChild("VoteService"))
local ShrinkService = require(ServerScriptService:WaitForChild("ShrinkService"))
local matchResultsEvent = ReplicatedStorage:WaitForChild("MatchResultsEvent")
local currentGameMode = ReplicatedStorage:WaitForChild("CurrentGameMode")

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
local playersAliveValue = ReplicatedStorage:WaitForChild("PlayersAlive")
local aliveStatusValue = ReplicatedStorage:WaitForChild("AliveStatus")
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
local OVERTIME_HAZARDS_CAP = 64

-- Difficulty curve is keyed to CORE through 1:35; match can run to MAX (2:00).
local CORE_DIFFICULTY_TIME = 95
local MAX_MATCH_TIME = 120

local currentMaxActiveHazards = MIN_ACTIVE_HAZARDS
local currentMatchTime = 0
local activeHazardCount = 0

local reservedTiles = {}
local cachedArenaTiles = {}

-- 0 at t<=2, 0..1 across 2..95 (same as old curve), then 1..3 across 95..120.
local function getDifficultyProgress(timePassed)
	if timePassed <= 2 then
		return 0
	end
	if timePassed <= CORE_DIFFICULTY_TIME then
		return (timePassed - 2) / (CORE_DIFFICULTY_TIME - 2)
	end
	local overtime = (timePassed - CORE_DIFFICULTY_TIME) / (MAX_MATCH_TIME - CORE_DIFFICULTY_TIME)
	return 1 + math.clamp(overtime, 0, 1) * 2
end

local function getMaxActiveHazards(timePassed)
	if timePassed <= 2 then
		local base = MIN_ACTIVE_HAZARDS
		if currentGameMode.Value == "Shrinking" then
			base = math.max(2, math.floor(base * 0.55))
		end
		return base
	end
	local rampStartCount = 6
	local progress = getDifficultyProgress(timePassed)
	local capped
	if progress <= 1 then
		-- Identical to the old 0..95 curve ending at MAX_ACTIVE_HAZARDS_CAP.
		capped = math.floor(rampStartCount + ((MAX_ACTIVE_HAZARDS_CAP - rampStartCount) * progress))
	else
		local over = math.clamp(progress - 1, 0, 2) / 2
		capped = math.floor(MAX_ACTIVE_HAZARDS_CAP + ((OVERTIME_HAZARDS_CAP - MAX_ACTIVE_HAZARDS_CAP) * over))
	end
	if currentGameMode.Value == "Shrinking" then
		capped = math.max(2, math.floor(capped * 0.55))
	end
	return capped
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
		if not reservedTiles[tile] and not ShrinkService.isFallen(tile) then
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
		if not reservedTiles[tile] and not ShrinkService.isFallen(tile) then
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
	tile.CanCollide = true
	tile.Transparency = 0
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
				EliminationService.eliminate(player, { cause = "fall", respectShield = false })
			end
		end
	end
end

EliminationService.onEliminated(function(player)
	eliminationTimes[player] = survivalTimeValue.Value
	table.insert(eliminationOrder, player)
	updateAliveHud()
end)

local function sendEliminatedToLobby(player)
	EliminationService.teleportToLobby(player)
end

local function markArenaEliminated(player)
	EliminationService.eliminate(player, { respectShield = false })
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
			-- Fallback only: soft-eliminate paths should not kill the Humanoid
			EliminationService.eliminate(player, { respectShield = false })
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


local TEAM_BLUE = "Blue"
local TEAM_RED = "Red"

local function shuffleList(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function assignTeams(contestants)
	RoundData.clearTeams()
	local shuffled = table.clone(contestants)
	shuffleList(shuffled)
	local half = math.ceil(#shuffled / 2)
	for i, player in ipairs(shuffled) do
		RoundData.setTeam(player, i <= half and TEAM_BLUE or TEAM_RED)
	end
end

local function getArenaBounds(tiles, fallbackPart)
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local y = fallbackPart and fallbackPart.Position.Y or 5
	for _, tile in ipairs(tiles) do
		minX = math.min(minX, tile.Position.X)
		maxX = math.max(maxX, tile.Position.X)
		minZ = math.min(minZ, tile.Position.Z)
		maxZ = math.max(maxZ, tile.Position.Z)
		y = tile.Position.Y + (tile.Size.Y / 2) + 3
	end
	if minX == math.huge then
		local p = fallbackPart.Position
		return p.X - 20, p.X + 20, p.Z - 20, p.Z + 20, p.Y + 3
	end
	return minX, maxX, minZ, maxZ, y
end

local function teleportTeamsOppositeSides(contestants, tiles, fallbackPart)
	local minX, maxX, minZ, maxZ, y = getArenaBounds(tiles, fallbackPart)
	local midZ = (minZ + maxZ) / 2
	local inset = math.max(4, (maxX - minX) * 0.12)
	local blueX = minX + inset
	local redX = maxX - inset

	local blues, reds = {}, {}
	for _, player in ipairs(contestants) do
		if RoundData.getTeam(player) == TEAM_RED then
			table.insert(reds, player)
		else
			table.insert(blues, player)
		end
	end

	local function placeTeam(list, x)
		local count = #list
		for i, player in ipairs(list) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local zSpread = 0
				if count > 1 then
					local span = math.max(6, (maxZ - minZ) * 0.55)
					zSpread = -span / 2 + span * ((i - 1) / (count - 1))
				end
				local lookAt = Vector3.new((minX + maxX) / 2, y, midZ + zSpread)
				local pos = Vector3.new(x, y, midZ + zSpread)
				root.CFrame = CFrame.lookAt(pos, lookAt)
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end

	placeTeam(blues, blueX)
	placeTeam(reds, redX)
end

local function getAliveTeamCounts()
	local blue, red = 0, 0
	for _, player in ipairs(Players:GetPlayers()) do
		if isAliveContestant(player) then
			local team = RoundData.getTeam(player)
			if team == TEAM_BLUE then
				blue += 1
			elseif team == TEAM_RED then
				red += 1
			end
		end
	end
	return blue, red
end

local function updateAliveHud()
	if currentGameMode.Value == "Team" then
		local blueAlive, redAlive = getAliveTeamCounts()
		local total = blueAlive + redAlive
		playersAliveValue.Value = total
		if total <= 0 then
			aliveStatusValue.Value = ""
		else
			aliveStatusValue.Value = string.format("%dv%d", blueAlive, redAlive)
		end
		return
	end

	local alive = getAliveCount()
	playersAliveValue.Value = alive
	if alive <= 0 then
		aliveStatusValue.Value = ""
	else
		aliveStatusValue.Value = string.format("%d LEFT", alive)
	end
end

local function clearAliveHud()
	playersAliveValue.Value = 0
	aliveStatusValue.Value = ""
end

local function shouldEndMatch(playersAtStart, currentAlive)
	if currentGameMode.Value == "Team" then
		local blueAlive, redAlive = getAliveTeamCounts()
		if playersAtStart <= 1 then
			return currentAlive == 0
		end
		-- End when one team is wiped (friendly fire / hazards can wipe both)
		return blueAlive == 0 or redAlive == 0
	end
	if currentGameMode.Value == "Juggernaut" then
		local jugg = RoundData.getJuggernaut()
		-- Hunters win as soon as the juggernaut is eliminated
		if not jugg or not isAliveContestant(jugg) then
			return true
		end
		-- Juggernaut wins when all hunters are gone
		if playersAtStart <= 1 then
			return currentAlive == 0
		end
		return currentAlive <= 1
	end
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

local function resolveWinningTeam(matchTime)
	local blueAlive, redAlive = getAliveTeamCounts()
	if blueAlive > 0 and redAlive == 0 then
		return TEAM_BLUE
	end
	if redAlive > 0 and blueAlive == 0 then
		return TEAM_RED
	end

	-- Both wiped or timeout: team with longer total survival among contestants
	local blueTime, redTime = 0, 0
	for player in pairs(RoundData.contestants) do
		local team = RoundData.getTeam(player)
		local t = eliminationTimes[player] or matchTime
		if team == TEAM_BLUE then
			blueTime += t
		elseif team == TEAM_RED then
			redTime += t
		end
	end
	if blueTime > redTime then
		return TEAM_BLUE
	end
	if redTime > blueTime then
		return TEAM_RED
	end

	if lastAlivePlayer and lastAlivePlayer.Parent then
		return RoundData.getTeam(lastAlivePlayer)
	end
	if #eliminationOrder > 0 then
		return RoundData.getTeam(eliminationOrder[#eliminationOrder])
	end
	return TEAM_BLUE
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

	local gainedXP = LevelService.awardXP(player, totalXP)

	RoundData.survivorRewards[player] = {
		coins = totalCoins,
		bonusCoins = bonusCoins,
		xp = gainedXP,
	}
end

-- Teleport helper function
local function teleportPlayers(playersList, targetPart)
	for _, player in ipairs(playersList) do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
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
				-- Juggernaut is immune to falling grid hazards (still dies to edge / kill floor)
				if player:GetAttribute("IsJuggernaut") == true then
					continue
				end
				EliminationService.eliminate(player, { cause = "hazard", respectShield = true })
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
	-- STATE 1: INTERMISSION + MODE VOTE
	clearAliveHud()
	local intermissionDuration = 15
	local voteDuration = 12
	local chosenMode = "Classic"
	local voteFinished = false

	task.spawn(function()
		chosenMode = VoteService.runVote(voteDuration) or "Classic"
		voteFinished = true
	end)

	for i = intermissionDuration, 1, -1 do
		survivalTimeValue.Value = i
		task.wait(1)
		if #Players:GetPlayers() < 1 then
			repeat task.wait(1) until #Players:GetPlayers() >= 1
		end
	end

	local waitDeadline = os.clock() + 3
	while not voteFinished and os.clock() < waitDeadline do
		task.wait(0.1)
	end
	if not voteFinished then
		chosenMode = "Classic"
	end

	local activeContestants = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if not player:GetAttribute("IsAFK") then
			table.insert(activeContestants, player)
		end
	end

	if #activeContestants == 0 then
		currentGameMode.Value = ""
		continue
	end

	-- Team / Juggernaut need at least 2 players; otherwise fall back to Classic
	if (chosenMode == "Team" or chosenMode == "Juggernaut") and #activeContestants < 2 then
		chosenMode = "Classic"
	end

	-- STATE 2: PREPARE ROUND
	RoundData.clear()
	RoundData.clearTeams()
	RoundData.setMode(chosenMode)
	currentGameMode.Value = chosenMode
	table.clear(eliminationTimes)
	table.clear(eliminationOrder)
	table.clear(campTracker)
	lastAlivePlayer = nil

	for _, player in ipairs(activeContestants) do
		player:SetAttribute("IsEliminated", nil)
		player:SetAttribute("CanSponsorThisRound", nil)
		player:SetAttribute("IsJuggernaut", nil)
		bindArenaDeathTracking(player)
		player:SetAttribute("InArena", true)
		player:SetAttribute("InPractice", nil)
		RoundData.markContestant(player)
	end

	local tilesForSpawn = getGridTiles(arenaGrid)
	if chosenMode == "Team" then
		assignTeams(activeContestants)
		teleportTeamsOppositeSides(activeContestants, tilesForSpawn, arenaSpawn)
	else
		teleportPlayers(activeContestants, arenaSpawn)
	end

	if chosenMode == "Juggernaut" then
		local pick = activeContestants[math.random(1, #activeContestants)]
		RoundData.setJuggernaut(pick)
	end

	local rollCallData = {}
	local modeForRollCall = currentGameMode.Value
	for _, player in ipairs(activeContestants) do
		local ability = player:GetAttribute("EquippedAbility") or "None"
		if modeForRollCall == "PunchOut" then
			ability = "Grid Punch"
		elseif modeForRollCall == "PureSurvival" then
			ability = "None"
		end
		local roleTeam = RoundData.getTeam(player)
		if modeForRollCall == "Juggernaut" then
			roleTeam = RoundData.isJuggernaut(player) and "Juggernaut" or "Hunter"
		end
		rollCallData[player.Name] = {
			ability = ability,
			team = roleTeam,
		}
	end

	local showRollCall = ReplicatedStorage:WaitForChild("ShowRollCall")
	for _, player in ipairs(activeContestants) do
		showRollCall:FireClient(player, rollCallData)
	end

	cachedArenaTiles = getGridTiles(arenaGrid)
	reservedTiles = {}
	ShrinkService.stop()
	ShrinkService.restoreAll()

	local arenaFloorY = getArenaFloorY(cachedArenaTiles, arenaSpawn.Position.Y)

	survivalTimeValue.Value = 0
	local timePassed = 0
	local startDelay = 0.15
	local endDelay = 0.01
	local overtimeEndDelay = 0.005
	local playersAtStart = #activeContestants

	task.wait(3.2)

	if chosenMode == "Shrinking" then
		ShrinkService.start(cachedArenaTiles)
	end

	updateAliveHud()

	-- STATE 3: IN-GAME
	while timePassed < MAX_MATCH_TIME do
		currentMatchTime = timePassed
		currentMaxActiveHazards = getMaxActiveHazards(timePassed)

		task.spawn(spawnHazard)

		if timePassed >= 30 then
			task.spawn(spawnHazard)
		end

		if timePassed >= 70 then
			task.spawn(spawnHazard)
		end

		-- Overtime (1:35 → 2:00): escalate toward unwinnable chaos
		if timePassed >= CORE_DIFFICULTY_TIME then
			task.spawn(spawnHazard)
		end

		if timePassed >= 105 then
			task.spawn(spawnHazard)
			task.spawn(spawnHazard)
		end

		if timePassed >= 115 then
			for _ = 1, 4 do
				task.spawn(spawnHazard)
			end
		end

		local currentDelay
		local delayFloor = endDelay

		if timePassed <= 2 then
			currentDelay = 0.35
		else
			local progress = getDifficultyProgress(timePassed)
			if progress <= 1 then
				-- Same delay curve as the old 0..95 match
				currentDelay = startDelay - ((startDelay - endDelay) * progress)
			else
				local over = math.clamp(progress - 1, 0, 2) / 2
				currentDelay = endDelay * (1 - over)
				delayFloor = overtimeEndDelay
			end
		end

		local randomFuzz = math.random(-5, 5) / 100
		local finalDelay = math.clamp(currentDelay + randomFuzz, delayFloor, 0.85)

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
		updateAliveHud()
		if shouldEndMatch(playersAtStart, currentAlive) then
			break
		end
	end

	-- STATE 4: ROUND OVER & PAYOUTS
	local matchTime = survivalTimeValue.Value
	local isTeamMode = currentGameMode.Value == "Team"
	local isJuggernautMode = currentGameMode.Value == "Juggernaut"
	local winningTeam = nil
	local winner = nil
	local juggernautWon = false

	if isTeamMode then
		winningTeam = resolveWinningTeam(matchTime)
		RoundData.winningTeam = winningTeam
		RoundData.winner = nil
		local winners = RoundData.getTeamPlayers(winningTeam)
		pcall(function()
			local PlayerStatsService = require(ServerScriptService:WaitForChild("PlayerStatsService"))
			local winnerSet = {}
			for _, p in ipairs(winners) do
				winnerSet[p] = true
				PlayerStatsService.addWin(p)
				p:SetAttribute("StatWins", p:FindFirstChild("TotalWins") and p.TotalWins.Value or 0)
			end
			for player in pairs(RoundData.contestants) do
				if player.Parent and not winnerSet[player] then
					PlayerStatsService.resetWinStreak(player)
				end
			end
		end)
	elseif isJuggernautMode then
		local jugg = RoundData.getJuggernaut()
		juggernautWon = jugg ~= nil and isAliveContestant(jugg)
		if juggernautWon then
			winner = jugg
			RoundData.winner = jugg
			RoundData.winningTeam = nil
			pcall(function()
				local PlayerStatsService = require(ServerScriptService:WaitForChild("PlayerStatsService"))
				PlayerStatsService.addWin(jugg)
				jugg:SetAttribute("StatWins", jugg:FindFirstChild("TotalWins") and jugg.TotalWins.Value or 0)
				for player in pairs(RoundData.contestants) do
					if player ~= jugg and player.Parent then
						PlayerStatsService.resetWinStreak(player)
					end
				end
			end)
		else
			-- All hunters share the win when the juggernaut is dethroned
			winner = nil
			winningTeam = "Survivors"
			RoundData.winner = nil
			RoundData.winningTeam = "Survivors"
			local hunters = RoundData.getHunterPlayers()
			pcall(function()
				local PlayerStatsService = require(ServerScriptService:WaitForChild("PlayerStatsService"))
				local winnerSet = {}
				for _, p in ipairs(hunters) do
					winnerSet[p] = true
					PlayerStatsService.addWin(p)
					p:SetAttribute("StatWins", p:FindFirstChild("TotalWins") and p.TotalWins.Value or 0)
				end
				for player in pairs(RoundData.contestants) do
					if player.Parent and not winnerSet[player] then
						PlayerStatsService.resetWinStreak(player)
					end
				end
			end)
		end
	else
		winner = resolveWinner(matchTime, playersAtStart)
		RoundData.winner = winner
		RoundData.winningTeam = nil

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
	end

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
					QuestService.onMatchPlayed(player)
				end
			end
		end
	end

	teleportPlayers(playersToReturnToLobby, lobbySpawn)

	clearAliveHud()

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

	ShrinkService.stop()
	ShrinkService.restoreAll()

	-- Ensure every arena tile is back to base look after shrink/hazard paint
	for _, tile in ipairs(getGridTiles(arenaGrid)) do
		resetTile(tile)
		tile.Anchored = true
	end

	RoundData.clearTeams()
	RoundData.clearJuggernaut()
	currentGameMode.Value = ""

	local resetClient = ReplicatedStorage:FindFirstChild("ResetClientSponsors")
	if resetClient then
		resetClient:FireAllClients()
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local viewMode = RoundData.isParticipant(player) and "participant" or "spectator"
		local payload = {
			viewMode = viewMode,
			rewards = buildRewardsForPlayer(player),
		}
		if isTeamMode and winningTeam then
			payload.winnerIsTeam = true
			payload.winningTeam = winningTeam
			payload.winnerName = winningTeam == "Blue" and "TEAM BLUE" or "TEAM RED"
			payload.winnerUserId = 0
		elseif isJuggernautMode and not juggernautWon then
			payload.winnerIsTeam = true
			payload.winningTeam = "Survivors"
			payload.winnerName = "SURVIVORS"
			payload.winnerUserId = 0
		elseif isJuggernautMode and juggernautWon and winner then
			payload.winnerIsTeam = false
			payload.winningTeam = "Juggernaut"
			payload.winnerName = winner.DisplayName
			payload.winnerUserId = winner.UserId
			payload.winnerIsJuggernaut = true
		else
			payload.winnerIsTeam = false
			payload.winnerName = winner and winner.DisplayName or "Unknown"
			payload.winnerUserId = winner and winner.UserId or 0
		end
		matchResultsEvent:FireClient(player, payload)
	end

	task.wait(2) 
end