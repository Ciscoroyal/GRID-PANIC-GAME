--[[
	Daily quest definitions + shared date-seeded rotation.
	Everyone gets the same DAILY_COUNT quests each UTC day.
]]

--[[
	The pool is generated from per-type tiers. A bigger pool is the whole point:
	with only fifteen entries and three picked a day, the same handful came round
	constantly.

	Every Type here must have a matching QuestService.on... hook, or the quest
	will sit at zero forever.
]]
local QuestDefinitions = {}

local FAMILIES = {
	{
		type = "Survive",
		tiers = {
			{ 30, "Survive 30 Seconds", "Stay alive for 30 seconds in one match.", 35 },
			{ 45, "Survive 45 Seconds", "Stay alive for 45 seconds in one match.", 50 },
			{ 60, "Survive 60 Seconds", "Stay alive for 60 seconds in one match.", 75 },
			{ 75, "Survive 75 Seconds", "Stay alive for 75 seconds in one match.", 90 },
			{ 90, "Survive 90 Seconds", "Stay alive for 90 seconds in one match.", 110 },
			{ 105, "Last Stand", "Stay alive for 105 seconds in one match.", 140 },
		},
	},
	{
		type = "Play",
		tiers = {
			{ 2, "Play 2 Matches", "Finish 2 matches as a contestant.", 40 },
			{ 3, "Play 3 Matches", "Finish 3 matches as a contestant.", 60 },
			{ 5, "Play 5 Matches", "Finish 5 matches as a contestant.", 90 },
			{ 8, "Marathon", "Finish 8 matches as a contestant.", 140 },
		},
	},
	{
		type = "Win",
		tiers = {
			{ 1, "Win a Match", "Win a round.", 120 },
			{ 2, "Win 2 Matches", "Win 2 rounds.", 180 },
			{ 3, "Triple Threat", "Win 3 rounds.", 260 },
		},
	},
	{
		type = "Eliminate",
		tiers = {
			{ 1, "Get an Elimination", "Knock one player out.", 100 },
			{ 2, "Double Trouble", "Knock 2 players out.", 150 },
			{ 3, "Hat Trick", "Knock 3 players out.", 210 },
			{ 5, "Cleanup Crew", "Knock 5 players out.", 300 },
		},
	},
	{
		type = "Ability",
		tiers = {
			{ 1, "Use Your Ability", "Activate your equipped ability.", 50 },
			{ 3, "Ability Combo", "Use your ability 3 times.", 75 },
			{ 5, "Ability Spammer", "Use your ability 5 times.", 100 },
			{ 8, "Button Masher", "Use your ability 8 times.", 140 },
			{ 12, "Never Off Cooldown", "Use your ability 12 times.", 190 },
		},
	},
	{
		type = "Sponsor",
		tiers = {
			{ 1, "Cheer Once", "Cheer for any player in a match.", 40 },
			{ 2, "Loud Crowd", "Cheer for 2 players.", 70 },
			{ 3, "Superfan", "Cheer for 3 players.", 100 },
		},
	},
	{
		type = "SponsorWin",
		tiers = {
			{ 1, "Back a Winner", "Cheer a player who goes on to win.", 100 },
			{ 2, "Kingmaker", "Cheer 2 players who go on to win.", 190 },
		},
	},
	{
		type = "Dash",
		tiers = {
			{ 10, "Dash 10 Times", "Dash 10 times during matches.", 60 },
			{ 20, "Quick Feet", "Dash 20 times during matches.", 100 },
			{ 35, "Blur", "Dash 35 times during matches.", 150 },
		},
	},
	{
		type = "Punch",
		tiers = {
			{ 1, "Land a Punch", "Land one Grid Punch on a player.", 60 },
			{ 3, "Bare Knuckle", "Land 3 Grid Punches.", 110 },
			{ 6, "Heavy Hands", "Land 6 Grid Punches.", 170 },
		},
	},
	{
		type = "Mine",
		tiers = {
			{ 1, "Lay a Trap", "Place one Proximity Mine.", 55 },
			{ 3, "Minefield", "Place 3 Proximity Mines.", 100 },
			{ 5, "Demolition", "Place 5 Proximity Mines.", 155 },
		},
	},
}

QuestDefinitions.POOL = {}

for _, family in ipairs(FAMILIES) do
	for _, tier in ipairs(family.tiers) do
		local goal, title, description, reward = tier[1], tier[2], tier[3], tier[4]
		local id = family.type .. goal
		QuestDefinitions[id] = {
			Id = id,
			Title = title,
			Description = description,
			Goal = goal,
			RewardCoins = reward,
			Type = family.type,
		}
		table.insert(QuestDefinitions.POOL, id)
	end
end

local UNUSED_ORIGINAL = {
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
	},
}

QuestDefinitions.DAILY_COUNT = 3

-- Legacy alias used by older UI; prefer pickForDay / payload.order
QuestDefinitions.ORDER = { "Survive60", "SponsorWin1", "Ability1" }

--[[
	Quest ids changed shape when the pool was rebuilt (UseAbility5 -> Ability5,
	SponsorWinner -> SponsorWin1, and so on). A player who already had a day's
	quests saved is holding the old ids, so map them forward rather than letting
	them resolve to nothing and disappear from the list.

	Only the four that actually changed need an entry; the rest kept their names.
]]
QuestDefinitions.LEGACY_ALIASES = {
	SponsorWinner = "SponsorWin1",
	UseAbility = "Ability1",
	UseAbility3 = "Ability3",
	UseAbility5 = "Ability5",
}

-- Returns the current id for a possibly-old quest id, or nil if it is gone.
function QuestDefinitions.resolveId(questId)
	if type(questId) ~= "string" then
		return nil
	end
	if QuestDefinitions[questId] and type(QuestDefinitions[questId]) == "table" then
		return questId
	end
	local aliased = QuestDefinitions.LEGACY_ALIASES[questId]
	if aliased and QuestDefinitions[aliased] then
		return aliased
	end
	return nil
end

function QuestDefinitions.get(questId)
	local def = QuestDefinitions[questId]
	if type(def) == "table" and def.Goal then
		return def
	end
	return nil
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
