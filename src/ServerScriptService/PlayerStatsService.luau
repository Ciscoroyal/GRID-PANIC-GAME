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
	return wins, kills, streak
end

local function pushOrdered(store, userId, value)
	if value <= 0 then return end
	pcall(function()
		store:SetAsync(tostring(userId), value)
	end)
end

local function syncBoards(player)
	scheduleLeaderboardRefresh()
	local wins, kills = ensureValues(player)
	local fans = player:FindFirstChild("AllTimeFans")
	pushOrdered(winsBoard, player.UserId, wins.Value)
	pushOrdered(killsBoard, player.UserId, kills.Value)
	if fans then
		pushOrdered(fansBoard, player.UserId, fans.Value)
	end
end

function PlayerStatsService.load(player)
	local wins, kills = ensureValues(player)
	local success, data = pcall(function()
		return statsStore:GetAsync(player.UserId)
	end)
	if success and type(data) == "table" then
		wins.Value = tonumber(data.wins) or 0
		kills.Value = tonumber(data.kills) or 0
		streak.Value = tonumber(data.winStreak) or 0
	else
		wins.Value = 0
		kills.Value = 0
		streak.Value = 0
	end
	loaded[player] = true
	player:SetAttribute("StatWins", wins.Value)
	player:SetAttribute("StatKills", kills.Value)
	player:SetAttribute("WinStreak", streak.Value)
	syncBoards(player)
	scheduleLeaderboardRefresh()

	task.spawn(function()
		local fans = player:WaitForChild("AllTimeFans", 20)
		if fans then
			syncBoards(player)
	scheduleLeaderboardRefresh()
			fans:GetPropertyChangedSignal("Value"):Connect(function()
				syncBoards(player)
			end)
		end
	end)
end

function PlayerStatsService.save(player)
	if not loaded[player] then return end
	local wins, kills, streak = ensureValues(player)
	pcall(function()
		statsStore:SetAsync(player.UserId, {
			wins = wins.Value,
			kills = kills.Value,
			winStreak = streak.Value,
		})
	end)
end

function PlayerStatsService.addWin(player)
	local wins, _, streak = ensureValues(player)
	wins.Value += 1
	streak.Value += 1
	player:SetAttribute("StatWins", wins.Value)
	player:SetAttribute("WinStreak", streak.Value)
	syncBoards(player)
	scheduleLeaderboardRefresh()
	PlayerStatsService.save(player)
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
	syncBoards(player)
	scheduleLeaderboardRefresh()
end

function PlayerStatsService.syncFans(player)
	syncBoards(player)
	scheduleLeaderboardRefresh()
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
