local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer
local storeGui = script.Parent
local storeFrame = storeGui:WaitForChild("STORE")
local toggleStore = storeGui:WaitForChild("ToggleStore")

local navigate = storeFrame:WaitForChild("Navigate")
local closeBtn = storeFrame:WaitForChild("Top"):WaitForChild("Close")

local cratesBtn = navigate:WaitForChild("CRATES")
local shopBtn = navigate:WaitForChild("SHOP")

local cratesFrame = storeFrame:WaitForChild("CRATES")
local shopFrame = storeFrame:FindFirstChild("SHOP") or storeFrame:FindFirstChild("Shop")
local unusedShop = nil
if storeFrame:FindFirstChild("SHOP") and storeFrame:FindFirstChild("Shop") then
	unusedShop = storeFrame.Shop
end

local currentTab = "SHOP"

local function setTabHighlight(activeName)
	for _, button in ipairs({ cratesBtn, shopBtn }) do
		local frame = button:FindFirstChild("Frame")
		if frame then
			frame.BackgroundTransparency = button.Name == activeName and 0 or 0.35
		end
	end
end

local function setTab(tabName)
	if tabName ~= "CRATES" and tabName ~= "SHOP" then
		tabName = "SHOP"
	end
	currentTab = tabName

	cratesFrame.Visible = tabName == "CRATES"
	if shopFrame then
		shopFrame.Visible = tabName == "SHOP"
	end
	if unusedShop then
		unusedShop.Visible = false
	end

	setTabHighlight(tabName)
end

local function setStoreVisible(isVisible, tabName)
	if localPlayer:GetAttribute("InArena") == true then
		storeFrame.Visible = false
		return
	end

	if tabName and tabName ~= "Close" then
		setTab(tabName)
	end

	storeFrame.Visible = isVisible
	if isVisible then
		storeFrame.Position = UDim2.new(0.5, 0, 0.56, 0)
		storeFrame:TweenPosition(
			UDim2.new(0.5, 0, 0.5, 0),
			Enum.EasingDirection.Out,
			Enum.EasingStyle.Back,
			0.35,
			true
		)
	end
end

cratesBtn.Activated:Connect(function()
	setTab("CRATES")
end)
shopBtn.Activated:Connect(function()
	setTab("SHOP")
end)

closeBtn.Activated:Connect(function()
	setStoreVisible(false)
end)

toggleStore.Event:Connect(function(tabName)
	if tabName == "Close" then
		setStoreVisible(false)
		return
	end
	if typeof(tabName) == "string" then
		if storeFrame.Visible and currentTab == tabName then
			setStoreVisible(false)
		else
			setStoreVisible(true, tabName)
		end
	else
		setStoreVisible(not storeFrame.Visible, currentTab)
	end
end)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	if localPlayer:GetAttribute("InArena") == true then
		setStoreVisible(false)
	end
end)

storeFrame.Visible = false
setTab("SHOP")
