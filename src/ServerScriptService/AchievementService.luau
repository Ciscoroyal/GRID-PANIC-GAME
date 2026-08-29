local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local AchievementDefinitions = require(ReplicatedStorage:WaitForChild("AchievementDefinitions"))
local CoinRewards = require(ReplicatedStorage:WaitForChild("CoinRewards"))

local achievementStore = DataStoreService:GetDataStore("Achievements_V1")
local achievementStateEvent = ReplicatedStorage:WaitForChild("AchievementStateEvent")
local claimAchievementEvent = ReplicatedStorage:WaitForChild("ClaimAchievementEvent")

local AchievementService = {}
local cache = {}

--[[
	Every Stat named in AchievementDefinitions has to resolve here. The values
	all already existed in the game; only `matches` needed new tracking.
]]
local function readStat(player, statKey)
	if statKey == "wins" then
		local wins = player:FindFirstChild("TotalWins")
		return wins and wins.Value or (player:GetAttribute("StatWins") or 0)
	elseif statKey == "kills" then
		local kills = player:FindFirstChild("TotalKills")
		return kills and kills.Value or (player:GetAttribute("StatKills") or 0)
	elseif statKey == "fans" then
		local fans = player:FindFirstChild("AllTimeFans")
		return fans and fans.Value or 0
	elseif statKey == "streak" then
		-- Best streak reached, not the current one: an achievement should not
		-- un-earn itself the moment you lose.
		local best = player:GetAttribute("BestWinStreak") or 0
		local current = player:FindFirstChild("WinStreak")
		return math.max(best, current and current.Value or 0)
	elseif statKey == "level" then
		return player:GetAttribute("PlayerLevel") or 1
	elseif statKey == "matches" then
		local matches = player:FindFirstChild("TotalMatches")
		return matches and matches.Value or (player:GetAttribute("StatMatches") or 0)
	elseif statKey == "coins" then
		local leaderstats = player:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		return coins and coins.Value or 0
	end
	return 0
end

local function blankState()
	local claimed = {}
	for _, id in ipairs(AchievementDefinitions.ORDER) do
		claimed[id] = false
	end
	return { claimed = claimed }
end

local function normalizeState(data)
	local state = blankState()
	if type(data) ~= "table" or type(data.claimed) ~= "table" then
		return state
	end
	for _, id in ipairs(AchievementDefinitions.ORDER) do
		state.claimed[id] = data.claimed[id] == true
	end
	return state
end

local function buildPayload(player, state)
	local achievements = {}
	for _, id in ipairs(AchievementDefinitions.ORDER) do
		local def = AchievementDefinitions.get(id)
		local progress = math.min(readStat(player, def.Stat), def.Goal)
		local complete = progress >= def.Goal
		achievements[id] = {
			id = id,
			title = def.Title,
			description = def.Description,
			progress = progress,
			goal = def.Goal,
			rewardCoins = def.RewardCoins,
			complete = complete,
			claimed = state.claimed[id] == true,
		}
	end
	return { achievements = achievements }
end

local function saveState(player)
	local state = cache[player]
	if not state then return end
	pcall(function()
		achievementStore:SetAsync(player.UserId, state)
	end)
end

local function pushState(player)
	local state = cache[player]
	if not state then return end
	achievementStateEvent:FireClient(player, buildPayload(player, state))
end

function AchievementService.load(player)
	local success, data = pcall(function()
		return achievementStore:GetAsync(player.UserId)
	end)
	cache[player] = normalizeState(success and data or nil)
	pushState(player)
end

function AchievementService.refresh(player)
	if cache[player] then
		pushState(player)
	end
end

local function claimAchievement(player, achievementId)
	local state = cache[player]
	local def = AchievementDefinitions.get(achievementId)
	if not state or not def then
		return false
	end
	if state.claimed[achievementId] then
		return false
	end
	if readStat(player, def.Stat) < def.Goal then
		return false
	end
	state.claimed[achievementId] = true
	CoinRewards.awardCoins(player, def.RewardCoins)
	saveState(player)
	pushState(player)
	return true
end

local function bindStatListeners(player)
	local function hook(valueObject)
		if not valueObject then return end
		valueObject:GetPropertyChangedSignal("Value"):Connect(function()
			AchievementService.refresh(player)
		end)
	end

	task.spawn(function()
		local wins = player:WaitForChild("TotalWins", 20)
		local kills = player:WaitForChild("TotalKills", 20)
		local fans = player:WaitForChild("AllTimeFans", 20)
		hook(wins)
		hook(kills)
		hook(fans)
	end)

	player:GetAttributeChangedSignal("StatWins"):Connect(function()
		AchievementService.refresh(player)
	end)
	player:GetAttributeChangedSignal("StatKills"):Connect(function()
		AchievementService.refresh(player)
	end)
end

claimAchievementEvent.OnServerEvent:Connect(function(player, achievementId)
	if typeof(achievementId) ~= "string" then return end
	claimAchievement(player, achievementId)
end)

Players.PlayerAdded:Connect(function(player)
	bindStatListeners(player)
	AchievementService.load(player)
end)

Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	cache[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindStatListeners(player)
	AchievementService.load(player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveState(player)
	end
	task.wait(1)
end)

return AchievementService