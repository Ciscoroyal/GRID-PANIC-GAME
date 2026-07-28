local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestDefinitions = require(ReplicatedStorage:WaitForChild("QuestDefinitions"))

local localPlayer = Players.LocalPlayer
local questsGui = script.Parent
local questsFrame = questsGui:WaitForChild("Quests")
local toggleQuests = questsGui:WaitForChild("ToggleQuests")
local scroll = questsFrame:WaitForChild("ScrollingFrame")
local closeBtn = questsFrame:WaitForChild("Top"):WaitForChild("Close")
local headerTitle = questsFrame:WaitForChild("Top"):WaitForChild("Title")

local questStateEvent = ReplicatedStorage:WaitForChild("QuestStateEvent")
local claimQuestEvent = ReplicatedStorage:WaitForChild("ClaimQuestEvent")

local STYLE = {
	ACCENT = Color3.fromRGB(0, 170, 85),
	GOLD = Color3.fromRGB(255, 200, 50),
	MUTED = Color3.fromRGB(90, 92, 105),
}

local questRows = {}
local latestState = nil

local function formatProgress(quest)
	if quest.id == "Survive60" then
		return string.format("%d / %d sec", math.floor(quest.progress), quest.goal)
	end
	return string.format("%d / %d", math.floor(quest.progress), quest.goal)
end

local function updateClaimButton(row, quest)
	local claimBtn = row:FindFirstChild("Claim")
	if not claimBtn then return end

	if quest.claimed then
		claimBtn.Text = "DONE"
		claimBtn.BackgroundColor3 = STYLE.MUTED
		claimBtn.Active = false
	elseif quest.complete then
		claimBtn.Text = "CLAIM " .. quest.rewardCoins
		claimBtn.BackgroundColor3 = STYLE.GOLD
		claimBtn.Active = true
	else
		claimBtn.Text = quest.rewardCoins .. " COINS"
		claimBtn.BackgroundColor3 = STYLE.ACCENT
		claimBtn.Active = false
	end
end

local function renderQuest(questId, quest)
	local row = questRows[questId]
	if not row then return end

	local title = row:FindFirstChild("Title")
	local desc = row:FindFirstChild("Description")
	local progress = row:FindFirstChild("Progress")

	if title then title.Text = quest.title end
	if desc then desc.Text = quest.description end
	if progress then progress.Text = formatProgress(quest) end
	updateClaimButton(row, quest)
end

local function renderAll(payload)
	latestState = payload
	if not payload or not payload.quests then return end
	if headerTitle then
		headerTitle.Text = payload.day and ("DAILY TASKS  " .. payload.day) or "DAILY TASKS"
	end
	for questId, quest in pairs(payload.quests) do
		renderQuest(questId, quest)
	end
end

local function buildRows()
	local template = scroll:FindFirstChild("QuestRowTemplate")
	if not template then return end

	for _, questId in ipairs(QuestDefinitions.ORDER) do
		local row = template:Clone()
		row.Name = questId
		row.Visible = true
		row.LayoutOrder = table.find(QuestDefinitions.ORDER, questId) or 0
		row.Parent = scroll

		local claimBtn = row:FindFirstChild("Claim")
		if claimBtn then
			claimBtn.Activated:Connect(function()
				claimQuestEvent:FireServer(questId)
			end)
		end

		questRows[questId] = row
	end
end

local function setQuestsVisible(isVisible)
	if isVisible and localPlayer:GetAttribute("InArena") == true then
		return
	end

	questsFrame.Visible = isVisible
	if isVisible then
		if latestState then renderAll(latestState) end
		questsFrame.Position = UDim2.new(0.5, 0, 0.56, 0)
		questsFrame:TweenPosition(
			UDim2.new(0.5, 0, 0.5, 0),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Back,
			0.35,
			true
		)
	end
end

buildRows()

closeBtn.Activated:Connect(function()
	setQuestsVisible(false)
end)

toggleQuests.Event:Connect(function(action)
	if action == "Close" then
		setQuestsVisible(false)
		return
	end
	if action == "Open" then
		setQuestsVisible(true)
		return
	end
	setQuestsVisible(not questsFrame.Visible)
end)

questStateEvent.OnClientEvent:Connect(renderAll)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	if localPlayer:GetAttribute("InArena") == true then
		setQuestsVisible(false)
	end
end)

questsFrame.Visible = false