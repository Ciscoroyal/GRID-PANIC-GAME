local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))
local showRollCall = ReplicatedStorage:WaitForChild("ShowRollCall")

local gui = script.Parent
local listFrame = gui:WaitForChild("ListFrame")
local scrollingFrame = listFrame:WaitForChild("PlayerListScroll")
local rowTemplate = scrollingFrame:WaitForChild("PlayerRowTemplate")

rowTemplate.Visible = false
listFrame.Visible = false

scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollingFrame.ScrollingDirection = Enum.ScrollingDirection.Y

local listLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
if listLayout then
	-- Must be vertical or extra players clip off-screen horizontally
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
end

local TEAM_COLORS = {
	Blue = Color3.fromRGB(80, 160, 255),
	Red = Color3.fromRGB(255, 80, 80),
	Juggernaut = Color3.fromRGB(255, 200, 60),
	Hunter = Color3.fromRGB(200, 200, 200),
}

local function clearRows()
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child ~= rowTemplate and not child:IsA("UILayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function ensureTeamLabel(row)
	local label = row:FindFirstChild("TeamText")
	if label then
		return label
	end
	label = Instance.new("TextLabel")
	label.Name = "TeamText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(0.22, 0, 0.55, 0)
	label.Position = UDim2.new(0.48, 0, 0.22, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Visible = false
	label.ZIndex = (row.NameText and row.NameText.ZIndex or 1) + 1
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = label
	label.Parent = row
	return label
end

local function createRollCallRow(playerName, entry, layoutOrder)
	local abilityName = entry
	local teamId = nil
	if typeof(entry) == "table" then
		abilityName = entry.ability or "None"
		teamId = entry.team
	end

	local player = Players:FindFirstChild(playerName)

	local row = rowTemplate:Clone()
	row.Name = playerName .. "_RollCallRow"
	row.LayoutOrder = layoutOrder
	row.Visible = true
	row.Parent = scrollingFrame

	local displayName = player and player.DisplayName or playerName
	if teamId == "Blue" or teamId == "Red" or teamId == "Juggernaut" or teamId == "Hunter" then
		row.NameText.Text = displayName
		local teamLabel = ensureTeamLabel(row)
		if teamId == "Blue" then
			teamLabel.Text = "BLUE"
		elseif teamId == "Red" then
			teamLabel.Text = "RED"
		elseif teamId == "Juggernaut" then
			teamLabel.Text = "JUGGERNAUT"
		else
			teamLabel.Text = "HUNTER"
		end
		teamLabel.TextColor3 = TEAM_COLORS[teamId]
		teamLabel.Visible = true
	else
		row.NameText.Text = displayName
		local teamLabel = row:FindFirstChild("TeamText")
		if teamLabel then
			teamLabel.Visible = false
		end
	end

	if player then
		UIHelpers.setAvatarImage(row.AvatarImage, player.UserId)
	end

	UIHelpers.setAbilityImage(row.AbilityImage, abilityName)

	return row
end

local function hideRollCall()
	listFrame.Visible = false
	clearRows()
end

local hideToken = 0

showRollCall.OnClientEvent:Connect(function(rollCallData)
	hideToken = hideToken + 1
	local token = hideToken
	clearRows()

	local sortedNames = {}
	for playerName in pairs(rollCallData) do
		table.insert(sortedNames, playerName)
	end
	-- Team mode: group Blue then Red, else alphabetical
	table.sort(sortedNames, function(a, b)
		local ea, eb = rollCallData[a], rollCallData[b]
		local ta = typeof(ea) == "table" and ea.team or nil
		local tb = typeof(eb) == "table" and eb.team or nil
		if ta ~= tb then
			if ta == "Juggernaut" then return true end
			if tb == "Juggernaut" then return false end
			if ta == "Blue" then return true end
			if tb == "Blue" then return false end
			if ta == "Red" then return true end
			if tb == "Red" then return false end
			if ta == "Hunter" then return true end
			if tb == "Hunter" then return false end
		end
		return a < b
	end)

	local rowCount = #sortedNames
	for index, playerName in ipairs(sortedNames) do
		createRollCallRow(playerName, rollCallData[playerName], index)
	end

	if rowCount == 0 then
		return
	end

	-- Ensure canvas tall enough for every row (backup if AutomaticCanvasSize lags)
	local rowHeight = rowTemplate.Size.Y.Offset
	if rowHeight <= 0 then
		rowHeight = 65
	end
	local pad = 6
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, rowCount * (rowHeight + pad) + pad)

	listFrame.Position = UDim2.new(0.5, 0, 0.45, 0)
	listFrame.Visible = true
	listFrame:TweenPosition(UDim2.new(0.5, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.35, true)

	task.delay(3.2, function()
		if token == hideToken then
			hideRollCall()
		end
	end)
end)
