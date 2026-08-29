local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))
local EquipAbilityEvent = ReplicatedStorage:WaitForChild("EquipAbilityEvent")
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")

local localPlayer = Players.LocalPlayer
local currentAbilityGui = script.Parent
local panelFrame = currentAbilityGui:WaitForChild("Current Ability")
local toggleCurrentAbility = currentAbilityGui:WaitForChild("ToggleCurrentAbility")

local abilityGrid = panelFrame:WaitForChild("AbilityGrid")
local abilityDetail = panelFrame:WaitForChild("AbilityDetail")
local closeBtn = panelFrame:WaitForChild("Top"):WaitForChild("Close")

local detailName = abilityDetail:WaitForChild("DetailName")
local detailDesc = abilityDetail:WaitForChild("DetailsDescription")
local detailIcon = abilityDetail:WaitForChild("DetailIcon")
local actionBtn = abilityDetail:WaitForChild("Button")
local priceLabel = actionBtn:WaitForChild("Price")
local priceTitle = priceLabel:FindFirstChild("Title") or priceLabel
local buttonFrame = actionBtn:FindFirstChild("Frame")

local STYLE = {
	ACCENT = Color3.fromRGB(0, 170, 85),
	GOLD = Color3.fromRGB(255, 200, 50),
	DANGER = Color3.fromRGB(210, 60, 60),
}

local selectedAbility = nil
local abilityCards = {}

local function setupPanelLayout()
	-- Left grid / right detail split under the Top bar
	abilityGrid.AnchorPoint = Vector2.new(0, 0)
	abilityGrid.Position = UDim2.new(0.02, 0, 0.12, 0)
	abilityGrid.Size = UDim2.new(0.58, 0, 0.84, 0)
	abilityGrid.ScrollBarThickness = 6

	local gridLayout = abilityGrid:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then
		gridLayout.CellSize = UDim2.new(0.3, 0, 0.3, 0)
		gridLayout.CellPadding = UDim2.new(0.025, 0, 0.035, 0)
		gridLayout.FillDirection = Enum.FillDirection.Horizontal
		gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	local gridPad = abilityGrid:FindFirstChildOfClass("UIPadding")
	if not gridPad then
		gridPad = Instance.new("UIPadding")
		gridPad.Parent = abilityGrid
	end
	gridPad.PaddingLeft = UDim.new(0.03, 0)
	gridPad.PaddingRight = UDim.new(0.03, 0)
	gridPad.PaddingTop = UDim.new(0.03, 0)
	gridPad.PaddingBottom = UDim.new(0.03, 0)

	abilityDetail.AnchorPoint = Vector2.new(1, 0)
	abilityDetail.Position = UDim2.new(0.98, 0, 0.12, 0)
	abilityDetail.Size = UDim2.new(0.36, 0, 0.84, 0)

	detailName.AnchorPoint = Vector2.new(0.5, 0)
	detailName.Position = UDim2.new(0.5, 0, 0.04, 0)
	detailName.Size = UDim2.new(0.9, 0, 0.09, 0)
	detailName.TextXAlignment = Enum.TextXAlignment.Center
	detailName.TextYAlignment = Enum.TextYAlignment.Center
	detailName.TextScaled = true

	detailIcon.AnchorPoint = Vector2.new(0.5, 0)
	detailIcon.Position = UDim2.new(0.5, 0, 0.15, 0)
	detailIcon.Size = UDim2.new(0.58, 0, 0.38, 0)
	local iconAspect = detailIcon:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not iconAspect then
		iconAspect = Instance.new("UIAspectRatioConstraint")
		iconAspect.Parent = detailIcon
	end
	iconAspect.AspectRatio = 1

	detailDesc.AnchorPoint = Vector2.new(0.5, 0)
	detailDesc.Position = UDim2.new(0.5, 0, 0.56, 0)
	detailDesc.Size = UDim2.new(0.9, 0, 0.22, 0)
	detailDesc.TextWrapped = true
	detailDesc.TextScaled = true
	detailDesc.TextXAlignment = Enum.TextXAlignment.Center
	detailDesc.TextYAlignment = Enum.TextYAlignment.Top
	local descConstraint = detailDesc:FindFirstChildOfClass("UITextSizeConstraint")
	if not descConstraint then
		descConstraint = Instance.new("UITextSizeConstraint")
		descConstraint.Parent = detailDesc
	end
	descConstraint.MaxTextSize = 18
	descConstraint.MinTextSize = 11

	actionBtn.AnchorPoint = Vector2.new(0.5, 1)
	actionBtn.Position = UDim2.new(0.5, 0, 0.96, 0)
	actionBtn.Size = UDim2.new(0.82, 0, 0.12, 0)
end

local function showToast(message)
	local existing = currentAbilityGui:FindFirstChild("CurrentAbilityToast")
	if existing then existing:Destroy() end

	local toast = Instance.new("TextLabel")
	toast.Name = "CurrentAbilityToast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 0.9, 0)
	toast.Size = UDim2.new(0.35, 0, 0.05, 0)
	toast.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = Color3.fromRGB(245, 245, 245)
	toast.Font = Enum.Font.GothamBold
	toast.TextScaled = true
	toast.Text = message
	toast.ZIndex = 30
	toast.Parent = currentAbilityGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast

	task.delay(1.5, function()
		if toast.Parent then toast:Destroy() end
	end)
end

local function setActionLabel(text, state)
	priceLabel.Text = ""
	priceTitle.Text = text

	if buttonFrame then
		if state == "equipped" then
			buttonFrame.BackgroundColor3 = STYLE.ACCENT
		elseif state == "buy" then
			buttonFrame.BackgroundColor3 = STYLE.GOLD
		elseif state == "error" then
			buttonFrame.BackgroundColor3 = STYLE.DANGER
		else
			buttonFrame.BackgroundColor3 = STYLE.ACCENT
		end
	end
end

local function getActionState(abilityName, data)
	if localPlayer:GetAttribute("EquippedAbility") == abilityName then
		return "equipped"
	end
	if data.Cost == 0 or localPlayer:GetAttribute(AbilityData.getOwnedAttributeKey(abilityName)) == true then
		return "equip"
	end
	return "buy"
end

local function getActionLabel(abilityName, data)
	if localPlayer:GetAttribute("EquippedAbility") == abilityName then
		return "EQUIPPED"
	end
	if data.Cost == 0 or localPlayer:GetAttribute(AbilityData.getOwnedAttributeKey(abilityName)) == true then
		return "EQUIP"
	end
	return "BUY " .. data.Cost
end

-- Selected cards keep their coloured highlight; unselected ones show no
-- outline at all, since the ability artwork already has its own border.
local function highlightCard(abilityName)
	for name, card in pairs(abilityCards) do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			if name == abilityName then
				local data = AbilityData[abilityName]
				stroke.Color = (data and data.Color) or STYLE.GOLD
				stroke.Thickness = 3
			else
				stroke.Thickness = 0
			end
		end
	end
end

local function updateDetailPanel(abilityName)
	local data = AbilityData[abilityName]
	if not data then return end

	selectedAbility = abilityName
	detailName.Text = abilityName
	detailDesc.Text = data.Description .. "\nCooldown: " .. data.Cooldown .. "s"
	UIHelpers.setAbilityImage(detailIcon, abilityName)
	detailIcon.Visible = true

	setActionLabel(getActionLabel(abilityName, data), getActionState(abilityName, data))
	highlightCard(abilityName)
end

local function refreshAllCards()
	if selectedAbility then
		updateDetailPanel(selectedAbility)
	end
end

local function waitForActionSuccess(abilityName, timeout)
	local data = AbilityData[abilityName]
	if not data then return false end

	local ownedAttribute = AbilityData.getOwnedAttributeKey(abilityName)
	local function isSuccessful()
		if localPlayer:GetAttribute("EquippedAbility") == abilityName then
			return true
		end
		if data.Cost > 0 and localPlayer:GetAttribute(ownedAttribute) == true then
			return true
		end
		return false
	end

	if isSuccessful() then return true end

	local done = false
	local conns = {}
	local function finish()
		if done then return end
		done = true
		for _, conn in ipairs(conns) do conn:Disconnect() end
	end

	table.insert(conns, localPlayer:GetAttributeChangedSignal("EquippedAbility"):Connect(function()
		if isSuccessful() then finish() end
	end))

	if data.Cost > 0 then
		table.insert(conns, localPlayer:GetAttributeChangedSignal(ownedAttribute):Connect(function()
			if isSuccessful() then finish() end
		end))
	end

	task.delay(timeout or 3, finish)
	while not done do task.wait() end
	return isSuccessful()
end

local function clearGeneratedCards()
	for _, child in ipairs(abilityGrid:GetChildren()) do
		if child:IsA("GuiButton") and child.Name ~= "AbilityCardTemplate" then
			child:Destroy()
		end
	end
	abilityCards = {}
end

local function buildAbilityGrid()
	local template = abilityGrid:FindFirstChild("AbilityCardTemplate") or abilityGrid:FindFirstChildWhichIsA("ImageButton")
	if not template then
		warn("[CurrentAbility] Missing ability card template in AbilityGrid")
		return
	end

	template.Name = "AbilityCardTemplate"
	template.Visible = false

	clearGeneratedCards()

	for abilityName, data in pairs(AbilityData) do
		if type(data) ~= "table" then continue end
		-- Disabled abilities are not offered at all.
		if not AbilityData.isEnabled(abilityName) then continue end

		local card = template:Clone()
		card.Name = abilityName
		card.Visible = true
		card.Size = UDim2.new(1, 0, 1, 0)
		card.LayoutOrder = data.Cost or 0
		UIHelpers.setAbilityImage(card, abilityName)
		card.Parent = abilityGrid

		card.Activated:Connect(function()
			updateDetailPanel(abilityName)
		end)
		UIHelpers.bindButtonHover(card)

		abilityCards[abilityName] = card
	end
end

local function canShowPanel()
	if localPlayer:GetAttribute("InArena") ~= true then
		return true
	end
	if localPlayer:GetAttribute("IsEliminated") == true then
		return true
	end
	local countdown = survivalTimeValue.Value
	return countdown >= 1 and countdown <= 15
end

local function setPanelVisible(isVisible)
	if isVisible and not canShowPanel() then
		return
	end

	if isVisible then
		UIHelpers.animatePanelOpen(panelFrame)
		local equipped = localPlayer:GetAttribute("EquippedAbility")
		if type(equipped) == "string" and AbilityData.isEnabled(equipped) then
			updateDetailPanel(equipped)
		elseif selectedAbility then
			refreshAllCards()
		end
	else
		UIHelpers.animatePanelClose(panelFrame)
	end
end

setupPanelLayout()
buildAbilityGrid()

-- These two were stranded inside setPanelVisible's blocked-open branch, so the
-- buy/equip button and the close button only ever gained hover feedback if a
-- player happened to try opening the panel mid-match first.
UIHelpers.bindButtonHover(closeBtn)
UIHelpers.bindButtonHover(actionBtn)
panelFrame.Visible = false

local firstAbility = localPlayer:GetAttribute("EquippedAbility")
if type(firstAbility) ~= "string" or not AbilityData.isEnabled(firstAbility) then
	firstAbility = AbilityData.getDefaultAbility()
end
if firstAbility then
	updateDetailPanel(firstAbility)
end

closeBtn.Activated:Connect(function()
	setPanelVisible(false)
end)

actionBtn.Activated:Connect(function()
	if not selectedAbility then return end

	local data = AbilityData[selectedAbility]
	if not data then return end

	-- Captured before the server call: afterwards the owned attribute is set and
	-- a purchase is indistinguishable from a plain equip.
	local isPurchase = data.Cost > 0
		and localPlayer:GetAttribute(AbilityData.getOwnedAttributeKey(selectedAbility)) ~= true

	if isPurchase then
		local leaderstats = localPlayer:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		if not coins or coins.Value < data.Cost then
			Audio.play("PurchaseDenied")
			setActionLabel("NOT ENOUGH COINS", "error")
			task.delay(1, function()
				updateDetailPanel(selectedAbility)
			end)
			return
		end
	end

	EquipAbilityEvent:FireServer(selectedAbility)

	if waitForActionSuccess(selectedAbility, 3) then
		-- A plain equip already got the generic click sound; only a real spend
		-- earns the purchase chime.
		if isPurchase then
			Audio.play("Purchase")
		end
		setActionLabel("EQUIPPED", "equipped")
		refreshAllCards()
		task.delay(0.5, function()
			updateDetailPanel(selectedAbility)
		end)
	else
		Audio.play("PurchaseDenied")
		setActionLabel("FAILED", "error")
		task.delay(1, function()
			updateDetailPanel(selectedAbility)
		end)
	end
end)

toggleCurrentAbility.Event:Connect(function(action)
	if action == "Close" then
		setPanelVisible(false)
		return
	end
	if action == "Open" then
		setPanelVisible(true)
		return
	end
	setPanelVisible(not panelFrame.Visible)
end)

for abilityName, data in pairs(AbilityData) do
	if type(data) ~= "table" then continue end
	if not AbilityData.isEnabled(abilityName) then continue end
	localPlayer:GetAttributeChangedSignal(AbilityData.getOwnedAttributeKey(abilityName)):Connect(refreshAllCards)
end

localPlayer:GetAttributeChangedSignal("EquippedAbility"):Connect(function()
	if panelFrame.Visible and selectedAbility then
		refreshAllCards()
	end
end)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	if localPlayer:GetAttribute("InArena") == true then
		setPanelVisible(false)
	end
end)

panelFrame.Visible = false