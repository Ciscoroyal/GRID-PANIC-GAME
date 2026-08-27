--[[
	Daily quest definitions + shared date-seeded rotation.
	Everyone gets the same DAILY_COUNT quests each UTC day.
]]

local QuestDefinitions = {
	Survive45 = {
		Id = "Survive45",
		Title = "Survive 45 Seconds",
		Description = "Stay alive for at least 45 seconds in one match.",
		Goal = 45,
		RewardCoins = 50,
		Type = "Survive",
	},
	Survive60 = {
		Id = "Survive60",
		Title = "Survive 60 Seconds",
		Description = "Stay alive for at least 60 seconds in one match.",
		Goal = 60,
		RewardCoins = 75,
		Type = "Survive",
	},
	Survive90 = {
		Id = "Survive90",
		Title = "Survive 90 Seconds",
		Description = "Stay alive for at least 90 seconds in one match.",
		Goal = 90,
		RewardCoins = 100,
		Type = "Survive",
	},
	SponsorWinner = {
		Id = "SponsorWinner",
		Title = "Back a Winner",
		Description = "Sponsor a player who wins the round.",
		Goal = 1,
		RewardCoins = 100,
		Type = "SponsorWin",
	},
	Sponsor1 = {
		Id = "Sponsor1",
		Title = "Cheer Once",
		Description = "Sponsor any player in a match.",
		Goal = 1,
		RewardCoins = 40,
		Type = "Sponsor",
	},
	UseAbility = {
		Id = "UseAbility",
		Title = "Use Your Ability",
		Description = "Activate your equipped ability during a match.",
		Goal = 1,
		RewardCoins = 50,
		Type = "Ability",
	},
	UseAbility3 = {
		Id = "UseAbility3",
		Title = "Ability Combo",
		Description = "Use your ability 3 times.",
		Goal = 3,
		RewardCoins = 75,
		Type = "Ability",
	},
	UseAbility5 = {
		Id = "UseAbility5",
		Title = "Ability Spammer",
		Description = "Use your ability 5 times.",
		Goal = 5,
		RewardCoins = 100,
		Type = "Ability",
	},
	Play3 = {
		Id = "Play3",
		Title = "Play 3 Matches",
		Description = "Finish 3 matches as a contestant.",
		Goal = 3,
		RewardCoins = 60,
		Type = "Play",
	},
	Play5 = {
		Id = "Play5",
		Title = "Play 5 Matches",
		Description = "Finish 5 matches as a contestant.",
		Goal = 5,
		RewardCoins = 90,
		Type = "Play",
	},
	Win1 = {
		Id = "Win1",
		Title = "Win a Match",
		Description = "Win a round.",
		Goal = 1,
		RewardCoins = 120,
		Type = "Win",
	},
	Win2 = {
		Id = "Win2",
		Title = "Win 2 Matches",
		Description = "Win 2 rounds.",
		Goal = 2,
		RewardCoins = 180,
		Type = "Win",
	},
	Eliminate1 = {
		Id = "Eliminate1",
		Title = "Get an Elimination",
		Description = "Get a combat elim / last-hit.",
		Goal = 1,
		RewardCoins = 100,
		Type = "Eliminate",
	},
	Eliminate2 = {
		Id = "Eliminate2",
		Title = "Get 2 Eliminations",
		Description = "Get 2 combat elims / last-hits.",
		Goal = 2,
		RewardCoins = 150,
		Type = "Eliminate",
	},
	Dash10 = {
		Id = "Dash10",
		Title = "Dash 10 Times",
		Description = "Dash 10 times during matches.",
		Goal = 10,
		RewardCoins = 60,
		Type = "Dash",
	},
}

-- Full rotation pool (same for all players each day)
QuestDefinitions.POOL = {
	"Survive45",
	"Survive60",
	"Survive90",
	"SponsorWinner",
	"Sponsor1",
	"UseAbility",
	"UseAbility3",
	"UseAbility5",
	"Play3",
	"Play5",
	"Win1",
	"Win2",
	"Eliminate1",
	"Eliminate2",
	"Dash10",
}

QuestDefinitions.DAILY_COUNT = 3

-- Legacy alias used by older UI; prefer pickForDay / payload.order
QuestDefinitions.ORDER = { "Survive60", "SponsorWinner", "UseAbility" }

function QuestDefinitions.get(questId)
	return QuestDefinitions[questId]
end

local function hashString(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end

-- Deterministic picks from the day key so every player shares the same dailies.
function QuestDefinitions.pickForDay(dayKey, count)
	count = math.max(1, count or QuestDefinitions.DAILY_COUNT)
	local pool = table.clone(QuestDefinitions.POOL)
	local seed = hashString(tostring(dayKey or ""))

	local function rand()
		seed = (seed * 1664525 + 1013904223) % 4294967296
		return seed / 4294967296
	end

	for i = #pool, 2, -1 do
		local j = math.floor(rand() * i) + 1
		pool[i], pool[j] = pool[j], pool[i]
	end

	local picks = {}
	for i = 1, math.min(count, #pool) do
		table.insert(picks, pool[i])
	end
	return picks
end

return QuestDefinitions
