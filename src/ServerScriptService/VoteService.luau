local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeData = require(ReplicatedStorage:WaitForChild("GameModeData"))
local voteModeEvent = ReplicatedStorage:WaitForChild("VoteModeEvent")
local voteStateEvent = ReplicatedStorage:WaitForChild("VoteStateEvent")

local VoteService = {}

local active = false
local options = {} -- array of {id, displayName, description}
local votes = {} -- [player] = modeId
local counts = {} -- [modeId] = number
local winnerId = nil

local function rebuildCounts()
	table.clear(counts)
	for _, opt in ipairs(options) do
		counts[opt.id] = 0
	end
	for _, modeId in pairs(votes) do
		if counts[modeId] ~= nil then
			counts[modeId] += 1
		end
	end
end

local function isValidOption(modeId)
	for _, opt in ipairs(options) do
		if opt.id == modeId then
			return true
		end
	end
	return false
end

--[[
	The poll stays open through the whole match so players sitting in the lobby
	have the entire round to decide. The panel only pops open for people who are
	not currently fighting - contestants would rather not have it over the arena.
]]
local function shouldShowPanel(player)
	if not active then
		return false
	end
	return player:GetAttribute("InArena") ~= true
end

local function buildStateFor(player)
	return {
		visible = shouldShowPanel(player),
		options = options,
		counts = counts,
		-- Use "" instead of nil so remotes always deliver a clearable myVote
		myVote = votes[player] or "",
		winner = winnerId,
	}
end

local function broadcastState()
	rebuildCounts()
	for _, player in ipairs(Players:GetPlayers()) do
		voteStateEvent:FireClient(player, buildStateFor(player))
	end
end

function VoteService.isActive()
	return active
end

function VoteService.getWinner()
	return winnerId
end

local sessionToken = 0

--[[
	Opens a poll for the next round. Called as soon as a match starts, so it is
	live for the whole match plus the following intermission.
]]
function VoteService.open()
	sessionToken += 1
	active = true
	winnerId = nil
	table.clear(votes)
	options = GameModeData.pickVoteOptions(2)
	rebuildCounts()
	broadcastState()
end

--[[
	Resolves the poll and returns the winning mode id. Does not yield - the round
	starts immediately after - so the result panel is hidden on a spawned timer.
]]
function VoteService.close()
	if not active then
		return winnerId
	end

	rebuildCounts()

	-- Pick winner: highest votes; ties broken randomly among tied
	local best = -1
	local tied = {}
	for _, opt in ipairs(options) do
		local n = counts[opt.id] or 0
		if n > best then
			best = n
			tied = { opt.id }
		elseif n == best then
			table.insert(tied, opt.id)
		end
	end

	if #tied == 0 then
		winnerId = options[1] and options[1].id or "Classic"
	else
		winnerId = tied[math.random(1, #tied)]
	end

	active = false
	broadcastState()

	-- Brief moment to show the result, then hide - unless a new poll opened.
	local token = sessionToken
	task.spawn(function()
		task.wait(1.5)
		if token ~= sessionToken or active then
			return
		end
		for _, player in ipairs(Players:GetPlayers()) do
			voteStateEvent:FireClient(player, {
				visible = false,
				options = options,
				counts = counts,
				myVote = votes[player] or "",
				winner = winnerId,
			})
		end
	end)

	return winnerId
end

voteModeEvent.OnServerEvent:Connect(function(player, modeId)
	if not active then
		return
	end
	if typeof(modeId) ~= "string" then
		return
	end
	if not isValidOption(modeId) then
		return
	end
	votes[player] = modeId
	broadcastState()
end)

Players.PlayerRemoving:Connect(function(player)
	if votes[player] then
		votes[player] = nil
		if active then
			broadcastState()
		end
	end
end)

--[[
	The panel follows arena state in both directions: it comes up the moment a
	player returns to the lobby, and it is taken down the moment they are
	teleported into a round - including while a finished poll is still showing
	its result.
]]
local function watchArenaState(player)
	player:GetAttributeChangedSignal("InArena"):Connect(function()
		voteStateEvent:FireClient(player, buildStateFor(player))
	end)
end

Players.PlayerAdded:Connect(function(player)
	watchArenaState(player)
	if active then
		task.defer(function()
			voteStateEvent:FireClient(player, buildStateFor(player))
		end)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	watchArenaState(player)
end

return VoteService
