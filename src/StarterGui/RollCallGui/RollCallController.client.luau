local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

local function clearRows()
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child ~= rowTemplate and not child:IsA("UILayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function createRollCallRow(playerName, abilityName)
	local player = Players:FindFirstChild(playerName)

	local row = rowTemplate:Clone()
	row.Name = playerName .. "_RollCallRow"
	row.Visible = true
	row.Parent = scrollingFrame

	row.NameText.Text = player and player.DisplayName or playerName

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

showRollCall.OnClientEvent:Connect(function(rollCallData)
	clearRows()

	local rowCount = 0
	for playerName, abilityName in pairs(rollCallData) do
		rowCount += 1
		createRollCallRow(playerName, abilityName)
	end

	if rowCount == 0 then
		return
	end

	listFrame.Position = UDim2.new(0.5, 0, 0.45, 0)
	listFrame.Visible = true
	listFrame:TweenPosition(UDim2.new(0.5, 0, 0.5, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Back, 0.35, true)

	task.delay(4.5, hideRollCall)
end)
