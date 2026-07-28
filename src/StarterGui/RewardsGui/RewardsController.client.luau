local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementDefinitions = require(ReplicatedStorage:WaitForChild("AchievementDefinitions"))

local localPlayer = Players.LocalPlayer
local rewardsGui = script.Parent
local rewardsFrame = rewardsGui:WaitForChild("REWARDS")
local toggleRewards = rewardsGui:WaitForChild("ToggleRewards")

local achievementStateEvent = ReplicatedStorage:WaitForChild("AchievementStateEvent")
local claimAchievementEvent = ReplicatedStorage:WaitForChild("ClaimAchievementEvent")

local navigate = rewardsFrame:WaitForChild("Navigate")
local closeBtn = rewardsFrame:WaitForChild("Top"):WaitForChild("Close")

local tabButtons = {
	Level = navigate:WaitForChild("Level"),
	Chest = navigate:WaitForChild("Chest"),
	Daily = navigate:WaitForChild("Daily"),
	Trophy = navigate:WaitForChild("Trophy"),
}

local tabFrames = {
	Level = rewardsFrame:WaitForChild("Level"),
	Chest = rewardsFrame:WaitForChild("Chest"),
	Daily = rewardsFrame:WaitForChild("Daily"),
	Trophy = rewardsFrame:WaitForChild("Trophy"),
}

local trophyFrame = tabFrames.Trophy
local statsLabel = trophyFrame:WaitForChild("Stats").Frame:WaitForChild("Title")
local achievementList = trophyFrame:WaitForChild("AchievementList")

local currentTab = "Daily"
local latestAchievements = nil
local achievementRows = {}

local STYLE = {
	ACCENT = Color3.fromRGB(0, 170, 85),
	GOLD = Color3.fromRGB(255, 200, 50),
	MUTED = Color3.fromRGB(90, 92, 105),
}

local function setTabHighlight(tabName)
	for name, button in pairs(tabButtons) do
		local frame = button:FindFirstChild("Frame")
		if frame then
			frame.BackgroundTransparency = name == tabName and 0 or 0.35
		end
	end
end

local function updatePersonalStats()
	local wins = localPlayer:GetAttribute("StatWins")
		or (localPlayer:FindFirstChild("TotalWins") and localPlayer.TotalWins.Value)
		or 0
	local kills = localPlayer:GetAttribute("StatKills")
		or (localPlayer:FindFirstChild("TotalKills") and localPlayer.TotalKills.Value)
		or 0
	local fans = localPlayer:FindFirstChild("AllTimeFans") and localPlayer.AllTimeFans.Value or 0
	statsLabel.Text = string.format("Wins: %d\nKills: %d\nFans: %d", wins, kills, fans)
end

local function updateClaimButton(row, achievement)
	local claimBtn = row:FindFirstChild("Play")
	if not claimBtn then return end

	local title = claimBtn:FindFirstChild("Title", true)
	if achievement.claimed then
		if title and title:IsA("TextLabel") then title.Text = "DONE" end
		claimBtn.BackgroundColor3 = STYLE.MUTED
		claimBtn.Active = false
	elseif achievement.complete then
		if title and title:IsA("TextLabel") then title.Text = "CLAIM" end
		claimBtn.BackgroundColor3 = STYLE.GOLD
		claimBtn.Active = true
	else
		if title and title:IsA("TextLabel") then title.Text = tostring(achievement.rewardCoins) end
		claimBtn.BackgroundColor3 = STYLE.ACCENT
		claimBtn.Active = false
	end
end

local function renderAchievement(achievementId, achievement)
	local row = achievementRows[achievementId]
	if not row or not achievement then return end

	local title = row:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = string.format("%s  (%d/%d)", achievement.title, math.floor(achievement.progress), achievement.goal)
	end
	updateClaimButton(row, achievement)
end

local function renderAllAchievements(payload)
	latestAchievements = payload
	if not payload or not payload.achievements then return end
	for achievementId, achievement in pairs(payload.achievements) do
		renderAchievement(achievementId, achievement)
	end
end

local function buildAchievementRows()
	local template = achievementList:FindFirstChild("AchievementItem")
	if not template then return end

	for _, achievementId in ipairs(AchievementDefinitions.ORDER) do
		local row = template:Clone()
		row.Name = achievementId
		row.Visible = true
		row.LayoutOrder = table.find(AchievementDefinitions.ORDER, achievementId) or 0
		row.Parent = achievementList

		local claimBtn = row:FindFirstChild("Play")
		if claimBtn then
			claimBtn.Activated:Connect(function()
				claimAchievementEvent:FireServer(achievementId)
			end)
		end

		achievementRows[achievementId] = row
	end
end

local function setTab(tabName)
	if not tabFrames[tabName] then
		tabName = "Daily"
	end
	currentTab = tabName

	for name, frame in pairs(tabFrames) do
		frame.Visible = name == tabName
	end
	setTabHighlight(tabName)

	if tabName == "Trophy" then
		updatePersonalStats()
		if latestAchievements then
			renderAllAchievements(latestAchievements)
		end
	end
end

local function setRewardsVisible(isVisible, tabName)
	if localPlayer:GetAttribute("InArena") == true then
		rewardsFrame.Visible = false
		return
	end

	if tabName and tabName ~= "Close" then
		setTab(tabName)
	end

	rewardsFrame.Visible = isVisible
	if isVisible then
		rewardsFrame.Position = UDim2.new(0.5, 0, 0.56, 0)
		rewardsFrame:TweenPosition(
			UDim2.new(0.5, 0, 0.5, 0),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Back,
			0.35,
			true
		)
	end
end

buildAchievementRows()

for tabName, button in pairs(tabButtons) do
	button.Activated:Connect(function()
		setTab(tabName)
	end)
end

achievementStateEvent.OnClientEvent:Connect(function(payload)
	renderAllAchievements(payload)
	if currentTab == "Trophy" then
		updatePersonalStats()
	end
end)

localPlayer:GetAttributeChangedSignal("StatWins"):Connect(updatePersonalStats)
localPlayer:GetAttributeChangedSignal("StatKills"):Connect(updatePersonalStats)
task.spawn(function()
	local fans = localPlayer:WaitForChild("AllTimeFans", 20)
	if fans then
		fans:GetPropertyChangedSignal("Value"):Connect(updatePersonalStats)
	end
end)

closeBtn.Activated:Connect(function()
	setRewardsVisible(false)
end)

toggleRewards.Event:Connect(function(tabName)
	if tabName == "Close" then
		setRewardsVisible(false)
		return
	end
	if typeof(tabName) == "string" then
		if rewardsFrame.Visible and currentTab == tabName then
			setRewardsVisible(false)
		else
			setRewardsVisible(true, tabName)
		end
	else
		setRewardsVisible(not rewardsFrame.Visible, currentTab)
	end
end)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	if localPlayer:GetAttribute("InArena") == true then
		setRewardsVisible(false)
	end
end)

rewardsFrame.Visible = false
setTab("Daily")
updatePersonalStats()
