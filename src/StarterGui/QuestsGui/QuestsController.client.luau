local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local menuGui = playerGui:WaitForChild("MenuGui")
local tasksPanel = menuGui:WaitForChild("Tasks")
local questList = tasksPanel:WaitForChild("Frame")
local headerTitle = tasksPanel:WaitForChild("Title")

local questStateEvent = ReplicatedStorage:WaitForChild("QuestStateEvent")
local claimQuestEvent = ReplicatedStorage:WaitForChild("ClaimQuestEvent")

local STYLE = {
	ACCENT = Color3.fromRGB(0, 170, 85),
	GOLD = Color3.fromRGB(255, 200, 50),
	MUTED = Color3.fromRGB(90, 92, 105),
}

local questRows = {}
local latestState = nil
local rowTemplate = nil

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

local function setHeaderText(text)
	setLabelTreeText(headerTitle, text)
end

local function formatProgress(quest)
	if quest.type == "Survive" or (typeof(quest.id) == "string" and string.sub(quest.id, 1, 7) == "Survive") then
		return string.format("%d / %d sec", math.floor(quest.progress), quest.goal)
	end
	return string.format("%d / %d", math.floor(quest.progress), quest.goal)
end

local function updateClaimButton(row, quest)
	local claimBtn = row:FindFirstChild("Claim")
	if not claimBtn then
		return
	end

	local title = claimBtn:FindFirstChild("Title")
	local cashIcon = claimBtn:FindFirstChild("CashIcon")

	if quest.claimed then
		setLabelTreeText(title, "DONE")
		claimBtn.BackgroundColor3 = STYLE.MUTED
		claimBtn.Active = false
		if cashIcon then
			cashIcon.Visible = false
		end
	elseif quest.complete then
		setLabelTreeText(title, "CLAIM")
		claimBtn.BackgroundColor3 = STYLE.GOLD
		claimBtn.Active = true
		if cashIcon then
			cashIcon.Visible = true
		end
	else
		setLabelTreeText(title, tostring(quest.rewardCoins))
		claimBtn.BackgroundColor3 = STYLE.ACCENT
		claimBtn.Active = false
		if cashIcon then
			cashIcon.Visible = true
		end
	end
end

local function clearRows()
	for questId, row in pairs(questRows) do
		if row and row.Parent then
			row:Destroy()
		end
		questRows[questId] = nil
	end
end

local function ensureRows(order)
	if not rowTemplate then
		return
	end

	local same = true
	if #order ~= 0 then
		for index, questId in ipairs(order) do
			local row = questRows[questId]
			if not row or row.LayoutOrder ~= index then
				same = false
				break
			end
		end
		local count = 0
		for _ in pairs(questRows) do
			count += 1
		end
		if count ~= #order then
			same = false
		end
	else
		same = false
	end
	if same then
		return
	end

	clearRows()
	for index, questId in ipairs(order) do
		local row = rowTemplate:Clone()
		row.Name = questId
		row.Visible = true
		row.LayoutOrder = index
		row.Parent = questList

		local claimBtn = row:FindFirstChild("Claim")
		if claimBtn then
			claimBtn.Activated:Connect(function()
				claimQuestEvent:FireServer(questId)
			end)
			UIHelpers.bindButtonHover(claimBtn)
		end
		UIHelpers.bindButtonHover(row)

		questRows[questId] = row
	end
end

local function renderQuest(questId, quest)
	local row = questRows[questId]
	if not row or not quest then
		return
	end

	setLabelTreeText(row:FindFirstChild("Title"), quest.title)
	local desc = row:FindFirstChild("Description")
	if desc then
		desc.Visible = false
		setLabelTreeText(desc, "")
	end
	setLabelTreeText(row:FindFirstChild("Progress"), formatProgress(quest))
	updateClaimButton(row, quest)
end

local function renderAll(payload)
	latestState = payload
	if not payload or not payload.quests then
		return
	end

	setHeaderText("Daily Task")
	local order = payload.order
	if typeof(order) ~= "table" or #order == 0 then
		order = {}
		for questId in pairs(payload.quests) do
			table.insert(order, questId)
		end
		table.sort(order)
	end

	ensureRows(order)
	for _, questId in ipairs(order) do
		renderQuest(questId, payload.quests[questId])
	end
end

local function setupTemplate()
	rowTemplate = questList:FindFirstChild("QuestRowTemplate")
	if not rowTemplate then
		return
	end
	rowTemplate.Visible = false
end

local function updateTasksVisibility()
	local inMatch = localPlayer:GetAttribute("InArena") == true and localPlayer:GetAttribute("IsEliminated") ~= true
	tasksPanel.Visible = not inMatch
end

setupTemplate()

questStateEvent.OnClientEvent:Connect(renderAll)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(updateTasksVisibility)
localPlayer:GetAttributeChangedSignal("IsEliminated"):Connect(updateTasksVisibility)
updateTasksVisibility()

if latestState then
	renderAll(latestState)
end
