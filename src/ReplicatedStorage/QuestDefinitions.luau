local QuestDefinitions = {
	Survive60 = {
		Id = "Survive60",
		Title = "Survive 60 Seconds",
		Description = "Stay alive for at least 60 seconds in one match.",
		Goal = 60,
		RewardCoins = 75,
	},
	SponsorWinner = {
		Id = "SponsorWinner",
		Title = "Back a Winner",
		Description = "Sponsor a player who wins the round.",
		Goal = 1,
		RewardCoins = 100,
	},
	UseAbility = {
		Id = "UseAbility",
		Title = "Use Your Ability",
		Description = "Activate your equipped ability during a match.",
		Goal = 1,
		RewardCoins = 50,
	},
}

QuestDefinitions.ORDER = { "Survive60", "SponsorWinner", "UseAbility" }

function QuestDefinitions.get(questId)
	return QuestDefinitions[questId]
end

return QuestDefinitions
