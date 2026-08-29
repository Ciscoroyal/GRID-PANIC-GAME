--[[
	The single status line at the top of the screen. Everything the player needs
	to know about round state is said here, in this priority order:

		PRACTICE            - while in the practice arena
		<NAME> WINS         - from the end of a match until the next intermission
		8 LEFT / 3v2        - during a live match (player count, never the clock)
		MATCH STARTING      - the roll call window before the first hazard
		MATCH START IN 0:12 - intermission countdown
		WAITING FOR PLAYERS - nothing running
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

local localPlayer = Players.LocalPlayer
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local aliveStatusValue = ReplicatedStorage:WaitForChild("AliveStatus")
local currentGameMode = ReplicatedStorage:WaitForChild("CurrentGameMode")
local matchResultsEvent = ReplicatedStorage:WaitForChild("MatchResultsEvent")

local label = script.Parent:WaitForChild("StatusLabel")

local DEFAULT_COLOR = Color3.new(1, 1, 1)
local URGENCY_COLOR = Color3.fromRGB(255, 90, 90)
local WINNER_COLOR = Color3.fromRGB(255, 210, 90)
local DRAW_COLOR = Color3.fromRGB(200, 200, 200)

-- Team wins are announced in that team's colour.
local TEAM_COLORS = {
	Blue = Color3.fromRGB(80, 160, 255),
	Red = Color3.fromRGB(255, 80, 80),
	Juggernaut = Color3.fromRGB(255, 200, 60),
	Survivors = Color3.fromRGB(150, 230, 150),
}

-- Player count turns red once the hazard curve peaks, same cue as before.
local CORE_DIFFICULTY_TIME = 95

-- Safety net so a missed intermission tick can never strand the winner text.
local WINNER_MAX_SECONDS = 25

local winnerText = nil
local winnerColor = WINNER_COLOR
local winnerShownAt = 0
local lastSurvivalTime = survivalTimeValue.Value

-- "MATCH STARTING" belongs to the roll call window only. Once the count has
-- appeared, an empty count means the round just ended (everyone is out), and
-- the last count is held until the winner line replaces it.
local matchStarted = false
local lastCountText = nil

local function clearWinner()
	winnerText = nil
end

--[[
	The clock over the last few seconds of intermission, before everyone is
	teleported into the arena.

	The asset can reasonably be either a single tick or a whole ticking phrase
	covering the countdown, so the mode is decided from its actual length once
	it has loaded: a long clip plays once at 0:05, a short one ticks per second.
	If the length is still unknown we assume a clip, because guessing wrong that
	way costs one quiet tick rather than five overlapping copies.
]]
local COUNTDOWN_FROM = 5
local LONG_CLIP_SECONDS = 2

local clockIsClip = true
local clockSound = nil

task.spawn(function()
	local template = Audio.get("CountdownClock")
	if not template then
		return
	end
	pcall(function()
		ContentProvider:PreloadAsync({ template })
	end)
	if template.TimeLength > 0 then
		clockIsClip = template.TimeLength >= LONG_CLIP_SECONDS
	end
end)

local function stopClock()
	if clockSound then
		clockSound:Stop()
		clockSound:Destroy()
		clockSound = nil
	end
end

local function updateCountdownClock(newTime, previousTime)
	-- SurvivalTime counts UP during a match and DOWN during intermission, so the
	-- clock is gated on there being no live mode.
	if currentGameMode.Value ~= "" or localPlayer:GetAttribute("InPractice") == true then
		stopClock()
		return
	end
	if newTime >= previousTime then
		return
	end
	if newTime < 1 then
		stopClock()
		return
	end
	if newTime > COUNTDOWN_FROM then
		return
	end

	if clockIsClip then
		if newTime == COUNTDOWN_FROM and not clockSound then
			clockSound = Audio.play("CountdownClock")
		end
	else
		-- Rising slightly each second so the last tick feels like the last tick.
		Audio.play("CountdownClock", { pitch = 1 + ((COUNTDOWN_FROM - newTime) * 0.05) })
	end
end

local function formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- === urgency pulse (carried over from the old alive counter) ===
local pulseToken = 0
local pulsing = false

local function stopPulse()
	pulseToken += 1
	pulsing = false
end

local function startUrgencyPulse()
	if pulsing then
		return
	end
	pulsing = true
	pulseToken += 1
	local token = pulseToken
	task.spawn(function()
		while token == pulseToken and label.Parent do
			local inTween = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextColor3 = URGENCY_COLOR })
			inTween:Play()
			inTween.Completed:Wait()
			if token ~= pulseToken then break end
			local outTween = TweenService:Create(label, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { TextColor3 = DEFAULT_COLOR })
			outTween:Play()
			outTween.Completed:Wait()
		end
		if token == pulseToken then
			pulsing = false
		end
	end)
end

local function setText(text, color, pulse)
	if label.Text ~= text then
		label.Text = text
	end
	label.Visible = text ~= ""

	if pulse then
		startUrgencyPulse()
	else
		stopPulse()
		if label.TextColor3 ~= color then
			label.TextColor3 = color
		end
	end
end

local function refresh()
	if localPlayer:GetAttribute("InPractice") == true then
		setText("PRACTICE", DEFAULT_COLOR, false)
		return
	end

	if winnerText then
		if os.clock() - winnerShownAt > WINNER_MAX_SECONDS then
			clearWinner()
		else
			setText(winnerText, winnerColor, false)
			return
		end
	end

	local modeId = currentGameMode.Value
	if typeof(modeId) == "string" and modeId ~= "" then
		-- A match is live. Player count only - the clock is deliberately hidden.
		local alive = aliveStatusValue.Value
		if typeof(alive) == "string" and alive ~= "" then
			matchStarted = true
			lastCountText = alive
			setText(alive, DEFAULT_COLOR, survivalTimeValue.Value >= CORE_DIFFICULTY_TIME)
		elseif matchStarted then
			-- Last player just died: hold the count until the winner is declared
			-- rather than flashing back to "MATCH STARTING".
			setText(lastCountText or "", DEFAULT_COLOR, false)
		else
			-- Roll call window: contestants are placed but hazards have not started.
			setText("MATCH STARTING", DEFAULT_COLOR, false)
		end
		return
	end

	local remaining = survivalTimeValue.Value
	if remaining >= 1 and remaining <= 15 then
		setText("MATCH START IN " .. formatCountdown(remaining), DEFAULT_COLOR, false)
		return
	end

	setText("WAITING FOR PLAYERS", DEFAULT_COLOR, false)
end

matchResultsEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local name = payload.winnerName
	if typeof(name) ~= "string" or name == "" then
		return
	end

	if payload.isDraw == true then
		winnerText = "DRAW"
		winnerColor = DRAW_COLOR
	elseif payload.winningTeam == "Survivors" then
		-- "SURVIVORS WINS" reads badly; everything else takes the singular.
		winnerText = "SURVIVORS WIN"
		winnerColor = TEAM_COLORS.Survivors
	else
		winnerText = string.upper(name) .. " WINS"
		winnerColor = TEAM_COLORS[payload.winningTeam] or WINNER_COLOR
	end

	--[[
		The sting is for the person who actually won - on a team win, everyone on
		the winning side. Losers get the result line and nothing else; a victory
		fanfare playing for someone who just went out reads as mockery.
	]]
	local wonIt = false
	if payload.isDraw ~= true then
		if name == localPlayer.Name then
			wonIt = true
		elseif typeof(payload.winningTeam) == "string" and payload.winningTeam ~= ""
			and localPlayer:GetAttribute("TeamId") == payload.winningTeam then
			wonIt = true
		end
	end
	if wonIt then
		Audio.play("Victory")
	end

	winnerShownAt = os.clock()
	refresh()
end)

survivalTimeValue.Changed:Connect(function(newTime)
	-- The intermission countdown is the only thing that makes this value fall,
	-- so a decrease means the next round cycle has begun: drop the winner text.
	if winnerText and newTime < lastSurvivalTime then
		clearWinner()
	end
	updateCountdownClock(newTime, lastSurvivalTime)
	lastSurvivalTime = newTime
	refresh()
end)

aliveStatusValue.Changed:Connect(refresh)
currentGameMode.Changed:Connect(function(modeId)
	-- A new match starting always clears a stale winner.
	if typeof(modeId) == "string" and modeId ~= "" then
		clearWinner()
		matchStarted = false
		lastCountText = nil
		-- The teleport has happened; the clock has done its job.
		stopClock()
	end
	refresh()
end)
localPlayer:GetAttributeChangedSignal("InPractice"):Connect(refresh)
localPlayer:GetAttributeChangedSignal("InArena"):Connect(refresh)

task.spawn(function()
	while label.Parent do
		refresh()
		task.wait(0.25)
	end
end)

refresh()
