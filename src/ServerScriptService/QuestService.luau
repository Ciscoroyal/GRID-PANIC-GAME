local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local QuestDefinitions = require(ReplicatedStorage:WaitForChild("QuestDefinitions"))
local CoinRewards = require(ReplicatedStorage:WaitForChild("CoinRewards"))

local questStore = DataStoreService:GetDataStore("DailyQuests_V2")
local questStateEvent = ReplicatedStorage:WaitForChild("QuestStateEvent")
local claimQuestEvent = ReplicatedStorage:WaitForChild("ClaimQuestEvent")

local dashQuestEvent = ReplicatedStorage:FindFirstChild("DashQuestEvent")
if not dashQuestEvent then
	dashQuestEvent = Instance.new("RemoteEvent")
	dashQuestEvent.Name = "DashQuestEvent"
	dashQuestEvent.Parent = ReplicatedStorage
end

local QuestService = {}
local cache = {}
local lastDashAt = {}

local function todayKey()
	return os.date("!%Y-%m-%d")
end

local function blankState()
	local day = todayKey()
	local active = QuestDefinitions.pickForDay(day, QuestDefinitions.DAILY_COUNT)
	local progress = {}
	local claimed = {}
	for _, questId in ipairs(active) do
		progress[questId] = 0
		claimed[questId] = false
	end
	return {
		day = day,
		active = active,
		progress = progress,
		claimed = claimed,
	}
end

local function isActiveQuest(state, questId)
	if not state or not state.active then
		return false
	end
	for _, id in ipairs(state.active) do
		if id == questId then
			return true
		end
	end
	return false
end

local function normalizeState(data)
	local today = todayKey()
	if type(data) ~= "table" or data.day ~= today then
		return blankState()
	end

	local active = data.active
	if type(active) ~= "table" or #active == 0 then
		active = QuestDefinitions.pickForDay(today, QuestDefinitions.DAILY_COUNT)
	end

	local state = {
		day = today,
		active = {},
		progress = {},
		claimed = {},
	}

	for _, questId in ipairs(active) do
		if QuestDefinitions.get(questId) then
			table.insert(state.active, questId)
			state.progress[questId] = tonumber(data.progress and data.progress[questId]) or 0
			state.claimed[questId] = data.claimed and data.claimed[questId] == true
		end
	end

	if #state.active == 0 then
		return blankState()
	end
	return state
end

local function buildPayload(state)
	local quests = {}
	for _, questId in ipairs(state.active) do
		local def = QuestDefinitions.get(questId)
		if def then
			local progress = state.progress[questId] or 0
			local goal = def.Goal
			quests[questId] = {
				id = questId,
				title = def.Title,
				description = def.Description,
				progress = progress,
				goal = goal,
				rewardCoins = def.RewardCoins,
				type = def.Type,
				complete = progress >= goal,
				claimed = state.claimed[questId] == true,
			}
		end
	end
	return {
		day = state.day,
		order = table.clone(state.active),
		quests = quests,
	}
end

local function saveState(player)
	local state = cache[player]
	if not state then
		return
	end
	pcall(function()
		questStore:SetAsync(player.UserId, state)
	end)
end

local function pushState(player)
	local state = cache[player]
	if not state then
		return
	end
	questStateEvent:FireClient(player, buildPayload(state))
end

function QuestService.load(player)
	local success, data = pcall(function()
		return questStore:GetAsync(player.UserId)
	end)
	cache[player] = normalizeState(success and data or nil)
	pushState(player)
end

local function increment(player, questId, amount, useMax)
	amount = amount or 1
	local state = cache[player]
	if not state then
		return
	end
	if not isActiveQuest(state, questId) then
		return
	end
	if state.claimed[questId] then
		return
	end
	local def = QuestDefinitions.get(questId)
	if not def then
		return
	end

	local current = state.progress[questId] or 0
	local nextValue = useMax and math.max(current, amount) or (current + amount)
	nextValue = math.min(nextValue, def.Goal)
	if nextValue == current then
		return
	end

	state.progress[questId] = nextValue
	saveState(player)
	pushState(player)
end

local function incrementType(player, questType, amount, useMax)
	local state = cache[player]
	if not state then
		return
	end
	for _, questId in ipairs(state.active) do
		local def = QuestDefinitions.get(questId)
		if def and def.Type == questType then
			increment(player, questId, amount, useMax)
		end
	end
end

function QuestService.onSurvival(player, seconds)
	if typeof(seconds) ~= "number" then
		return
	end
	incrementType(player, "Survive", math.floor(seconds), true)
end

function QuestService.onMatchPlayed(player)
	incrementType(player, "Play", 1, false)
end

function QuestService.onWin(player)
	incrementType(player, "Win", 1, false)
end

function QuestService.onEliminate(player)
	incrementType(player, "Eliminate", 1, false)
end

function QuestService.onAbilityUsed(player)
	incrementType(player, "Ability", 1, false)
end

function QuestService.onSponsorWinner(player)
	incrementType(player, "SponsorWin", 1, false)
end

function QuestService.onSponsor(player)
	incrementType(player, "Sponsor", 1, false)
end

function QuestService.onDash(player)
	incrementType(player, "Dash", 1, false)
end

local function claimQuest(player, questId)
	local state = cache[player]
	if not state or not isActiveQuest(state, questId) or not QuestDefinitions.get(questId) then
		return false, "Invalid quest"
	end
	if state.claimed[questId] then
		return false, "Already claimed"
	end
	local progress = state.progress[questId] or 0
	local goal = QuestDefinitions.get(questId).Goal
	if progress < goal then
		return false, "Quest not complete"
	end
	state.claimed[questId] = true
	local def = QuestDefinitions.get(questId)
	CoinRewards.awardCoins(player, def.RewardCoins)
	saveState(player)
	pushState(player)
	return true, "Claimed"
end

claimQuestEvent.OnServerEvent:Connect(function(player, questId)
	if typeof(questId) ~= "string" then
		return
	end
	claimQuest(player, questId)
end)

dashQuestEvent.OnServerEvent:Connect(function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if player:GetAttribute("InArena") ~= true then
		return
	end
	if player:GetAttribute("IsEliminated") == true then
		return
	end
	local now = os.clock()
	if lastDashAt[player] and (now - lastDashAt[player]) < 0.35 then
		return
	end
	lastDashAt[player] = now
	QuestService.onDash(player)
end)

Players.PlayerAdded:Connect(function(player)
	QuestService.load(player)
end)

Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	cache[player] = nil
	lastDashAt[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	QuestService.load(player)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveState(player)
	end
	task.wait(1)
end)

return QuestService
