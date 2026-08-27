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

local function buildStateFor(player)
	return {
		visible = active,
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

--[[
	Runs a vote for `duration` seconds. Returns winning mode id.
]]
function VoteService.runVote(duration)
	duration = duration or 12
	active = true
	winnerId = nil
	table.clear(votes)
	options = GameModeData.pickVoteOptions(2)
	rebuildCounts()
	broadcastState()

	local endsAt = os.clock() + duration
	while os.clock() < endsAt do
		task.wait(0.25)
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

	-- brief moment to show result, then hide
	task.wait(1.5)
	for _, player in ipairs(Players:GetPlayers()) do
		voteStateEvent:FireClient(player, {
			visible = false,
			options = options,
			counts = counts,
			myVote = votes[player] or "",
			winner = winnerId,
		})
	end

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

Players.PlayerAdded:Connect(function(player)
	if active then
		task.defer(function()
			voteStateEvent:FireClient(player, buildStateFor(player))
		end)
	end
end)

return VoteService
