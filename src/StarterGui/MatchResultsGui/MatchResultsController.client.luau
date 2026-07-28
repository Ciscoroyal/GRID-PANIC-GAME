local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local gui = script.Parent
local overlay = gui:WaitForChild("BackgroundOverlay")
local center = overlay:WaitForChild("CenterContainer")
local mainLayout = center:WaitForChild("MainLayout")
local winnerProfile = center:WaitForChild("WinnerProfile")
local winnerText = winnerProfile:WaitForChild("WinnerText")
local winnerName = winnerProfile:FindFirstChild("WinnerName")
local winnerAvatar = winnerProfile:WaitForChild("WinnerAvatar")
local rewardsPanel = center:WaitForChild("RewardsPanel")
local statTemplate = rewardsPanel:WaitForChild("StatRowTemplate")
local closeButton = overlay:WaitForChild("CloseButton")

statTemplate.Visible = false
overlay.Visible = false
gui.Enabled = false

local matchResultsEvent = ReplicatedStorage:WaitForChild("MatchResultsEvent")
local RESULTS_DISPLAY_SECONDS = 5
local RESULTS_DISPLAY_ORDER = 100
local autoCloseToken = 0

local HIDDEN_WHILE_RESULTS = {
	"PouchButton",
	"StoreButton",
	"TrophyButton",
	"TaskButton",
	"SettingButton",
	"FriendBoost",
}

local hiddenMenuState = {}

local PARTICIPANT_WINNER_LAYOUT = {
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 300, 0, 350),
}

local SPECTATOR_WINNER_LAYOUT = {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.new(0, 300, 0, 350),
}

local function applyWinnerLayout(isSpectator)
	local layout = isSpectator and SPECTATOR_WINNER_LAYOUT or PARTICIPANT_WINNER_LAYOUT
	winnerProfile.AnchorPoint = layout.AnchorPoint
	winnerProfile.Position = layout.Position
	winnerProfile.Size = layout.Size
end

local function clearRewardRows()
	for _, child in ipairs(rewardsPanel:GetChildren()) do
		if child:IsA("Frame") and child ~= statTemplate and child.Name ~= "StatRowTemplate" then
			child:Destroy()
		end
	end
end

local function populateRewardRows(rewards)
	for index, reward in ipairs(rewards) do
		local row = statTemplate:Clone()
		row.Name = "StatRow_" .. index
		row.Visible = true
		row.Parent = rewardsPanel

		local icon = row:FindFirstChild("StatIcon")
		local text = row:FindFirstChild("StatText")
		if icon then
			icon.LayoutOrder = 1
			icon.Position = UDim2.new(0, 0, 0, 0)
			icon.Size = UDim2.new(0, 30, 0, 30)
			if reward.type == "cheer" or reward.type == "sponsor" then
				icon.ScaleType = Enum.ScaleType.Fit
				if not icon:FindFirstChild("AvatarCorner") then
					local corner = Instance.new("UICorner")
					corner.Name = "AvatarCorner"
					corner.CornerRadius = UDim.new(1, 0)
					corner.Parent = icon
				end
				if reward.targetUserId then
					UIHelpers.setAvatarImage(icon, reward.targetUserId)
				else
					icon.Image = reward.icon or ""
				end
			else
				icon.ScaleType = Enum.ScaleType.Stretch
				icon.Image = reward.icon or ""
			end
		end
		if text then
			text.LayoutOrder = 2
			text.Position = UDim2.new(0, 0, 0, 0)
			text.Text = reward.text or ""
		end
	end
end

local function getMenuGui()
	return playerGui:FindFirstChild("MenuGui")
end

local function getLobbyControlsGui()
	return playerGui:FindFirstChild("LobbyControlsGui")
end

local function getLoadoutGui()
	return playerGui:FindFirstChild("LoadoutGui")
end

local function hideLobbyUi()
	table.clear(hiddenMenuState)

	local menuGui = getMenuGui()
	if menuGui then
		for _, name in ipairs(HIDDEN_WHILE_RESULTS) do
			local element = menuGui:FindFirstChild(name)
			if element then
				hiddenMenuState[element] = element.Visible
				element.Visible = false
			end
		end
	end

	local lobbyControls = getLobbyControlsGui()
	if lobbyControls then
			hiddenMenuState[lobbyControls] = lobbyControls.Enabled
			lobbyControls.Enabled = false
	end

	local loadoutGui = getLoadoutGui()
	if loadoutGui then
		local toggleLoadout = loadoutGui:FindFirstChild("ToggleLoadout")
		if toggleLoadout and toggleLoadout:IsA("BindableEvent") then
			toggleLoadout:Fire("Close")
		end
	end
end

local function restoreLobbyUi()
	for element, wasVisible in pairs(hiddenMenuState) do
		if element.Parent then
			if element:IsA("ScreenGui") then
				element.Enabled = wasVisible
			else
				element.Visible = wasVisible
			end
		end
	end
	table.clear(hiddenMenuState)
end

local function hideResults()
	overlay.Active = false
	overlay.Visible = false
	gui.Enabled = false
	restoreLobbyUi()
end

local function showResults(data)
	clearRewardRows()

	local viewMode = data.viewMode or "spectator"
	local isSpectator = viewMode ~= "participant"
	local winnerUserId = data.winnerUserId or 0
	local winnerDisplayName = data.winnerName or "Unknown"

	winnerText.Text = "WINNER"
	if winnerName then
		winnerName.Text = winnerDisplayName
		winnerName.Visible = true
	end

	if winnerUserId > 0 then
		UIHelpers.setAvatarImage(winnerAvatar, winnerUserId)
	else
		winnerAvatar.Image = ""
	end

	applyWinnerLayout(isSpectator)
	winnerProfile.LayoutOrder = 1
	rewardsPanel.LayoutOrder = 2
	rewardsPanel.Visible = not isSpectator

	if not isSpectator then
		populateRewardRows(data.rewards or {})
	end

	gui.DisplayOrder = RESULTS_DISPLAY_ORDER
	overlay.Active = true
	hideLobbyUi()

	gui.Enabled = true
	overlay.Visible = true

	autoCloseToken += 1
	local token = autoCloseToken
	task.delay(RESULTS_DISPLAY_SECONDS, function()
		if token == autoCloseToken then
			hideResults()
		end
	end)
end

matchResultsEvent.OnClientEvent:Connect(showResults)

closeButton.MouseButton1Click:Connect(function()
	autoCloseToken += 1
	hideResults()
end)