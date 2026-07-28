local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local QuestDefinitions = require(ReplicatedStorage:WaitForChild("QuestDefinitions"))
local CoinRewards = require(ReplicatedStorage:WaitForChild("CoinRewards"))

local questStore = DataStoreService:GetDataStore("DailyQuests_V1")
local questStateEvent = ReplicatedStorage:WaitForChild("QuestStateEvent")
local claimQuestEvent = ReplicatedStorage:WaitForChild("ClaimQuestEvent")

local QuestService = {}
local cache = {}

local function todayKey()
	return os.date("!%Y-%m-%d")
end

local function blankState()
	local progress = {}
	local claimed = {}
	for _, questId in ipairs(QuestDefinitions.ORDER) do
		progress[questId] = 0
		claimed[questId] = false
	end
	return {
		day = todayKey(),
		progress = progress,
		claimed = claimed,
	}
end

local function normalizeState(data)
	local state = blankState()
	if type(data) ~= "table" then
		return state
	end
	if data.day ~= todayKey() then
		return state
	end
	state.day = data.day
	for _, questId in ipairs(QuestDefinitions.ORDER) do
		state.progress[questId] = tonumber(data.progress and data.progress[questId]) or 0
		state.claimed[questId] = data.claimed and data.claimed[questId] == true
	end
	return state
end

local function buildPayload(state)
	local quests = {}
	for _, questId in ipairs(QuestDefinitions.ORDER) do
		local def = QuestDefinitions.get(questId)
		local progress = state.progress[questId] or 0
		local goal = def.Goal
		local complete = progress >= goal
		quests[questId] = {
			id = questId,
			title = def.Title,
			description = def.Description,
			progress = progress,
			goal = goal,
			rewardCoins = def.RewardCoins,
			complete = complete,
			claimed = state.claimed[questId] == true,
		}
	end
	return {
		day = state.day,
		quests = quests,
	}
end

local function saveState(player)
	local state = cache[player]
	if not state then return end
	pcall(function()
		questStore:SetAsync(player.UserId, state)
	end)
end

local function pushState(player)
	local state = cache[player]
	if not state then return end
	questStateEvent:FireClient(player, buildPayload(state))
end

function QuestService.load(player)
	local success, data = pcall(function()
		return questStore:GetAsync(player.UserId)
	end)
	cache[player] = normalizeState(success and data or nil)
	pushState(player)
end

local function increment(player, questId, amount)
	amount = amount or 1
	local state = cache[player]
	if not state then return end
	if state.claimed[questId] then return end
	local def = QuestDefinitions.get(questId)
	if not def then return end
	local current = state.progress[questId] or 0
	local nextValue = current
	if questId == "Survive60" then
		nextValue = math.max(current, amount)
	else
		nextValue = current + amount
	end
	nextValue = math.min(nextValue, def.Goal)
	if nextValue == current then return end
	state.progress[questId] = nextValue
	saveState(player)
	pushState(player)
end

function QuestService.onSurvival(player, seconds)
	if typeof(seconds) ~= "number" then return end
	increment(player, "Survive60", math.floor(seconds))
end

function QuestService.onSponsorWinner(player)
	increment(player, "SponsorWinner", 1)
end

function QuestService.onAbilityUsed(player)
	increment(player, "UseAbility", 1)
end

local function claimQuest(player, questId)
	local state = cache[player]
	if not state or not QuestDefinitions.get(questId) then
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
	if typeof(questId) ~= "string" then return end
	claimQuest(player, questId)
end)

Players.PlayerAdded:Connect(function(player)
	QuestService.load(player)
end)

Players.PlayerRemoving:Connect(function(player)
	saveState(player)
	cache[player] = nil
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
