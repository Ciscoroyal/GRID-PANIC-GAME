local Players = game:GetService("Players")

local RoundData = {
	winner = nil,
	mode = "Classic",
	contestants = {},
	teams = {},
	survivorRewards = {},
	sponsorResults = {},
	juggernaut = nil,
}

RoundData.winningTeam = nil

local JUGGERNAUT_SCALE = 1.35

local function resetCharacterScale(player)
	if not player or not player.Parent then
		return
	end
	local character = player.Character
	if character then
		pcall(function()
			character:ScaleTo(1)
		end)
	end
end

local function applyJuggernautScale(player)
	if not player or not player.Parent then
		return
	end
	local character = player.Character
	if character then
		pcall(function()
			character:ScaleTo(JUGGERNAUT_SCALE)
		end)
	end
end

function RoundData.clear()
	RoundData.clearJuggernaut()
	RoundData.winner = nil
	RoundData.winningTeam = nil
	table.clear(RoundData.contestants)
	table.clear(RoundData.teams)
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

function RoundData.setMode(modeId)
	if typeof(modeId) ~= "string" or modeId == "" then
		modeId = "Classic"
	end
	RoundData.mode = modeId
end

function RoundData.getMode()
	return RoundData.mode or "Classic"
end

function RoundData.setTeam(player, teamId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	if teamId ~= "Blue" and teamId ~= "Red" then
		RoundData.teams[player] = nil
		player:SetAttribute("TeamId", nil)
		return
	end
	RoundData.teams[player] = teamId
	player:SetAttribute("TeamId", teamId)
end

function RoundData.getTeam(player)
	if not player then
		return nil
	end
	return RoundData.teams[player] or player:GetAttribute("TeamId")
end

function RoundData.clearTeams()
	for player in pairs(RoundData.teams) do
		if player and player.Parent then
			player:SetAttribute("TeamId", nil)
		end
	end
	table.clear(RoundData.teams)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		player:SetAttribute("TeamId", nil)
	end
end

function RoundData.getTeamPlayers(teamId)
	local list = {}
	for player, team in pairs(RoundData.teams) do
		if team == teamId and player and player.Parent then
			table.insert(list, player)
		end
	end
	return list
end

function RoundData.setJuggernaut(player)
	RoundData.clearJuggernaut()
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	RoundData.juggernaut = player
	player:SetAttribute("IsJuggernaut", true)
	applyJuggernautScale(player)
end

function RoundData.getJuggernaut()
	return RoundData.juggernaut
end

function RoundData.isJuggernaut(player)
	if not player then
		return false
	end
	return RoundData.juggernaut == player or player:GetAttribute("IsJuggernaut") == true
end

function RoundData.clearJuggernaut()
	local current = RoundData.juggernaut
	if current and current.Parent then
		current:SetAttribute("IsJuggernaut", nil)
		resetCharacterScale(current)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("IsJuggernaut") == true then
			player:SetAttribute("IsJuggernaut", nil)
			resetCharacterScale(player)
		end
	end
	RoundData.juggernaut = nil
end

function RoundData.getHunterPlayers()
	local list = {}
	for player in pairs(RoundData.contestants) do
		if player and player.Parent and not RoundData.isJuggernaut(player) then
			table.insert(list, player)
		end
	end
	return list
end

return RoundData
