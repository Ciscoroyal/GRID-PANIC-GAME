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
local HazardHitService = require(ServerScriptService:WaitForChild("HazardHitService"))
local LobbySpawnService = require(ServerScriptService:WaitForChild("LobbySpawnService"))
local WinnerDisplayService = require(ServerScriptService:WaitForChild("WinnerDisplayService"))
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

--[[
	Spread contestants evenly around a circle near the arena edge, all facing the
	centre, instead of stacking everyone on ArenaSpawn. Each slot snaps to the top
	of the closest unused tile so nobody spawns over a gap or inside a neighbour.
]]
local function teleportPlayersInRing(contestants, tiles, fallbackPart, centrePlayer)
	local count = #contestants
	if count == 0 then
		return
	end

	local minX, maxX, minZ, maxZ, y = getArenaBounds(tiles, fallbackPart)
	local centerX = (minX + maxX) / 2
	local centerZ = (minZ + maxZ) / 2
	local halfSpan = math.min(maxX - minX, maxZ - minZ) / 2
	-- Tighter than the old 0.7: at 0.7 players started too far apart to threaten
	-- each other early in the round.
	local radius = math.max(6, halfSpan * 0.5)

	local usedTiles = {}

	-- The juggernaut starts dead centre, surrounded by the hunters.
	local ringPlayers = contestants
	if centrePlayer then
		ringPlayers = {}
		for _, player in ipairs(contestants) do
			if player ~= centrePlayer then
				table.insert(ringPlayers, player)
			end
		end
	end
	local function nearestFreeTile(position)
		local bestTile, bestDist = nil, math.huge
		for _, tile in ipairs(tiles) do
			if not usedTiles[tile] then
				local dx = tile.Position.X - position.X
				local dz = tile.Position.Z - position.Z
				local dist = (dx * dx) + (dz * dz)
				if dist < bestDist then
					bestDist = dist
					bestTile = tile
				end
			end
		end
		return bestTile
	end

	if centrePlayer then
		local character = centrePlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local pos = Vector3.new(centerX, y, centerZ)
			local tile = nearestFreeTile(pos)
			if tile then
				usedTiles[tile] = true
				pos = Vector3.new(
					tile.Position.X,
					tile.Position.Y + (tile.Size.Y / 2) + 3,
					tile.Position.Z
				)
			end
			root.CFrame = CFrame.new(pos)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local ringCount = #ringPlayers
	if ringCount == 0 then
		return
	end

	-- Random offset so the same player is not always in the same seat.
	local angleOffset = math.random() * math.pi * 2
	local angleStep = (math.pi * 2) / ringCount

	for i, player in ipairs(ringPlayers) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local angle = angleOffset + (angleStep * (i - 1))
			local pos = Vector3.new(
				centerX + (math.cos(angle) * radius),
				y,
				centerZ + (math.sin(angle) * radius)
			)

			local tile = nearestFreeTile(pos)
			if tile then
				usedTiles[tile] = true
				pos = Vector3.new(
					tile.Position.X,
					tile.Position.Y + (tile.Size.Y / 2) + 3,
					tile.Position.Z
				)
			end

			local lookAt = Vector3.new(centerX, pos.Y, centerZ)
			if (Vector3.new(lookAt.X, 0, lookAt.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 0.1 then
				lookAt = pos + Vector3.new(0, 0, 1)
			end

			root.CFrame = CFrame.lookAt(pos, lookAt)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
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

-- Eliminations landing within this window are treated as one event, not a race.
local SIMULTANEOUS_DEATH_WINDOW = 0.15

--[[
	Returns winner, isDraw.

	When a single block catches the last players standing together they are all
	eliminated on the same tick, so their survival times are identical and the
	old "highest time wins" scan just returned whichever the hash order reached
	first - crowning someone who died at the same instant as everyone else.
	That case is now a draw.
]]
local function resolveWinner(matchTime, playersAtStart)
	-- Anyone still standing wins outright.
	for _, player in ipairs(Players:GetPlayers()) do
		if isAliveContestant(player) and RoundData.didPlay(player) then
			return player, false
		end
	end

	local bestTime = -1
	for player in pairs(RoundData.contestants) do
		local survivalTime = eliminationTimes[player] or matchTime
		if survivalTime > bestTime then
			bestTime = survivalTime
		end
	end

	local tied = {}
	for player in pairs(RoundData.contestants) do
		local survivalTime = eliminationTimes[player] or matchTime
		if math.abs(survivalTime - bestTime) <= SIMULTANEOUS_DEATH_WINDOW then
			table.insert(tied, player)
		end
	end

	if #tied > 1 then
		return nil, true
	end
	if tied[1] then
		return tied[1], false
	end

	if lastAlivePlayer and lastAlivePlayer.Parent and RoundData.didPlay(lastAlivePlayer) then
		return lastAlivePlayer, false
	end

	if #eliminationOrder > 0 then
		return eliminationOrder[#eliminationOrder], false
	end

	if playersAtStart == 1 then
		for player in pairs(RoundData.contestants) do
			return player, false
		end
	end

	return nil, false
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

-- =========================================================
-- PRE-MATCH LOCK
-- Players are frozen from the moment they land in the arena until the roll
-- call UI disappears, so nobody can walk, jump, dash, punch or use an ability
-- while the line-up is still on screen. Client scripts read the MatchLocked
-- attribute; the humanoid changes below are the server-side enforcement.
-- Keep this matched to the hide delay in StarterGui.RollCallGui.RollCallController.
-- =========================================================
local ROLL_CALL_DISPLAY_SECONDS = 3.2

local frozenMovement = {}

local function getStarterWalkSpeed()
	local speed = game:GetService("StarterPlayer").CharacterWalkSpeed
	if typeof(speed) ~= "number" or speed <= 0 then
		speed = 16
	end
	return speed
end

local function applyFreeze(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if not frozenMovement[player] then
		frozenMovement[player] = {
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
		}
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function lockContestants(contestants)
	for _, player in ipairs(contestants) do
		player:SetAttribute("MatchLocked", true)
		applyFreeze(player)
	end
end

local function releaseContestant(player)
	player:SetAttribute("MatchLocked", nil)

	local saved = frozenMovement[player]
	frozenMovement[player] = nil

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local starterPlayer = game:GetService("StarterPlayer")

	local walkSpeed = saved and saved.walkSpeed or nil
	if typeof(walkSpeed) ~= "number" or walkSpeed <= 0 then
		walkSpeed = getStarterWalkSpeed()
	end

	local jumpPower = saved and saved.jumpPower or nil
	if typeof(jumpPower) ~= "number" or jumpPower <= 0 then
		jumpPower = starterPlayer.CharacterJumpPower
		if typeof(jumpPower) ~= "number" or jumpPower <= 0 then
			jumpPower = 50
		end
	end

	local jumpHeight = saved and saved.jumpHeight or nil
	if typeof(jumpHeight) ~= "number" or jumpHeight <= 0 then
		jumpHeight = starterPlayer.CharacterJumpHeight
		if typeof(jumpHeight) ~= "number" or jumpHeight <= 0 then
			jumpHeight = 7.2
		end
	end

	humanoid.WalkSpeed = walkSpeed
	humanoid.JumpPower = jumpPower
	humanoid.JumpHeight = jumpHeight
end

local function releaseContestants(contestants)
	for _, player in ipairs(contestants) do
		releaseContestant(player)
	end
end

--[[
	Holds everyone still for exactly as long as the roll call UI is on screen,
	then hands control back. Freeze is re-applied while waiting so a mid-window
	respawn can't give someone early movement.
]]
local function holdUntilRollCallEnds(contestants)
	local deadline = os.clock() + ROLL_CALL_DISPLAY_SECONDS
	while os.clock() < deadline do
		for _, player in ipairs(contestants) do
			if player.Parent and player:GetAttribute("MatchLocked") == true then
				applyFreeze(player)
			end
		end
		task.wait(0.25)
	end

	releaseContestants(contestants)
end

-- Teleport helper function
local function teleportPlayers(playersList, targetPart)
	local toLobby = targetPart == lobbySpawn
	for _, player in ipairs(playersList) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			-- Returning a whole field to one point stacks everyone inside each
			-- other; scatter them across the lobby instead.
			if toLobby and LobbySpawnService.placeCharacter(character) then
				continue
			end
			character.HumanoidRootPart.CFrame = targetPart.CFrame * CFrame.new(0, 3, 0)
		end
	end
end

--[[
	Safety net for the walk home at the end of a round.

	teleportPlayers only moves players who are InArena, not eliminated, and who
	happen to have a character with a root part at that exact instant. Anyone
	mid-respawn was silently skipped, and an eliminated player whose own return
	was swallowed by EliminationService's re-entrancy guard was never in the list
	to begin with - either way they were left standing in the arena until the
	next round moved them.

	So instead of trusting the sweep, check where everyone actually ended up and
	move whoever is still out there.
]]
local ARENA_EXIT_PADDING = 14 -- studs past the tile footprint that still counts as "in the arena"
local ARENA_EXIT_ATTEMPTS = 3
local pendingLobbyPlacement = {} -- [player] = RBXScriptConnection

local function getArenaBounds()
	local tiles = getGridTiles(arenaGrid)
	if #tiles == 0 then
		return nil
	end
	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	local topY = -math.huge
	for _, tile in ipairs(tiles) do
		-- Fallen tiles have been tweened 40 studs down; their home position is what
		-- defines the footprint, so use the widest reading either way.
		minX = math.min(minX, tile.Position.X)
		maxX = math.max(maxX, tile.Position.X)
		minZ = math.min(minZ, tile.Position.Z)
		maxZ = math.max(maxZ, tile.Position.Z)
		topY = math.max(topY, tile.Position.Y)
	end
	return {
		minX = minX - ARENA_EXIT_PADDING,
		maxX = maxX + ARENA_EXIT_PADDING,
		minZ = minZ - ARENA_EXIT_PADDING,
		maxZ = maxZ + ARENA_EXIT_PADDING,
		minY = topY - 60,
		maxY = topY + 60,
	}
end

local function isInsideArena(position, bounds)
	return position.X >= bounds.minX and position.X <= bounds.maxX
		and position.Z >= bounds.minZ and position.Z <= bounds.maxZ
		and position.Y >= bounds.minY and position.Y <= bounds.maxY
end

-- No character to move right now: place them the moment they get one.
local function placeOnNextCharacter(player)
	if pendingLobbyPlacement[player] then
		return
	end
	local connection
	connection = player.CharacterAdded:Connect(function(character)
		connection:Disconnect()
		pendingLobbyPlacement[player] = nil
		character:WaitForChild("HumanoidRootPart", 10)
		-- Only if they have not been sent into a new round in the meantime.
		if player:GetAttribute("InArena") ~= true then
			LobbySpawnService.placeCharacter(character)
		end
	end)
	pendingLobbyPlacement[player] = connection
	task.delay(20, function()
		if pendingLobbyPlacement[player] == connection then
			connection:Disconnect()
			pendingLobbyPlacement[player] = nil
		end
	end)
end

local function ensureEveryoneLeftTheArena()
	local bounds = getArenaBounds()
	if not bounds then
		return
	end

	for _ = 1, ARENA_EXIT_ATTEMPTS do
		local stragglers = {}
		for _, player in ipairs(Players:GetPlayers()) do
			-- Practice happens on its own grid well away from the arena, so this
			-- never drags a practising player out of their session.
			if player:GetAttribute("InPractice") ~= true then
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then
					if isInsideArena(root.Position, bounds) then
						table.insert(stragglers, player)
					end
				else
					placeOnNextCharacter(player)
				end
			end
		end

		if #stragglers == 0 then
			return
		end

		teleportPlayers(stragglers, lobbySpawn)
		task.wait(0.35)
	end

	warn("[HazardSpawner] Some players could not be returned to the lobby after the round.")
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

	-- 4. THE INSTANT KILL (bypasses physics engine lag completely)
	-- Position-based and lag-compensated - see HazardHitService for why the old
	-- bounding-box sweep was replaced.
	local hitPlayers = HazardHitService.getPlayersHit(targetTile, function(player)
		return player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true
	end)

	for _, player in ipairs(hitPlayers) do
		-- Juggernaut immunity is enforced inside EliminationService.
		EliminationService.eliminate(player, { cause = "hazard", respectShield = true })
	end

	-- 5. Spawn the invisible server hitbox just in case your other scripts need the "CanKill" attribute
	local serverHitbox = hazardCubeModel:Clone()
	serverHitbox:SetAttribute("CanKill", true)

	-- Strip the touch-based elimination script. It is a second kill path with
	-- the old unfair semantics and would undo the check above.
	for _, descendant in ipairs(serverHitbox:GetDescendants()) do
		if descendant:IsA("BaseScript") and descendant.Name == "EliminationScript" then
			descendant:Destroy()
		end
	end

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
	-- The mode poll is already running - it opens when the previous match starts
	-- so the lobby has the whole round to decide. It only closes here.
	clearAliveHud()
	local intermissionDuration = 10

	if not VoteService.isActive() then
		-- First round of the server, or the poll was lost somehow.
		VoteService.open()
	end

	for i = intermissionDuration, 1, -1 do
		survivalTimeValue.Value = i
		task.wait(1)
		if #Players:GetPlayers() < 1 then
			repeat task.wait(1) until #Players:GetPlayers() >= 1
		end
	end

	local chosenMode = VoteService.close() or "Classic"

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
	-- Last round's giant winner steps off the lobby floor.
	WinnerDisplayService.clear()

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
		-- Counts toward the "matches played" achievement ladder.
		pcall(function()
			local PlayerStatsService = require(ServerScriptService:WaitForChild("PlayerStatsService"))
			PlayerStatsService.addMatch(player)
		end)
	end

	-- Freeze before the teleport so nobody gets a free frame of movement on landing.
	lockContestants(activeContestants)

	-- Pick the juggernaut before placing anyone: they start in the middle with
	-- the hunters ringed around them.
	local juggernaut = nil
	if chosenMode == "Juggernaut" then
		juggernaut = activeContestants[math.random(1, #activeContestants)]
		RoundData.setJuggernaut(juggernaut)
	end

	local tilesForSpawn = getGridTiles(arenaGrid)
	if chosenMode == "Team" then
		assignTeams(activeContestants)
		teleportTeamsOppositeSides(activeContestants, tilesForSpawn, arenaSpawn)
	else
		teleportPlayersInRing(activeContestants, tilesForSpawn, arenaSpawn, juggernaut)
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

	holdUntilRollCallEnds(activeContestants)

	if chosenMode == "Shrinking" then
		ShrinkService.start(cachedArenaTiles)
	end

	updateAliveHud()

	-- Voting for the NEXT round opens the moment this one starts, giving anyone
	-- in the lobby the whole match to make up their mind.
	VoteService.open()

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
	local matchDraw = false

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
		winner, matchDraw = resolveWinner(matchTime, playersAtStart)
		RoundData.winner = winner
		RoundData.winningTeam = nil

		if winner and winner.Parent and not matchDraw then
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
			--[[
				Only move players who are still out in the arena. Eliminated players
				were already returned to the lobby when they died, and sending them
				again here teleported them a second time - you would land, stand
				still, then get yanked somewhere else when the round wrapped up.
			]]
			if player:GetAttribute("IsEliminated") ~= true then
				table.insert(playersToReturnToLobby, player)
			end

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
	ensureEveryoneLeftTheArena()

	clearAliveHud()

	for _, player in ipairs(Players:GetPlayers()) do
		-- Safety net: nobody leaves a round still frozen.
		if player:GetAttribute("MatchLocked") == true or frozenMovement[player] then
			releaseContestant(player)
		end
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
		elseif matchDraw then
			-- No avatar to show: everyone left went out together.
			payload.winnerIsTeam = true
			payload.isDraw = true
			payload.winningTeam = nil
			payload.winnerName = "DRAW"
			payload.winnerUserId = 0
		else
			payload.winnerIsTeam = false
			payload.winnerName = winner and winner.DisplayName or "Unknown"
			payload.winnerUserId = winner and winner.UserId or 0
		end
		matchResultsEvent:FireClient(player, payload)
	end

	-- Put the winner up in the lobby, giant, so it is obvious who took it.
	if winner and not matchDraw then
		WinnerDisplayService.show(winner)
	elseif isJuggernautMode and juggernautWon and winner then
		WinnerDisplayService.show(winner)
	end

	-- Stats only change here, so this is the moment the boards are stale.
	local leaderboardRefresh = ServerStorage:FindFirstChild("LeaderboardRefresh")
	if leaderboardRefresh then
		leaderboardRefresh:Fire()
	end

	task.wait(2) 
end