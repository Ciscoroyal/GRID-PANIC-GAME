local ServerStorage = game:GetService("ServerStorage")

local refreshScheduled = false
local function scheduleLeaderboardRefresh()
	if refreshScheduled then
		return
	end
	refreshScheduled = true
	task.delay(2, function()
		refreshScheduled = false
		local refreshEvent = ServerStorage:FindFirstChild("LeaderboardRefresh")
		if refreshEvent then
			refreshEvent:Fire()
		end
	end)
end

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local statsStore = DataStoreService:GetDataStore("PlayerStats_V1")
local winsBoard = DataStoreService:GetOrderedDataStore("GridPanic_Wins_V1")
local killsBoard = DataStoreService:GetOrderedDataStore("GridPanic_Kills_V1")
local fansBoard = DataStoreService:GetOrderedDataStore("GridPanic_Fans_V1")

local PlayerStatsService = {}
local loaded = {}
local boardDirty = {}
local flushScheduled = {}

local function ensureValues(player)
	local wins = player:FindFirstChild("TotalWins")
	if not wins then
		wins = Instance.new("IntValue")
		wins.Name = "TotalWins"
		wins.Parent = player
	end
	local kills = player:FindFirstChild("TotalKills")
	if not kills then
		kills = Instance.new("IntValue")
		kills.Name = "TotalKills"
		kills.Parent = player
	end
	local streak = player:FindFirstChild("WinStreak")
	if not streak then
		streak = Instance.new("IntValue")
		streak.Name = "WinStreak"
		streak.Parent = player
	end
	-- Matches played: the long-haul grind stat the achievement ladder needs.
	local matches = player:FindFirstChild("TotalMatches")
	if not matches then
		matches = Instance.new("IntValue")
		matches.Name = "TotalMatches"
		matches.Parent = player
	end
	return wins, kills, streak, matches
end

local function pushOrdered(store, userId, value)
	if value <= 0 then
		return
	end
	pcall(function()
		store:SetAsync(tostring(userId), value)
	end)
end

local function flushOrderedBoards(player)
	if not player or not loaded[player] then
		return
	end

	boardDirty[player] = nil
	local wins, kills = ensureValues(player)
	local fans = player:FindFirstChild("AllTimeFans")
	pushOrdered(winsBoard, player.UserId, wins.Value)
	pushOrdered(killsBoard, player.UserId, kills.Value)
	if fans then
		pushOrdered(fansBoard, player.UserId, fans.Value)
	end
	scheduleLeaderboardRefresh()
end

local function markBoardsDirty(player)
	boardDirty[player] = true
	scheduleLeaderboardRefresh()
end

-- Batch OrderedDataStore writes so kills/fans don't hammer budget every change.
local function scheduleBoardFlush(player, delaySeconds)
	markBoardsDirty(player)
	if flushScheduled[player] then
		return
	end
	flushScheduled[player] = true
	task.delay(delaySeconds or 5, function()
		flushScheduled[player] = nil
		if player.Parent and boardDirty[player] then
			flushOrderedBoards(player)
		end
	end)
end

function PlayerStatsService.load(player)
	local wins, kills, streak, matches = ensureValues(player)
	local success, data = pcall(function()
		return statsStore:GetAsync(player.UserId)
	end)
	local bestStreak = 0
	if success and type(data) == "table" then
		wins.Value = tonumber(data.wins) or 0
		kills.Value = tonumber(data.kills) or 0
		streak.Value = tonumber(data.winStreak) or 0
		matches.Value = tonumber(data.matches) or 0
		bestStreak = tonumber(data.bestWinStreak) or streak.Value
	else
		wins.Value = 0
		kills.Value = 0
		streak.Value = 0
		matches.Value = 0
	end
	loaded[player] = true
	player:SetAttribute("StatWins", wins.Value)
	player:SetAttribute("StatKills", kills.Value)
	player:SetAttribute("WinStreak", streak.Value)
	player:SetAttribute("StatMatches", matches.Value)
	player:SetAttribute("BestWinStreak", math.max(bestStreak, streak.Value))

	-- One ordered write on join keeps boards healthy without per-kill spam.
	flushOrderedBoards(player)

	task.spawn(function()
		local fans = player:WaitForChild("AllTimeFans", 20)
		if fans then
			flushOrderedBoards(player)
			fans:GetPropertyChangedSignal("Value"):Connect(function()
				scheduleBoardFlush(player, 5)
			end)
		end
	end)
end

function PlayerStatsService.save(player)
	if not loaded[player] then
		return
	end
	local wins, kills, streak, matches = ensureValues(player)
	pcall(function()
		statsStore:SetAsync(player.UserId, {
			wins = wins.Value,
			kills = kills.Value,
			winStreak = streak.Value,
			matches = matches.Value,
			bestWinStreak = player:GetAttribute("BestWinStreak") or streak.Value,
		})
	end)
	flushOrderedBoards(player)
end

-- Counted once per match entered, for the "matches played" ladder.
function PlayerStatsService.addMatch(player)
	local _, _, _, matches = ensureValues(player)
	matches.Value += 1
	player:SetAttribute("StatMatches", matches.Value)
end

function PlayerStatsService.addWin(player)
	local wins, _, streak = ensureValues(player)
	wins.Value += 1
	streak.Value += 1
	player:SetAttribute("StatWins", wins.Value)
	player:SetAttribute("WinStreak", streak.Value)
	-- Highest streak ever reached, so a streak trophy is never taken back.
	if streak.Value > (player:GetAttribute("BestWinStreak") or 0) then
		player:SetAttribute("BestWinStreak", streak.Value)
	end
	-- Wins are rare; flush immediately so podiums update promptly.
	PlayerStatsService.save(player)
	pcall(function()
		local QuestService = require(game:GetService("ServerScriptService"):WaitForChild("QuestService"))
		QuestService.onWin(player)
	end)
end

function PlayerStatsService.resetWinStreak(player)
	local _, _, streak = ensureValues(player)
	streak.Value = 0
	player:SetAttribute("WinStreak", 0)
	PlayerStatsService.save(player)
end

function PlayerStatsService.addKill(player)
	local _, kills = ensureValues(player)
	kills.Value += 1
	player:SetAttribute("StatKills", kills.Value)
	scheduleBoardFlush(player, 5)
end

function PlayerStatsService.syncFans(player)
	scheduleBoardFlush(player, 5)
end

function PlayerStatsService.getSnapshot(player)
	local wins, kills = ensureValues(player)
	local fans = player:FindFirstChild("AllTimeFans")
	return {
		wins = wins.Value,
		kills = kills.Value,
		fans = fans and fans.Value or 0,
	}
end

function PlayerStatsService.getTop(store, count)
	count = count or 10
	local entries = {}
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, count)
	end)
	if not ok or not pages then
		return entries
	end
	local page = pages:GetCurrentPage()
	for rank, item in ipairs(page) do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, {
				rank = rank,
				userId = userId,
				value = item.value,
			})
		end
	end
	return entries
end

function PlayerStatsService.getAllTop(count)
	return {
		Wins = PlayerStatsService.getTop(winsBoard, count),
		Kills = PlayerStatsService.getTop(killsBoard, count),
		Fans = PlayerStatsService.getTop(fansBoard, count),
	}
end

function PlayerStatsService.getStores()
	return {
		Wins = winsBoard,
		Kills = killsBoard,
		Fans = fansBoard,
	}
end

Players.PlayerAdded:Connect(function(player)
	PlayerStatsService.load(player)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerStatsService.save(player)
	loaded[player] = nil
	boardDirty[player] = nil
	flushScheduled[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	PlayerStatsService.load(player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerStatsService.save(player)
	end
	task.wait(1)
end)

return PlayerStatsService

