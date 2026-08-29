--[[
	Achievement ladder.

	Built as tiers per stat rather than a flat list, so the Trophy tab is
	something to grind at rather than seven one-offs that are all done in an
	afternoon. Rewards scale with the goal.

	Every Stat used here must be readable by AchievementService.readStat.
	Adding a tier is a one-line change; adding a stat needs a readStat case.
]]
local AchievementDefinitions = {}

local LADDERS = {
	{
		stat = "wins",
		prefix = "Wins",
		tiers = {
			{ 1, "First Victory", "Win your first match.", 100 },
			{ 5, "Getting Good", "Win 5 matches.", 175 },
			{ 10, "Champion", "Win 10 matches.", 250 },
			{ 25, "Contender", "Win 25 matches.", 450 },
			{ 50, "Grid Legend", "Win 50 matches.", 750 },
			{ 100, "Centurion", "Win 100 matches.", 1400 },
			{ 250, "Unstoppable", "Win 250 matches.", 3000 },
			{ 500, "Grid Immortal", "Win 500 matches.", 6000 },
		},
	},
	{
		stat = "kills",
		prefix = "Kills",
		tiers = {
			{ 1, "First Blood", "Get your first elimination.", 75 },
			{ 10, "Brawler", "Eliminate 10 players.", 150 },
			{ 25, "Arena Slayer", "Eliminate 25 players.", 300 },
			{ 100, "Executioner", "Eliminate 100 players.", 700 },
			{ 250, "Menace", "Eliminate 250 players.", 1500 },
			{ 500, "Nightmare", "Eliminate 500 players.", 3000 },
			{ 1000, "Grid Reaper", "Eliminate 1,000 players.", 6500 },
		},
	},
	{
		stat = "fans",
		prefix = "Fans",
		tiers = {
			{ 10, "Fan Favorite", "Collect 10 fans.", 150 },
			{ 50, "Superstar", "Collect 50 fans.", 500 },
			{ 150, "Headliner", "Collect 150 fans.", 1100 },
			{ 500, "Icon", "Collect 500 fans.", 2600 },
			{ 1500, "Living Legend", "Collect 1,500 fans.", 6000 },
		},
	},
	{
		stat = "streak",
		prefix = "Streak",
		tiers = {
			{ 3, "On A Roll", "Win 3 matches in a row.", 200 },
			{ 5, "Hot Streak", "Win 5 matches in a row.", 400 },
			{ 10, "Untouchable", "Win 10 matches in a row.", 1000 },
			{ 20, "Flawless", "Win 20 matches in a row.", 2500 },
		},
	},
	{
		stat = "level",
		prefix = "Level",
		tiers = {
			{ 5, "Rookie", "Reach level 5.", 150 },
			{ 10, "Regular", "Reach level 10.", 300 },
			{ 25, "Veteran", "Reach level 25.", 700 },
			{ 50, "Elite", "Reach level 50.", 1600 },
			{ 75, "Master", "Reach level 75.", 3000 },
			{ 100, "Grandmaster", "Reach level 100.", 6000 },
		},
	},
	{
		stat = "matches",
		prefix = "Matches",
		tiers = {
			{ 10, "Warming Up", "Play 10 matches.", 100 },
			{ 50, "Committed", "Play 50 matches.", 300 },
			{ 200, "Grid Regular", "Play 200 matches.", 900 },
			{ 500, "Dedicated", "Play 500 matches.", 2000 },
			{ 1000, "Lifer", "Play 1,000 matches.", 4500 },
		},
	},
	{
		stat = "coins",
		prefix = "Coins",
		tiers = {
			{ 1000, "Pocket Change", "Hold 1,000 coins.", 100 },
			{ 10000, "Well Off", "Hold 10,000 coins.", 400 },
			{ 100000, "Rich", "Hold 100,000 coins.", 1500 },
			{ 1000000, "Millionaire", "Hold 1,000,000 coins.", 5000 },
		},
	},
}

AchievementDefinitions.ORDER = {}

for _, ladder in ipairs(LADDERS) do
	for _, tier in ipairs(ladder.tiers) do
		local goal, title, description, reward = tier[1], tier[2], tier[3], tier[4]
		local id = ladder.prefix .. "_" .. goal
		AchievementDefinitions[id] = {
			Id = id,
			Title = title,
			Description = description,
			Stat = ladder.stat,
			Goal = goal,
			RewardCoins = reward,
		}
		table.insert(AchievementDefinitions.ORDER, id)
	end
end

--[[
	The original seven ids are kept as aliases pointing at the same goals, so
	anyone who already claimed them keeps that claim rather than being handed a
	duplicate reward under a new id.
]]
local LEGACY_ALIASES = {
	FirstWin = "Wins_1",
	WinStreak10 = "Wins_10",
	WinStreak50 = "Wins_50",
	FirstBlood = "Kills_1",
	Slayer25 = "Kills_25",
	FanFavorite = "Fans_10",
	Superstar = "Fans_50",
}

AchievementDefinitions.LEGACY_ALIASES = LEGACY_ALIASES

local UNUSED_ORIGINAL = {
	FirstWin = {
		Id = "FirstWin",
	},
}

function AchievementDefinitions.get(id)
	return AchievementDefinitions[id]
end

return AchievementDefinitions