local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local CoinRewards = require(ReplicatedStorage:WaitForChild("CoinRewards"))
local RoundData = require(ReplicatedStorage:WaitForChild("RoundData"))
local sponsorEvent = ReplicatedStorage:WaitForChild("SponsorEvent")
local sponsorResultEvent = ReplicatedStorage:WaitForChild("SponsorResultEvent")
local matchCompleteEvent = ServerStorage:WaitForChild("MatchComplete")
local overheadTagTemplate = ServerStorage:WaitForChild("OverheadTag")

local function getPlayerLevel(player)
	local level = player:GetAttribute("PlayerLevel")
	if typeof(level) == "number" and level > 0 then
		return level
	end
	return 1
end

--[[
	During a live match the overhead tag is trimmed to the player's name only.
	Once they are eliminated (and back in the lobby) or the round ends, the full
	tag with level, fans and win streak comes back.
]]
local function isInMatch(player)
	if player:GetAttribute("InArena") ~= true then
		return false
	end
	return player:GetAttribute("IsEliminated") ~= true
end

-- The billboard is sized for the full stat stack, so with only the name left
-- the label floats well above the head. Drop the whole tag closer in that mode.
local FULL_TAG_OFFSET = overheadTagTemplate.StudsOffset
local NAME_ONLY_OFFSET = Vector3.new(FULL_TAG_OFFSET.X, 0.2, FULL_TAG_OFFSET.Z)

local function updateOverheadTag(player, tag)
	if not tag or not tag.Parent then return end
	local frame = tag:FindFirstChild("Frame")
	if not frame then return end

	local nameOnly = isInMatch(player)
	tag.StudsOffset = nameOnly and NAME_ONLY_OFFSET or FULL_TAG_OFFSET

	local nameLabel = frame:FindFirstChild("PlayerName")
	local levelLabel = frame:FindFirstChild("Level")
	local fansFrame = frame:FindFirstChild("Fans")
	local fansLabel = fansFrame and fansFrame:FindFirstChild("Fans")
	local allTimeFans = player:FindFirstChild("AllTimeFans")
	local fanCount = allTimeFans and allTimeFans.Value or 0

	if nameLabel then
		nameLabel.Text = player.DisplayName
	end
	if levelLabel then
		levelLabel.Text = "Lv." .. getPlayerLevel(player)
		levelLabel.Visible = not nameOnly
	end
	if fansLabel then
		fansLabel.Text = tostring(fanCount)
	end
	if fansFrame then
		fansFrame.Visible = not nameOnly
	end

	local streakFrame = frame:FindFirstChild("Streak")
	local streakValue = tonumber(player:GetAttribute("WinStreak")) or 0
	if streakFrame then
		streakFrame.Visible = (not nameOnly) and streakValue > 0
		local streakLabel = streakFrame:FindFirstChild("Fans")
		if streakLabel then
			streakLabel.Text = tostring(streakValue)
		end
	end
end

local function refreshPlayerOverheadTag(player)
	local character = player.Character
	if not character then return end
	local head = character:FindFirstChild("Head")
	if not head then return end
	local tag = head:FindFirstChild("OverheadTag")
	if tag then
		updateOverheadTag(player, tag)
	end
end
-- The Database to save All-Time Fans
local fanDataStore = DataStoreService:GetDataStore("AllTimeFans_V1")
-- Memory Banks
local activeSponsorships = {}
local deathConnections = {}
local sponsoredCharacterAddedConnections = {}
local SPONSOR_PAYOUT = 50

local function rejectCheer(sponsor, message)
	sponsorResultEvent:FireClient(sponsor, false, message)
end

local function acceptCheer(sponsor, targetName)
	sponsorResultEvent:FireClient(sponsor, true, targetName)
end

local LOBBY_ZONE_RADIUS = 45
local BOOTH_ZONE_RADIUS = 18

local function getFlatDistance(posA, posB)
	return (Vector3.new(posA.X, 0, posA.Z) - Vector3.new(posB.X, 0, posB.Z)).Magnitude
end

local function getArcadeBooths()
	local booths = {}
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst.Name == "Arcade Machine" and inst:IsA("BasePart") then
			table.insert(booths, inst)
		end
	end
	return booths
end

local function isNearArcadeBooth(position)
	for _, booth in ipairs(getArcadeBooths()) do
		if getFlatDistance(position, booth.Position) <= BOOTH_ZONE_RADIUS then
			return true
		end
	end
	return false
end

local function isNearLobbyZone(player)
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	if isNearArcadeBooth(root.Position) then
		return true
	end

	local lobbySpawn = workspace:FindFirstChild("LobbySpawn")
	if lobbySpawn and lobbySpawn:IsA("BasePart") then
		if getFlatDistance(root.Position, lobbySpawn.Position) <= LOBBY_ZONE_RADIUS then
			return true
		end
	end

	return false
end

local function canPlaceSponsorBet(sponsor)
	if sponsor:GetAttribute("InArena") ~= true then
		return true
	end
	if sponsor:GetAttribute("IsEliminated") == true then
		return true
	end
	return isNearLobbyZone(sponsor)
end
-- =================================================================
-- 1. LOAD DATA & ATTACH PHYSICAL TAGS
-- =================================================================
Players.PlayerAdded:Connect(function(player)
	local allTimeFans = Instance.new("IntValue")
	allTimeFans.Name = "AllTimeFans"
	allTimeFans.Parent = player
	local success, savedFans = pcall(function()
		return fanDataStore:GetAsync(player.UserId)
	end)
	if success and savedFans then
		allTimeFans.Value = savedFans
	else
		allTimeFans.Value = 0
	end
	pcall(function()
		local PlayerStatsService = require(game:GetService("ServerScriptService"):WaitForChild("PlayerStatsService"))
		PlayerStatsService.syncFans(player)
	end)
	local function attachTag(character)
		local head = character:WaitForChild("Head", 5)
		if not head then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoid.NameDisplayDistance = 0
			humanoid.HealthDisplayDistance = 0
		end

		local existing = head:FindFirstChild("OverheadTag")
		if existing then existing:Destroy() end

		local tag = overheadTagTemplate:Clone()
		tag.Name = "OverheadTag"
		tag.Adornee = head
		tag.Parent = head
		updateOverheadTag(player, tag)
	end

	allTimeFans:GetPropertyChangedSignal("Value"):Connect(function()
		refreshPlayerOverheadTag(player)
	end)

	player:GetAttributeChangedSignal("StatWins"):Connect(function()
		refreshPlayerOverheadTag(player)
	end)
	player:GetAttributeChangedSignal("StatKills"):Connect(function()
		refreshPlayerOverheadTag(player)
	end)
	player:GetAttributeChangedSignal("PlayerLevel"):Connect(function()
		refreshPlayerOverheadTag(player)
	end)

	player:GetAttributeChangedSignal("WinStreak"):Connect(function()
		refreshPlayerOverheadTag(player)
	end)

	-- Entering / leaving a match switches the tag between name-only and full.
	player:GetAttributeChangedSignal("InArena"):Connect(function()
		refreshPlayerOverheadTag(player)
	end)
	player:GetAttributeChangedSignal("IsEliminated"):Connect(function()
		refreshPlayerOverheadTag(player)
	end)

	player.CharacterAdded:Connect(attachTag)
	if player.Character then
		attachTag(player.Character)
	end
end)
Players.PlayerRemoving:Connect(function(player)
	local fans = player:FindFirstChild("AllTimeFans")
	if fans then
		pcall(function()
			fanDataStore:SetAsync(player.UserId, fans.Value)
		end)
	end
end)
-- =================================================================
-- 2. PLACING THE BET & SETTING THE DEATH TRIPWIRE
-- =================================================================
sponsorEvent.OnServerEvent:Connect(function(sponsor, sponsoredPlayer)
	if activeSponsorships[sponsor] then
		rejectCheer(sponsor, "You already cheered this round.")
		return
	end
	if typeof(sponsoredPlayer) ~= "Instance" or not sponsoredPlayer:IsA("Player") then
		rejectCheer(sponsor, "Invalid cheer target.")
		return
	end
	if sponsoredPlayer == sponsor then
		rejectCheer(sponsor, "You cannot cheer for yourself.")
		return
	end
	if not canPlaceSponsorBet(sponsor) then
		rejectCheer(sponsor, "Move to the lobby or an arcade booth to cheer.")
		return
	end
	if sponsoredPlayer:GetAttribute("InArena") ~= true then
		rejectCheer(sponsor, "That player is not in the match.")
		return
	end
	if sponsoredPlayer:GetAttribute("IsEliminated") == true then
		rejectCheer(sponsor, "That player was already eliminated.")
		return
	end
	local character = sponsoredPlayer.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		rejectCheer(sponsor, "That player is no longer alive.")
		return
	end
	activeSponsorships[sponsor] = sponsoredPlayer
	RoundData.sponsorResults[sponsor] = {
		targetUserId = sponsoredPlayer.UserId,
		targetName = sponsoredPlayer.DisplayName,
		won = nil,
		coins = 0,
		bonusCoins = 0,
	}
	acceptCheer(sponsor, sponsoredPlayer.DisplayName)
	pcall(function()
		local QuestService = require(game:GetService("ServerScriptService"):WaitForChild("QuestService"))
		QuestService.onSponsor(sponsor)
	end)
	-- The Fan Boost 
	local allTimeFans = sponsoredPlayer:FindFirstChild("AllTimeFans")
	if allTimeFans then
		allTimeFans.Value = allTimeFans.Value + 1
		pcall(function()
			local PlayerStatsService = require(game:GetService("ServerScriptService"):WaitForChild("PlayerStatsService"))
			PlayerStatsService.syncFans(sponsoredPlayer)
		end)
	end
	-- THE DEATH TRACKER
	local function setupDeathTracker(sponsor, sponsoredPlayer)
		local function connectHumanoid(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if not humanoid then return end
			if deathConnections[sponsor] then
				deathConnections[sponsor]:Disconnect()
			end
			deathConnections[sponsor] = humanoid.Died:Connect(function()
				if activeSponsorships[sponsor] ~= sponsoredPlayer then return end
				if deathConnections[sponsor] then
					deathConnections[sponsor]:Disconnect()
					deathConnections[sponsor] = nil
				end
			end)
		end
		if sponsoredPlayer.Character then
			connectHumanoid(sponsoredPlayer.Character)
		end
		if sponsoredCharacterAddedConnections[sponsor] then
			sponsoredCharacterAddedConnections[sponsor]:Disconnect()
			sponsoredCharacterAddedConnections[sponsor] = nil
		end
		sponsoredCharacterAddedConnections[sponsor] = sponsoredPlayer.CharacterAdded:Connect(function(character)
			if activeSponsorships[sponsor] == sponsoredPlayer then
				connectHumanoid(character)
			end
		end)
	end
	setupDeathTracker(sponsor, sponsoredPlayer)
end)
--- =================================================================
-- 3. THE MASTER EVALUATION (Triggers when MatchComplete fires)
-- =================================================================
matchCompleteEvent.Event:Connect(function()
	local winner = RoundData.winner

	local function applySponsorResult(sponsor, targetPlayer, existing)
		local result = existing or {}
		if targetPlayer and targetPlayer.Parent then
			result.targetUserId = targetPlayer.UserId
			result.targetName = targetPlayer.DisplayName
		end

		local targetWon = false
		if RoundData.winningTeam == "Survivors" then
			-- Cheering any hunter pays out when the juggernaut is dethroned
			targetWon = targetPlayer ~= nil
				and RoundData.didPlay(targetPlayer)
				and targetPlayer:GetAttribute("IsJuggernaut") ~= true
		elseif RoundData.winningTeam then
			local targetTeam = targetPlayer and (RoundData.getTeam(targetPlayer) or targetPlayer:GetAttribute("TeamId"))
			targetWon = targetTeam ~= nil and targetTeam == RoundData.winningTeam
		else
			targetWon = winner ~= nil and (
				targetPlayer == winner
				or (result.targetUserId and winner.UserId == result.targetUserId)
			)
		end

		if targetWon then
			local _, bonusCoins = CoinRewards.awardCoins(sponsor, SPONSOR_PAYOUT)
			result.won = true
			result.coins = SPONSOR_PAYOUT
			result.bonusCoins = bonusCoins
			pcall(function()
				local QuestService = require(game:GetService("ServerScriptService"):WaitForChild("QuestService"))
				QuestService.onSponsorWinner(sponsor)
			end)
		else
			result.won = false
			result.coins = 0
			result.bonusCoins = 0
		end

		RoundData.sponsorResults[sponsor] = result
	end

	for sponsor, targetPlayer in pairs(activeSponsorships) do
		if sponsor and sponsor.Parent and targetPlayer then
			applySponsorResult(sponsor, targetPlayer, RoundData.sponsorResults[sponsor])
		end
	end

	for sponsor, result in pairs(RoundData.sponsorResults) do
		if result.won == nil and sponsor and sponsor.Parent then
			applySponsorResult(sponsor, activeSponsorships[sponsor], result)
		end
	end
	for _, connection in pairs(sponsoredCharacterAddedConnections) do
		if connection then connection:Disconnect() end
	end
	table.clear(sponsoredCharacterAddedConnections)
	for _, connection in pairs(deathConnections) do
		if connection then connection:Disconnect() end
	end
	table.clear(deathConnections)
	table.clear(activeSponsorships)
end)