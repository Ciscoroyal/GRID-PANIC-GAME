local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementDefinitions = require(ReplicatedStorage:WaitForChild("AchievementDefinitions"))
local LevelData = require(ReplicatedStorage:WaitForChild("LevelData"))
local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

local localPlayer = Players.LocalPlayer
local rewardsGui = script.Parent
local rewardsFrame = rewardsGui:WaitForChild("REWARDS")
local toggleRewards = rewardsGui:WaitForChild("ToggleRewards")

local achievementStateEvent = ReplicatedStorage:WaitForChild("AchievementStateEvent")
local claimAchievementEvent = ReplicatedStorage:WaitForChild("ClaimAchievementEvent")
local levelStateEvent = ReplicatedStorage:WaitForChild("LevelStateEvent")
local levelUpEvent = ReplicatedStorage:WaitForChild("LevelUpEvent")

local navigate = rewardsFrame:WaitForChild("Navigate")
local closeBtn = rewardsFrame:WaitForChild("Top"):WaitForChild("Close")

local tabButtons = {
	Level = navigate:WaitForChild("Level"),
	Chest = navigate:WaitForChild("Chest"),
	Daily = navigate:WaitForChild("Daily"),
	Trophy = navigate:WaitForChild("Trophy"),
}

local TAB_ORDER = {
	Level = 1,
	Chest = 2,
	Daily = 3,
	Trophy = 4,
}

-- Match Loadout Navigate kit (vertical + wrap, scale padding)
navigate.Size = UDim2.new(0.250015765, 0, 0.100123651, 0)
navigate.Position = UDim2.new(0.5, 0, -0.048, 0)
navigate.AnchorPoint = Vector2.new(0.5, 0.5)
navigate.BackgroundTransparency = 1
navigate.ZIndex = 0
local navLayout = navigate:FindFirstChildOfClass("UIListLayout")
if navLayout then
	navLayout.FillDirection = Enum.FillDirection.Vertical
	navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	navLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	navLayout.Padding = UDim.new(0.2, 0)
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.Wraps = true
end
for name, button in pairs(tabButtons) do
	button.LayoutOrder = TAB_ORDER[name] or 0
	button.Size = UDim2.new(0.801111817, 0, 1, 0)
	button.AnchorPoint = Vector2.new(0, 0)
	button.ZIndex = 1
end

local tabFrames = {
	Level = rewardsFrame:WaitForChild("Level"),
	Chest = rewardsFrame:WaitForChild("Chest"),
	Daily = rewardsFrame:WaitForChild("Daily"),
	Trophy = rewardsFrame:WaitForChild("Trophy"),
}

local trophyFrame = tabFrames.Trophy
local statsLabel = trophyFrame:WaitForChild("Stats").Frame:WaitForChild("Title")
local achievementList = trophyFrame:WaitForChild("AchievementList")

-- Single-column scroll; Wraps=true was shoving rows under Stats / off-screen
do
	local listLayout = achievementList:FindFirstChildOfClass("UIListLayout")
	if listLayout then
		listLayout.Wraps = false
		listLayout.FillDirection = Enum.FillDirection.Vertical
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
		listLayout.Padding = UDim.new(0, 6)
	end
	achievementList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	achievementList.CanvasSize = UDim2.new(0, 0, 0, 0)
	achievementList.ScrollingDirection = Enum.ScrollingDirection.Y
	achievementList.ClipsDescendants = true
end

local levelFrame = tabFrames.Level
local xpContainer = levelFrame:WaitForChild("XPContainer")
local levelBadge = xpContainer:WaitForChild("LevelBadge")
local levelNumberLabel = levelBadge:WaitForChild("LevelNumber")
local barWrapper = xpContainer:WaitForChild("BarWrapper")
local xpTextLabel = barWrapper:WaitForChild("XPText")
local barFill = barWrapper:WaitForChild("BarBackground"):WaitForChild("BarFill")
local milestoneList = levelFrame:WaitForChild("AllChests")
local milestoneTemplate = milestoneList:WaitForChild("LevelReward")
milestoneTemplate.Visible = false

local currentTab = "Daily"
local latestAchievements = nil
local achievementRows = {}
local milestoneRows = {}
local latestLevelSnapshot = nil
local latestMilestones = nil

local STYLE = {
	ACCENT = Color3.fromRGB(0, 170, 85),
	GOLD = Color3.fromRGB(255, 200, 50),
	MUTED = Color3.fromRGB(110, 112, 122),
	CLAIM_FACE = Color3.fromRGB(255, 200, 50),
	REWARD_FACE = Color3.fromRGB(80, 170, 255),
	DONE_FACE = Color3.fromRGB(120, 122, 132),
}

local ROW_HEIGHT = 78

local function setTabHighlight(tabName)
	for name, button in pairs(tabButtons) do
		local active = name == tabName
		-- Match Loadout Ability / Rewards Top: white face + white extruded Frame
		button.BackgroundColor3 = active and Color3.new(1, 1, 1) or Color3.fromRGB(76, 78, 99)
		local frame = button:FindFirstChild("Frame")
		if frame then
			frame.BackgroundColor3 = Color3.new(1, 1, 1)
			frame.BackgroundTransparency = active and 0 or 0.35
		end
	end
end

local function setLabelTreeText(label, text)
	if not label or not label:IsA("TextLabel") then
		return
	end
	label.Text = text
	local inner = label:FindFirstChild("Title")
	if inner and inner:IsA("TextLabel") then
		inner.Text = text
	end
end

local function formatXP(n)
	n = math.floor(tonumber(n) or 0)
	local formatted = tostring(n)
	while true do
		local updated, count = string.gsub(formatted, "^(%-?%d+)(%d%d%d)", "%1,%2")
		formatted = updated
		if count == 0 then
			break
		end
	end
	return formatted
end

local function updatePersonalStats()
	local wins = localPlayer:GetAttribute("StatWins")
		or (localPlayer:FindFirstChild("TotalWins") and localPlayer.TotalWins.Value)
		or 0
	local kills = localPlayer:GetAttribute("StatKills")
		or (localPlayer:FindFirstChild("TotalKills") and localPlayer.TotalKills.Value)
		or 0
	local fans = localPlayer:FindFirstChild("AllTimeFans") and localPlayer.AllTimeFans.Value or 0
	local level = localPlayer:GetAttribute("PlayerLevel") or 1
	statsLabel.Text = string.format("Level: %d\nWins: %d\nKills: %d\nFans: %d", level, wins, kills, fans)
end

local function updateLevelHeader(snapshot)
	if not snapshot then
		return
	end
	latestLevelSnapshot = snapshot
	levelNumberLabel.Text = tostring(snapshot.level)
	if snapshot.isMax then
		xpTextLabel.Text = string.format("%s XP (MAX LEVEL)", formatXP(snapshot.totalXP))
		barFill.Size = UDim2.new(1, 0, 1, 0)
	else
		xpTextLabel.Text = string.format(
			"%s / %s XP (Next Level)",
			formatXP(snapshot.xpIntoLevel),
			formatXP(snapshot.xpForNext)
		)
		barFill.Size = UDim2.new(math.clamp(snapshot.progress or 0, 0, 1), 0, 1, 0)
	end
end

local function updateMilestoneRow(row, milestone)
	local inner = row:FindFirstChild("Frame")
	if not inner then
		return
	end

	local levelHeader = inner:FindFirstChild("LevelHeader")
	if levelHeader then
		setLabelTreeText(levelHeader, "LEVEL")
	end

	local levelNumber = inner:FindFirstChild("LevelNumber")
	if levelNumber then
		setLabelTreeText(levelNumber, tostring(milestone.level))
	end

	local rewardText = inner:FindFirstChild("RewardText")
	if rewardText then
		local text = milestone.cosmetic
			and string.format("%d COINS + %s", milestone.coins, milestone.cosmetic)
			or string.format("%d COINS", milestone.coins)
		setLabelTreeText(rewardText, text)
	end

	local lock = inner:FindFirstChild("Lock")
	if lock then
		lock.Visible = not milestone.unlocked
	end

	local claim = inner:FindFirstChild("Claim")
	if claim then
		claim.Active = false
		pcall(function()
			claim.Interactable = false
		end)
		if milestone.unlocked then
			setLabelTreeText(claim:FindFirstChild("Title"), "OWNED")
			claim.BackgroundColor3 = STYLE.MUTED
		else
			setLabelTreeText(claim:FindFirstChild("Title"), "LOCKED")
			claim.BackgroundColor3 = STYLE.ACCENT
		end
	end
end

local function renderMilestones(milestones)
	latestMilestones = milestones
	if not milestones then
		return
	end

	for _, row in pairs(milestoneRows) do
		row:Destroy()
	end
	milestoneRows = {}

	for index, milestone in ipairs(milestones) do
		local row = milestoneTemplate:Clone()
		row.Name = "Milestone_" .. milestone.level
		row.Visible = true
		row.LayoutOrder = index
		-- Size is driven by UIGridLayout CellSize
		row.Size = UDim2.new(0.46, 0, 0, 150)
		row.Parent = milestoneList
		updateMilestoneRow(row, milestone)
		milestoneRows[milestone.level] = row
	end
end

local function styleAchievementTitle(title)
	if not title or not title:IsA("TextLabel") then
		return
	end
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.TextStrokeTransparency = 0.35
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = title
	end
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
end

local function ensureDescriptionLabel(row)
	local desc = row:FindFirstChild("Description")
	if desc and desc:IsA("TextLabel") then
		return desc
	end
	desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.BackgroundTransparency = 1
	desc.BorderSizePixel = 0
	desc.Font = Enum.Font.GothamMedium
	desc.TextScaled = true
	desc.TextWrapped = true
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextColor3 = Color3.fromRGB(235, 235, 235)
	desc.TextTransparency = 0.15
	desc.TextStrokeColor3 = Color3.new(0, 0, 0)
	desc.TextStrokeTransparency = 0.55
	desc.ZIndex = 2
	desc.Parent = row
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 16
	constraint.MinTextSize = 10
	constraint.Parent = desc
	return desc
end

local function layoutAchievementText(row)
	local title = row:FindFirstChild("Title")
	local desc = ensureDescriptionLabel(row)
	if title and title:IsA("TextLabel") then
		title.AnchorPoint = Vector2.new(0, 0)
		title.Position = UDim2.new(0.04, 0, 0.1, 0)
		title.Size = UDim2.new(0.62, 0, 0.36, 0)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.TextScaled = true
		local titleConstraint = title:FindFirstChildOfClass("UITextSizeConstraint")
		if not titleConstraint then
			titleConstraint = Instance.new("UITextSizeConstraint")
			titleConstraint.Parent = title
		end
		titleConstraint.MaxTextSize = 22
		titleConstraint.MinTextSize = 12
	end
	desc.AnchorPoint = Vector2.new(0, 0)
	desc.Position = UDim2.new(0.04, 0, 0.5, 0)
	desc.Size = UDim2.new(0.62, 0, 0.38, 0)
	return desc
end

local function setClaimFace(claimBtn, faceColor, muted)
	claimBtn.BackgroundColor3 = muted and Color3.fromRGB(72, 74, 82) or faceColor
	local face = claimBtn:FindFirstChild("Frame")
	if face and face:IsA("GuiObject") then
		face.BackgroundColor3 = faceColor
		face.BackgroundTransparency = muted and 0.2 or 0
		local faceGrad = face:FindFirstChildOfClass("UIGradient")
		if faceGrad then
			faceGrad.Enabled = not muted
		end
	end
	local btnGrad = claimBtn:FindFirstChildOfClass("UIGradient")
	if btnGrad then
		btnGrad.Enabled = not muted
	end
end

local function updateClaimButton(row, achievement)
	local claimBtn = row:FindFirstChild("Play")
	if not claimBtn then return end

	local title = claimBtn:FindFirstChild("Title")
	local cashIcon = claimBtn:FindFirstChild("ImageLabel")
	local showCash = false

	if achievement.claimed then
		if title and title:IsA("TextLabel") then title.Text = "DONE" end
		setClaimFace(claimBtn, STYLE.DONE_FACE, true)
		claimBtn.Active = false
	elseif achievement.complete then
		if title and title:IsA("TextLabel") then title.Text = "CLAIM" end
		setClaimFace(claimBtn, STYLE.CLAIM_FACE, false)
		claimBtn.Active = true
	else
		if title and title:IsA("TextLabel") then title.Text = tostring(achievement.rewardCoins) end
		setClaimFace(claimBtn, STYLE.REWARD_FACE, false)
		claimBtn.Active = false
		showCash = true
	end

	pcall(function()
		claimBtn.Interactable = claimBtn.Active
	end)

	if title and title:IsA("TextLabel") then
		title.TextColor3 = Color3.new(1, 1, 1)
		title.TextStrokeColor3 = Color3.new(0, 0, 0)
		title.TextStrokeTransparency = 0.4
		title.ZIndex = 3
	end
	if cashIcon and cashIcon:IsA("ImageLabel") then
		cashIcon.Visible = showCash
		cashIcon.ImageTransparency = 0
		cashIcon.ZIndex = 2
	end
end

local function renderAchievement(achievementId, achievement)
	local row = achievementRows[achievementId]
	if not row or not achievement then return end

	local def = AchievementDefinitions.get(achievementId)
	local title = row:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = string.format("%s  (%d/%d)", achievement.title, math.floor(achievement.progress), achievement.goal)
		styleAchievementTitle(title)
	end
	local desc = layoutAchievementText(row)
	desc.Text = (def and def.Description) or achievement.description or ""
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
	template.Visible = false

	template.AnchorPoint = Vector2.new(0.5, 0)
	template.Size = UDim2.new(0.98, 0, 0, ROW_HEIGHT)
	layoutAchievementText(template)

	local templateTitle = template:FindFirstChild("Title")
	styleAchievementTitle(templateTitle)
	local templatePlay = template:FindFirstChild("Play")
	if templatePlay then
		local playTitle = templatePlay:FindFirstChild("Title")
		if playTitle and playTitle:IsA("TextLabel") then
			playTitle.TextColor3 = Color3.new(1, 1, 1)
		end
	end

	for _, achievementId in ipairs(AchievementDefinitions.ORDER) do
		local row = template:Clone()
		row.Name = achievementId
		row.Visible = true
		row.AnchorPoint = Vector2.new(0.5, 0)
		row.Size = UDim2.new(0.98, 0, 0, ROW_HEIGHT)
		row.LayoutOrder = table.find(AchievementDefinitions.ORDER, achievementId) or 0
		row.Parent = achievementList

		styleAchievementTitle(row:FindFirstChild("Title"))
		local desc = layoutAchievementText(row)
		local def = AchievementDefinitions.get(achievementId)
		desc.Text = (def and def.Description) or ""

		local claimBtn = row:FindFirstChild("Play")
		if claimBtn then
			local playTitle = claimBtn:FindFirstChild("Title")
			if playTitle and playTitle:IsA("TextLabel") then
				playTitle.TextColor3 = Color3.new(1, 1, 1)
			end
			claimBtn.Activated:Connect(function()
				claimAchievementEvent:FireServer(achievementId)
			end)
			UIHelpers.bindButtonHover(claimBtn)
		end
		UIHelpers.bindButtonHover(row)

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
	elseif tabName == "Level" then
		if latestLevelSnapshot then
			updateLevelHeader(latestLevelSnapshot)
		end
		if latestMilestones then
			renderMilestones(latestMilestones)
		end
		levelStateEvent:FireServer()
	end
end

local function canShowLobbyPanel()
	if localPlayer:GetAttribute("InPractice") == true then
		return true
	end
	if localPlayer:GetAttribute("InArena") ~= true then
		return true
	end
	if localPlayer:GetAttribute("IsEliminated") == true then
		return true
	end
	return false
end

local function setRewardsVisible(isVisible, tabName)
	if isVisible and not canShowLobbyPanel() then
		return
	end

	if tabName and tabName ~= "Close" then
		setTab(tabName)
	end

	if isVisible then
		UIHelpers.animatePanelOpen(rewardsFrame)
	else
		UIHelpers.animatePanelClose(rewardsFrame)
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

levelStateEvent.OnClientEvent:Connect(function(snapshot, milestones)
	updateLevelHeader(snapshot)
	if milestones then
		renderMilestones(milestones)
	end
	updatePersonalStats()
end)

levelUpEvent.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end
	local msg = string.format("Level %d! +%d coins", payload.level or 0, payload.coins or 0)
	if payload.cosmetic then
		msg ..= " • Unlocked " .. payload.cosmetic
	end
	print("[LevelUp]", msg)
end)

localPlayer:GetAttributeChangedSignal("StatWins"):Connect(updatePersonalStats)
localPlayer:GetAttributeChangedSignal("StatKills"):Connect(updatePersonalStats)
localPlayer:GetAttributeChangedSignal("PlayerLevel"):Connect(updatePersonalStats)
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

UIHelpers.bindHoversUnder(navigate)
UIHelpers.bindButtonHover(closeBtn)

rewardsFrame.Visible = false
setTab("Daily")
updatePersonalStats()
levelStateEvent:FireServer()