local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))
local PurchaseAbilityVFXEvent = ReplicatedStorage:WaitForChild("PurchaseAbilityVFXEvent")
local VFXEvent = ReplicatedStorage:WaitForChild("VFXEvent")

local PlayerSettings
pcall(function()
	PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))
end)

local localPlayer = Players.LocalPlayer
local loadoutGui = script.Parent
local loadoutFrame = loadoutGui:WaitForChild("Loadout")
local toggleLoadout = loadoutGui:WaitForChild("ToggleLoadout")

local navigate = loadoutFrame:WaitForChild("Navigate")
local abilityFrame = loadoutFrame:WaitForChild("Ability")
local dashFrame = loadoutFrame:WaitForChild("Dash")
local deathFrame = loadoutFrame:WaitForChild("Death")
local closeBtn = loadoutFrame:WaitForChild("Top"):WaitForChild("Close")

local abilityGrid = abilityFrame:WaitForChild("LeftPane_Abilities")

-- AbilityDetail overlaps the built-in VFX pane; keep hidden.
local abilityDetail = abilityFrame:FindFirstChild("AbilityDetail")
if abilityDetail then
	abilityDetail.Visible = false
end

local RIGHT_PANE_BY_ABILITY = {
	["Grid Punch"] = "RightPanePunch_VFX",
	["Shield Bubble"] = "RightPaneShield_VFX",
	["Shockwave"] = "RightPaneShockwave_VFX",
	["Proximity Mine"] = "RightPaneMine_VFX",
	["Dash Strike"] = "RightPaneDashStrike_VFX",
}

local PREVIEW_VFX_BY_ABILITY = {
	["Grid Punch"] = "LightShake",
	["Dash Strike"] = "LightShake",
	["Shield Bubble"] = "LightShake",
	["Proximity Mine"] = "LightShake",
	["Shockwave"] = "HeavyShake",
}

local tabButtons = {
	Ability = navigate:WaitForChild("Ability"),
	DASH = navigate:WaitForChild("DASH"),
	DEATH = navigate:WaitForChild("DEATH"),
}

local tabFrames = {
	Ability = abilityFrame,
	DASH = dashFrame,
	DEATH = deathFrame,
}

local STYLE = {
	ACCENT = Color3.fromRGB(0, 170, 85),
	GOLD = Color3.fromRGB(255, 200, 50),
	MUTED = Color3.fromRGB(90, 92, 105),
}

local selectedAbility = nil
local selectedVFXByAbility = {}
local currentTab = "Ability"
local abilityCards = {}
local vfxCardsByPane = {}
local vfxBound = false

local function getVFXAttributeKey(abilityName)
	return "EquippedVFX_" .. abilityName:gsub(" ", "_")
end

local function getVFXVariantName(vfxCard)
	local titleLabel = vfxCard:FindFirstChild("Title", true)
	if titleLabel and titleLabel:IsA("TextLabel") then
		local inner = titleLabel:FindFirstChild("Title")
		if inner and inner:IsA("TextLabel") and inner.Text ~= "" then
			return inner.Text
		end
		if titleLabel.Text ~= "" and titleLabel.Text ~= "Button" then
			return titleLabel.Text
		end
	end
	return vfxCard.Name
end

local function parsePrice(vfxCard)
	local priceLabel = vfxCard:FindFirstChild("Price", true)
	if not priceLabel then
		return 0
	end
	local text = priceLabel.Text
	local inner = priceLabel:FindFirstChild("Title")
	if inner and inner:IsA("TextLabel") then
		text = inner.Text
	end
	text = text:gsub("[^%d]", "")
	return tonumber(text) or 0
end

local function showToast(message)
	local existing = loadoutGui:FindFirstChild("LoadoutToast")
	if existing then existing:Destroy() end

	local toast = Instance.new("TextLabel")
	toast.Name = "LoadoutToast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 0.9, 0)
	toast.Size = UDim2.new(0.4, 0, 0.05, 0)
	toast.BackgroundColor3 = Color3.fromRGB(25, 27, 35)
	toast.BackgroundTransparency = 0.15
	toast.TextColor3 = Color3.fromRGB(245, 245, 245)
	toast.Font = Enum.Font.GothamBold
	toast.TextScaled = true
	toast.Text = message
	toast.ZIndex = 30
	toast.Parent = loadoutGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = toast

	task.delay(1.5, function()
		if toast.Parent then toast:Destroy() end
	end)
end

local function previewAbilityVFX(abilityName)
	if PlayerSettings and not PlayerSettings.isScreenShakeEnabled() then
		return
	end

	local effect = PREVIEW_VFX_BY_ABILITY[abilityName] or "LightShake"
	local camera = workspace.CurrentCamera
	if not camera then return end

	local intensity = effect == "HeavyShake" and 2 or 0.8
	local duration = effect == "HeavyShake" and 0.4 or 0.2
	local startTime = os.clock()
	local conn
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed >= duration then
			conn:Disconnect()
			return
		end
		local currentIntensity = intensity * (1 - (elapsed / duration))
		local offsetX = (math.random() - 0.5) * currentIntensity
		local offsetY = (math.random() - 0.5) * currentIntensity
		local offsetZ = (math.random() - 0.5) * currentIntensity
		camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(offsetX), math.rad(offsetY), math.rad(offsetZ))
	end)
end

local function highlightVFXCard(paneName, variantName)
	local cards = vfxCardsByPane[paneName]
	if not cards then return end

	for _, card in ipairs(cards) do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			local cardVariant = getVFXVariantName(card)
			if cardVariant == variantName then
				stroke.Color = STYLE.GOLD
				stroke.Thickness = 3
			else
				stroke.Color = Color3.fromRGB(0, 0, 0)
				stroke.Thickness = 1.5
			end
		end
	end
end

local function showRightPaneForAbility(abilityName)
	local targetPane = RIGHT_PANE_BY_ABILITY[abilityName]
	for _, child in ipairs(abilityFrame:GetChildren()) do
		if child.Name:find("RightPane") then
			child.Visible = child.Name == targetPane
		end
	end

	local equippedVFX = localPlayer:GetAttribute(getVFXAttributeKey(abilityName)) or "Default"
	if targetPane then
		highlightVFXCard(targetPane, equippedVFX)
	end
end

local function highlightAbilityCard(abilityName)
	for name, card in pairs(abilityCards) do
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			if name == abilityName then
				local data = AbilityData[abilityName]
				stroke.Color = (data and data.Color) or STYLE.GOLD
				stroke.Thickness = 3
			else
				stroke.Color = Color3.fromRGB(0, 0, 0)
				stroke.Thickness = 1.5
			end
		end
	end
end

local function selectAbility(abilityName)
	local data = AbilityData[abilityName]
	if not data then return end

	selectedAbility = abilityName
	highlightAbilityCard(abilityName)
	showRightPaneForAbility(abilityName)
end

local function equipSelectedVFX(abilityName, vfxCard)
	local variantName = getVFXVariantName(vfxCard)
	local price = parsePrice(vfxCard)
	if variantName == "Default" then
		price = 0
	end
	local ownedKey = "OwnVFX_" .. abilityName:gsub(" ", "_") .. "_" .. variantName:gsub(" ", "_")

	if price > 0 and localPlayer:GetAttribute(ownedKey) ~= true then
		local leaderstats = localPlayer:FindFirstChild("leaderstats")
		local coins = leaderstats and leaderstats:FindFirstChild("Coins")
		if not coins or coins.Value < price then
			showToast("Not enough coins!")
			return false
		end
	end

	PurchaseAbilityVFXEvent:FireServer(abilityName, variantName, price)

	local equippedKey = getVFXAttributeKey(abilityName)
	local done = false
	local conn
	conn = localPlayer:GetAttributeChangedSignal(equippedKey):Connect(function()
		done = true
	end)
	task.delay(1, function()
		done = true
	end)
	while not done do
		task.wait()
	end
	if conn then conn:Disconnect() end

	local equipped = localPlayer:GetAttribute(equippedKey)
	if equipped == variantName then
		selectedVFXByAbility[abilityName] = variantName
		local paneName = RIGHT_PANE_BY_ABILITY[abilityName]
		if paneName then
			highlightVFXCard(paneName, variantName)
		end
		return true
	end
	return false
end

local function setupNavigate()
	-- Keep the same Navigate kit as Rewards/Store (scale padding = even gaps between tabs)
	navigate.Size = UDim2.new(0.250015765, 0, 0.100123651, 0)
	navigate.Position = UDim2.new(0.5, 0, -0.048, 0)
	navigate.AnchorPoint = Vector2.new(0.5, 0.5)
	navigate.BackgroundTransparency = 1

	local layout = navigate:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Parent = navigate
	end
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.2, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Wraps = true

	local tabOrder = { Ability = 1, DASH = 2, DEATH = 3 }
	for name, button in pairs(tabButtons) do
		button.Size = UDim2.new(0.801111817, 0, 1, 0)
		button.AnchorPoint = Vector2.new(0, 0)
		button.LayoutOrder = tabOrder[name] or 0
	end

	if closeBtn and closeBtn:IsA("GuiObject") then
		closeBtn.AnchorPoint = Vector2.new(1, 0.5)
		closeBtn.Position = UDim2.new(0.985, 0, 0.5, 0)
		closeBtn.Size = UDim2.new(0.055, 0, 0.62, 0)
	end
end

local function bindVFXCards()
	if vfxBound then return end
	vfxBound = true

	for paneName, abilityName in pairs({
		RightPanePunch_VFX = "Grid Punch",
		RightPaneDashStrike_VFX = "Dash Strike",
		RightPaneShield_VFX = "Shield Bubble",
		RightPaneMine_VFX = "Proximity Mine",
		RightPaneShockwave_VFX = "Shockwave",
	}) do
		local pane = abilityFrame:FindFirstChild(paneName)
		if not pane then continue end

		pane.BackgroundTransparency = 1

		local cards = {}
		for _, child in ipairs(pane:GetChildren()) do
			if child.Name == "AbilityVFX" and child:IsA("GuiButton") then
				table.insert(cards, child)
			end
		end
		vfxCardsByPane[paneName] = cards

		for _, vfxCard in ipairs(cards) do

			local playBtn = vfxCard:FindFirstChild("Play")
			local buyBtn = vfxCard:FindFirstChild("Buy")

			if playBtn and playBtn:IsA("GuiButton") then
				playBtn.Activated:Connect(function()
					selectAbility(abilityName)
					previewAbilityVFX(abilityName)
				end)
			end

			if buyBtn and buyBtn:IsA("GuiButton") then
				buyBtn.Activated:Connect(function()
					selectAbility(abilityName)
					if equipSelectedVFX(abilityName, vfxCard) then
						showToast("Equipped " .. getVFXVariantName(vfxCard) .. " VFX")
					end
				end)
			end

			vfxCard.Activated:Connect(function()
				selectAbility(abilityName)
			end)
		end
	end
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
	clearGeneratedCards()

	local template = abilityGrid:FindFirstChild("AbilityCardTemplate") or abilityGrid:FindFirstChildWhichIsA("ImageButton")
	if not template then
		warn("[Loadout] Missing AbilityCardTemplate in LeftPane_Abilities")
		return
	end

	template.Name = "AbilityCardTemplate"
	template.Visible = false

	for abilityName, data in pairs(AbilityData) do
		if type(data) ~= "table" then continue end

		local card = template:Clone()
		card.Name = abilityName
		card.Visible = true
		card.LayoutOrder = data.Cost or 0
		UIHelpers.setAbilityImage(card, abilityName)
		card.Parent = abilityGrid

		card.Activated:Connect(function()
			selectAbility(abilityName)
		end)
		UIHelpers.bindButtonHover(card)

		abilityCards[abilityName] = card
	end
end

local function setTab(tabName)
	if not tabFrames[tabName] then
		tabName = "Ability"
	end
	currentTab = tabName

	for name, frame in pairs(tabFrames) do
		frame.Visible = name == tabName
	end

	if tabName == "Ability" then
		if selectedAbility then
			showRightPaneForAbility(selectedAbility)
		else
			showRightPaneForAbility("Grid Punch")
		end
	end

	for name, button in pairs(tabButtons) do
		local active = name == tabName
		-- Match Ability kit: white face + white extruded Frame
		button.BackgroundColor3 = active and Color3.new(1, 1, 1) or Color3.fromRGB(76, 78, 99)
		local frame = button:FindFirstChild("Frame")
		if frame then
			frame.BackgroundColor3 = Color3.new(1, 1, 1)
			frame.BackgroundTransparency = active and 0 or 0.35
		end
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

local function setLoadoutVisible(isVisible, tabName)
	if isVisible and not canShowLobbyPanel() then
		return
	end

	if isVisible then
		setTab(tabName or "Ability")
		UIHelpers.animatePanelOpen(loadoutFrame)
		if selectedAbility then
			selectAbility(selectedAbility)
		end
	else
		UIHelpers.animatePanelClose(loadoutFrame)
	end
end

bindVFXCards()
setupNavigate()
buildAbilityGrid()

local preferred = localPlayer:GetAttribute("EquippedAbility")
if type(preferred) ~= "string" or not AbilityData[preferred] then
	preferred = "Grid Punch"
end
selectAbility(preferred)

for tabName, button in pairs(tabButtons) do
	button.Activated:Connect(function()
		setTab(tabName)
	end)
end

closeBtn.Activated:Connect(function()
	setLoadoutVisible(false)
end)

toggleLoadout.Event:Connect(function(tabName)
	if tabName == "Close" then
		setLoadoutVisible(false)
		return
	end
	if typeof(tabName) == "string" then
		if loadoutFrame.Visible and currentTab == tabName then
			setLoadoutVisible(false)
		else
			setLoadoutVisible(true, tabName)
		end
	else
		setLoadoutVisible(not loadoutFrame.Visible, "Ability")
	end
end)

localPlayer:GetAttributeChangedSignal("EquippedAbility"):Connect(function()
	local equipped = localPlayer:GetAttribute("EquippedAbility")
	-- Only sync browse view when loadout is open; left pane does not change equipped ability.
	if loadoutFrame.Visible and type(equipped) == "string" and AbilityData[equipped] then
		selectAbility(equipped)
	end
end)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	if localPlayer:GetAttribute("InArena") == true then
		setLoadoutVisible(false)
	end
end)

UIHelpers.bindHoversUnder(navigate)
UIHelpers.bindButtonHover(closeBtn)
UIHelpers.bindHoversUnder(abilityFrame)

loadoutFrame.Visible = false
setTab("Ability")
