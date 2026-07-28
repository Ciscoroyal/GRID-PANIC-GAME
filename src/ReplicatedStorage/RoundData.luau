local RoundData = {
	winner = nil,
	contestants = {},
	survivorRewards = {},
	sponsorResults = {},
}

function RoundData.clear()
	RoundData.winner = nil
	table.clear(RoundData.contestants)
	table.clear(RoundData.survivorRewards)
	table.clear(RoundData.sponsorResults)
end

function RoundData.markContestant(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		RoundData.contestants[player] = true
	end
end

function RoundData.didPlay(player)
	return RoundData.contestants[player] == true
end

function RoundData.isParticipant(player)
	return RoundData.contestants[player] == true or RoundData.sponsorResults[player] ~= nil
end

return RoundData