local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStatsService = require(script.Parent:WaitForChild("PlayerStatsService"))
require(script.Parent:WaitForChild("AchievementService"))

local leaderboardRefreshEvent = ServerStorage:FindFirstChild("LeaderboardRefresh")
if not leaderboardRefreshEvent then
	leaderboardRefreshEvent = Instance.new("BindableEvent")
	leaderboardRefreshEvent.Name = "LeaderboardRefresh"
	leaderboardRefreshEvent.Parent = ServerStorage
end

local leaderboardDataEvent = ReplicatedStorage:WaitForChild("LeaderboardDataEvent")

local BOARDS = {
	Wins = workspace:WaitForChild("WinsLeaderboards"):WaitForChild("SurfaceGui"),
	Fans = workspace:WaitForChild("FansLeaderboards"):WaitForChild("SurfaceGui"),
	Kills = workspace:WaitForChild("KillsLeaderboards"):WaitForChild("SurfaceGui"),
}

local CONTAINER_NAMES = {
	Wins = "WinsContainer",
	Fans = "FansContainer",
	Kills = "KillsContainer",
}

local VALUE_LABEL_NAMES = {
	Wins = "WinCount",
	Fans = "FansCount",
	Kills = "KillCount",
}
local PODIUMS = {
	Wins = workspace:WaitForChild("WinsPodium"),
	Fans = workspace:WaitForChild("FansPodium"),
	Kills = workspace:WaitForChild("KillsPodium"),
}

local PODIUM_DISPLAY_FOLDER_NAME = "PodiumDisplays"
-- Cache top-1 userIds so we only rebuild avatars when the leader changes.
local podiumLeaderUserIds = {
	Wins = nil,
	Fans = nil,
	Kills = nil,
}

local function getDisplayFolder()
	local folder = workspace:FindFirstChild(PODIUM_DISPLAY_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PODIUM_DISPLAY_FOLDER_NAME
		folder.Parent = workspace
	end
	return folder
end

local function clearPodiumAvatar(podium)
	local folder = workspace:FindFirstChild(PODIUM_DISPLAY_FOLDER_NAME)
	if folder then
		local existing = folder:FindFirstChild(podium.Name .. "_Avatar")
		if existing then existing:Destroy() end
	end
	local legacy = podium:FindFirstChild("LeaderAvatar")
	if legacy then legacy:Destroy() end
end

local function getPodiumTopPosition(podium)
	return (podium.CFrame * CFrame.new(0, podium.Size.Y / 2, 0)).Position
end

local function prepareDisplayCharacter(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.AutoRotate = false
		-- Static for now. Keep Animator intact so idle/victory anims can be added later.
		humanoid.PlatformStand = true
	end

	-- Disable default Animate so it doesn't fight a future custom podium track.
	local animate = model:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Disabled = true
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		end
	end
end

local function placeModelOnPodium(model, podium, lookTarget)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root then return end

	prepareDisplayCharacter(model)

	local topPos = getPodiumTopPosition(podium)
	model:PivotTo(CFrame.new(topPos))

	local bboxCF, bboxSize = model:GetBoundingBox()
	local bottomY = bboxCF.Position.Y - (bboxSize.Y / 2)
	local rootOffset = root.Position.Y - bottomY
	local standPos = Vector3.new(topPos.X, topPos.Y + rootOffset, topPos.Z)
	local facePos = Vector3.new(lookTarget.X, standPos.Y, lookTarget.Z)

	model:PivotTo(CFrame.lookAt(standPos, facePos))
	root.Anchored = true
end

local function renderPodiumAvatar(boardKey, podium, userId)
	if podiumLeaderUserIds[boardKey] == userId then
		-- Same leader already displayed; skip expensive avatar rebuild.
		local folder = workspace:FindFirstChild(PODIUM_DISPLAY_FOLDER_NAME)
		local existing = folder and folder:FindFirstChild(podium.Name .. "_Avatar")
		if existing then
			return
		end
	end

	clearPodiumAvatar(podium)
	podiumLeaderUserIds[boardKey] = userId
	if not userId then
		return
	end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then
		podiumLeaderUserIds[boardKey] = nil
		return
	end

	model.Name = podium.Name .. "_Avatar"
	model:SetAttribute("DisplayUserId", userId)

	local lobbySpawn = workspace:FindFirstChild("LobbySpawn")
	local lookTarget = lobbySpawn and lobbySpawn.Position or (podium.Position + podium.CFrame.LookVector * 10)

	placeModelOnPodium(model, podium, lookTarget)
	model.Parent = getDisplayFolder()
end

local function refreshPodiums(top)
	top = top or PlayerStatsService.getAllTop(1)
	renderPodiumAvatar("Wins", PODIUMS.Wins, top.Wins[1] and top.Wins[1].userId)
	renderPodiumAvatar("Fans", PODIUMS.Fans, top.Fans[1] and top.Fans[1].userId)
	renderPodiumAvatar("Kills", PODIUMS.Kills, top.Kills[1] and top.Kills[1].userId)
end


local nameCache = {}

local function getDisplayName(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	name = ok and name or ("Player " .. userId)
	nameCache[userId] = name
	return name
end

--[[
	Resolve a batch of names concurrently and wait for the lot.

	GetNameFromUserIdAsync is a web call. Looking up three boards of ten one
	after another meant up to thirty round trips in series on a cold cache,
	which is why the boards took so long to come back. Fired together they cost
	roughly one round trip in total.
]]
local function warmNames(userIds)
	local pending = 0
	local done = false
	for _, userId in ipairs(userIds) do
		if not nameCache[userId] then
			pending += 1
			task.spawn(function()
				getDisplayName(userId)
				pending -= 1
				if pending <= 0 then
					done = true
				end
			end)
		end
	end
	if pending == 0 then
		return
	end
	local deadline = os.clock() + 5
	while not done and os.clock() < deadline do
		task.wait(0.05)
	end
end

local function clearList(list)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Template" and not child:IsA("UILayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function renderBoard(boardKey, entries)
	local surface = BOARDS[boardKey]
	local containerName = CONTAINER_NAMES[boardKey]
	local valueLabelName = VALUE_LABEL_NAMES[boardKey]
	local container = surface:FindFirstChild(containerName)
	if not container then return end
	local list = container:FindFirstChild("PlayerList")
	local template = list and list:FindFirstChild("Template")
	if not list or not template then return end
	template.Visible = false

	--[[
		These lists ship with CanvasSize (0,0) and AutomaticCanvasSize off, so the
		canvas had no height and the boards could not be scrolled at all - any row
		past the visible area was simply unreachable. Let the layout drive it.
	]]
	if list:IsA("ScrollingFrame") then
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.CanvasSize = UDim2.new()
		list.ScrollingDirection = Enum.ScrollingDirection.Y
		list.ScrollingEnabled = true
	end

	clearList(list)
	for _, entry in ipairs(entries) do
		local row = template:Clone()
		row.Name = "Row_" .. entry.rank
		row.Visible = true
		row.LayoutOrder = entry.rank
		local rankLabel = row:FindFirstChild("Rank")
		local nameLabel = row:FindFirstChild("PlayerName")
		local valueLabel = row:FindFirstChild(valueLabelName)
		local avatar = row:FindFirstChild("Avatar")
		if rankLabel then rankLabel.Text = "#" .. entry.rank end
		if nameLabel then nameLabel.Text = getDisplayName(entry.userId) end
		if valueLabel then valueLabel.Text = tostring(entry.value) end
		if avatar and avatar:IsA("ImageLabel") then
			avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. entry.userId .. "&w=48&h=48"
		end
		row.Parent = list
	end
end

--[[
	Refreshes are serialised. A round ending while a previous refresh is still
	waiting on DataStore reads used to start a second one on top of it, so the
	boards could be rebuilt twice and the podium avatars torn down mid-build.
]]
local refreshBusy = false
local refreshQueued = false

--[[
	Ten rows filled the board exactly, so the canvas matched the window and
	there was nothing to scroll. Twenty-five gives the list somewhere to go and
	makes the ladder worth climbing past tenth.
]]
local BOARD_ROWS = 25

--[[
	One shared read of the sorted boards.

	Every client that opened the leaderboard UI used to trigger its own
	getAllTop - three GetSortedAsync calls each - on top of the three the world
	boards do at the end of every match. That is what filled the DataStore
	queue ("request was added to queue" in the log) and made the boards take an
	age to come back: the calls were not slow, they were waiting in line.

	The standings only move when a match ends, so one read is cached and shared.
	The match-end refresh clears it first so the boards are never stale where it
	matters.
]]
local TOP_CACHE_SECONDS = 30
local cachedTop = nil
local cachedTopAt = 0
local cachedTopRows = 0
local topFetchBusy = false

local function getTop(rows)
	if cachedTop and cachedTopRows >= rows and (os.clock() - cachedTopAt) < TOP_CACHE_SECONDS then
		return cachedTop
	end

	-- A fetch already in flight: wait for it instead of starting a second one.
	if topFetchBusy then
		local deadline = os.clock() + 10
		while topFetchBusy and os.clock() < deadline do
			task.wait(0.1)
		end
		if cachedTop and cachedTopRows >= rows then
			return cachedTop
		end
	end

	topFetchBusy = true
	local ok, result = pcall(PlayerStatsService.getAllTop, rows)
	topFetchBusy = false

	if ok and type(result) == "table" then
		cachedTop = result
		cachedTopAt = os.clock()
		cachedTopRows = rows
		return result
	end

	-- A stale board beats an empty one.
	return cachedTop
end

local function invalidateTop()
	cachedTopAt = 0
end

local function doRefreshBoards()
	-- This runs off the match-end event, so take a genuinely fresh read.
	invalidateTop()
	local top = getTop(BOARD_ROWS)
	if not top then
		return
	end

	-- Resolve every name on all three boards in one concurrent batch before
	-- rendering, rather than one blocking call per row.
	local ids = {}
	for _, board in pairs(top) do
		for _, entry in ipairs(board) do
			table.insert(ids, entry.userId)
		end
	end
	warmNames(ids)

	renderBoard("Wins", top.Wins)
	renderBoard("Fans", top.Fans)
	renderBoard("Kills", top.Kills)
	refreshPodiums({
		Wins = { top.Wins[1] },
		Fans = { top.Fans[1] },
		Kills = { top.Kills[1] },
	})
end

local function refreshBoards()
	if refreshBusy then
		refreshQueued = true
		return
	end
	refreshBusy = true
	task.spawn(function()
		repeat
			refreshQueued = false
			local ok, err = pcall(doRefreshBoards)
			if not ok then
				warn("[Leaderboards] refresh failed:", err)
			end
		until not refreshQueued
		refreshBusy = false
	end)
end

local function buildClientPayload()
	local payload = getTop(BOARD_ROWS)
	if not payload then
		return {}
	end
	-- Same concurrency fix: 75 sequential name lookups made this request feel
	-- like the board had hung.
	local ids = {}
	for _, entries in pairs(payload) do
		for _, entry in ipairs(entries) do
			table.insert(ids, entry.userId)
		end
	end
	warmNames(ids)
	for _, entries in pairs(payload) do
		for _, entry in ipairs(entries) do
			entry.name = getDisplayName(entry.userId)
		end
	end
	return payload
end

leaderboardDataEvent.OnServerEvent:Connect(function(player)
	leaderboardDataEvent:FireClient(player, buildClientPayload())
end)

Players.PlayerAdded:Connect(function(player)
	local stats = PlayerStatsService.getSnapshot(player)
	player:SetAttribute("StatWins", stats.wins)
	player:SetAttribute("StatKills", stats.kills)
end)

for _, player in ipairs(Players:GetPlayers()) do
	local stats = PlayerStatsService.getSnapshot(player)
	player:SetAttribute("StatWins", stats.wins)
	player:SetAttribute("StatKills", stats.kills)
end


--[[
	Stats only move when a match ends, so the boards are driven by that event
	(fired by HazardSpawner during the payout step). The poll below is just a
	safety net for players joining mid-session - it used to run every 30s, which
	rebuilt podium avatar models at arbitrary moments, including mid-match.
]]
local SAFETY_POLL_SECONDS = 180

leaderboardRefreshEvent.Event:Connect(refreshBoards)
refreshBoards()
while true do
	task.wait(SAFETY_POLL_SECONDS)
	refreshBoards()
end
