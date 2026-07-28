local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local killFeedEvent = ReplicatedStorage:WaitForChild("KillFeedEvent")

local ATTRIBUTION_WINDOW = 12
local lastHitBy = {}
local pendingCause = {}
local reported = {}

local KillFeedService = {}

function KillFeedService.attributeHit(victim, killer)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then return end
	if typeof(killer) ~= "Instance" or not killer:IsA("Player") then return end
	if victim == killer then return end
	lastHitBy[victim] = { killer = killer, time = os.clock() }
	pendingCause[victim] = nil
end

function KillFeedService.setPendingCause(victim, cause)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then return end
	pendingCause[victim] = cause
end

local function getAttributedKiller(victim)
	local data = lastHitBy[victim]
	if data and os.clock() - data.time <= ATTRIBUTION_WINDOW then
		return data.killer
	end
	return nil
end

function KillFeedService.markHazardKill(victim)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then return end
	if not getAttributedKiller(victim) then
		pendingCause[victim] = "hazard"
	end
end

function KillFeedService.reportElimination(victim, forcedKiller)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") then return end
	if reported[victim] then return end
	reported[victim] = true

	local killer = nil
	if typeof(forcedKiller) == "Instance" and forcedKiller:IsA("Player") then
		killer = forcedKiller
	else
		killer = getAttributedKiller(victim)
	end

	if killer and killer ~= victim then
		pcall(function()
			local PlayerStatsService = require(game:GetService("ServerScriptService"):WaitForChild("PlayerStatsService"))
			PlayerStatsService.addKill(killer)
			killer:SetAttribute("StatKills", killer:FindFirstChild("TotalKills") and killer.TotalKills.Value or 0)
		end)
	end

	killFeedEvent:FireAllClients(victim.DisplayName, killer and killer.DisplayName or nil)
	lastHitBy[victim] = nil
	pendingCause[victim] = nil

	task.delay(2, function()
		reported[victim] = nil
	end)
end

function KillFeedService.reportEnvironmentElimination(victim)
	KillFeedService.reportElimination(victim, nil)
end

Players.PlayerRemoving:Connect(function(player)
	lastHitBy[player] = nil
	pendingCause[player] = nil
	reported[player] = nil
end)

return KillFeedService