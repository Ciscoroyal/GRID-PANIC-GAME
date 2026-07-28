local AchievementDefinitions = {
	FirstWin = {
		Id = "FirstWin",
		Title = "First Victory",
		Description = "Win your first match.",
		Stat = "wins",
		Goal = 1,
		RewardCoins = 100,
	},
	WinStreak10 = {
		Id = "WinStreak10",
		Title = "Champion",
		Description = "Reach 10 total wins.",
		Stat = "wins",
		Goal = 10,
		RewardCoins = 250,
	},
	WinStreak50 = {
		Id = "WinStreak50",
		Title = "Grid Legend",
		Description = "Reach 50 total wins.",
		Stat = "wins",
		Goal = 50,
		RewardCoins = 750,
	},
	FirstBlood = {
		Id = "FirstBlood",
		Title = "First Blood",
		Description = "Get your first elimination.",
		Stat = "kills",
		Goal = 1,
		RewardCoins = 75,
	},
	Slayer25 = {
		Id = "Slayer25",
		Title = "Arena Slayer",
		Description = "Reach 25 total eliminations.",
		Stat = "kills",
		Goal = 25,
		RewardCoins = 300,
	},
	FanFavorite = {
		Id = "FanFavorite",
		Title = "Fan Favorite",
		Description = "Collect 10 all-time fans.",
		Stat = "fans",
		Goal = 10,
		RewardCoins = 150,
	},
	Superstar = {
		Id = "Superstar",
		Title = "Superstar",
		Description = "Collect 50 all-time fans.",
		Stat = "fans",
		Goal = 50,
		RewardCoins = 500,
	},
}

AchievementDefinitions.ORDER = {
	"FirstWin", "WinStreak10", "WinStreak50",
	"FirstBlood", "Slayer25",
	"FanFavorite", "Superstar",
}

function AchievementDefinitions.get(id)
	return AchievementDefinitions[id]
end

return AchievementDefinitions