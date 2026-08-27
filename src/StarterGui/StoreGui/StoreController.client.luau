local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

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
		local active = button.Name == activeName
		-- Match Ability kit: white face + white extruded Frame
		button.BackgroundColor3 = active and Color3.new(1, 1, 1) or Color3.fromRGB(76, 78, 99)
		local frame = button:FindFirstChild("Frame")
		if frame then
			frame.BackgroundColor3 = Color3.new(1, 1, 1)
			frame.BackgroundTransparency = active and 0 or 0.35
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

local function setStoreVisible(isVisible, tabName)
	if isVisible and not canShowLobbyPanel() then
		return
	end

	if tabName and tabName ~= "Close" then
		setTab(tabName)
	end

	if isVisible then
		UIHelpers.animatePanelOpen(storeFrame)
	else
		UIHelpers.animatePanelClose(storeFrame)
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
