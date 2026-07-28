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
		humanoid.PlatformStand = true
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

local function renderPodiumAvatar(podium, userId)
	clearPodiumAvatar(podium)
	if not userId then return end

	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not model then return end

	model.Name = podium.Name .. "_Avatar"

	local lobbySpawn = workspace:FindFirstChild("LobbySpawn")
	local lookTarget = lobbySpawn and lobbySpawn.Position or (podium.Position + podium.CFrame.LookVector * 10)

	placeModelOnPodium(model, podium, lookTarget)
	model.Parent = getDisplayFolder()
end

local function refreshPodiums()
	local top = PlayerStatsService.getAllTop(1)
	renderPodiumAvatar(PODIUMS.Wins, top.Wins[1] and top.Wins[1].userId)
	renderPodiumAvatar(PODIUMS.Fans, top.Fans[1] and top.Fans[1].userId)
	renderPodiumAvatar(PODIUMS.Kills, top.Kills[1] and top.Kills[1].userId)
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

local function refreshBoards()
leaderboardRefreshEvent.Event:Connect(refreshBoards)
	local top = PlayerStatsService.getAllTop(10)
	renderBoard("Wins", top.Wins)
	renderBoard("Fans", top.Fans)
	renderBoard("Kills", top.Kills)
	refreshPodiums()
end

local function buildClientPayload()
	local payload = PlayerStatsService.getAllTop(25)
	for boardKey, entries in pairs(payload) do
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

refreshBoards()
while true do
	task.wait(30)
	refreshBoards()
end
