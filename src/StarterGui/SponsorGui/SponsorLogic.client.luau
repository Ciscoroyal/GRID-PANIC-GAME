local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local gui = script.Parent

local STYLE = {
	PANEL = Color3.fromRGB(42, 44, 56),
	ACCENT = Color3.fromRGB(0, 170, 85),
	GOLD = Color3.fromRGB(255, 200, 50),
	TEXT = Color3.fromRGB(245, 245, 245),
	MUTED = Color3.fromRGB(165, 170, 185),
	DANGER = Color3.fromRGB(210, 60, 60),
}

-- Wait for the original UI elements to load
local originalListFrame = gui:WaitForChild("ListFrame")
local originalAskFrame = gui:WaitForChild("AskFrame")

local sponsorEvent = ReplicatedStorage:WaitForChild("SponsorEvent")
local sponsorResultEvent = ReplicatedStorage:WaitForChild("SponsorResultEvent")
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")
local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))
local hasSponsoredThisRound = false
local eliminatedThisRound = false
local liveMenuConnections = {}
local pendingCheerRow = nil

local function ensureCorner(parent, radius)
	local corner = parent:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = parent
	end
	corner.CornerRadius = radius
end

local function ensureStroke(parent, thickness, transparency)
	local stroke = parent:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = thickness
	stroke.Transparency = transparency
end

-- =================================================================
-- THE ULTIMATE SHIELD BYPASS & CANVAS FIX
-- =================================================================
local masterGui = localPlayer.PlayerGui:FindFirstChild("MasterSponsorGui")
if not masterGui then
	masterGui = Instance.new("ScreenGui")
	masterGui.Name = "MasterSponsorGui"
	masterGui.DisplayOrder = 50
	masterGui.ResetOnSpawn = false
	masterGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	masterGui.Parent = localPlayer.PlayerGui
end

for _, child in ipairs(masterGui:GetChildren()) do
	if child.Name == "ListFrame" or child.Name == "AskFrame" then
		child:Destroy()
	end
end

originalListFrame.Parent = masterGui
originalAskFrame.Parent = masterGui

local listFrame = masterGui:WaitForChild("ListFrame")
local scrollingFrame = listFrame:WaitForChild("PlayerListScroll")
local rowTemplate = scrollingFrame:WaitForChild("PlayerRowTemplate")
local askFrame = masterGui:WaitForChild("AskFrame")

rowTemplate.Visible = false

scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollingFrame.Active = true

local listLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
if not listLayout then
	listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollingFrame
end

local yesBtn = askFrame:WaitForChild("YesButton")
local noBtn = askFrame:WaitForChild("NoButton")
local closeBtn = listFrame:WaitForChild("Top"):WaitForChild("Close")

listFrame.Visible = false
askFrame.Visible = false

local function countArenaSurvivors()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer and player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true and player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				count += 1
			end
		end
	end
	return count
end

-- =========================================================
-- HELPER: Safely close the menu and stop tracking deaths
-- =========================================================
local function clearScrollContent()
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child ~= rowTemplate and not child:IsA("UILayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function showCheerToast(message)
	local existing = listFrame:FindFirstChild("CheerToast")
	if existing then
		existing:Destroy()
	end

	local toast = Instance.new("TextLabel")
	toast.Name = "CheerToast"
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 0.92, 0)
	toast.Size = UDim2.new(0.8, 0, 0, 36)
	toast.BackgroundColor3 = STYLE.PANEL
	toast.BackgroundTransparency = 0.1
	toast.TextColor3 = STYLE.DANGER
	toast.Font = Enum.Font.GothamBold
	toast.TextSize = 16
	toast.TextWrapped = true
	toast.Text = message
	toast.Parent = listFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = toast

	task.delay(2, function()
		if toast.Parent then
			toast:Destroy()
		end
	end)
end

local function closeSponsorTerminal()
	listFrame.Visible = false
	for _, connection in ipairs(liveMenuConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(liveMenuConnections)
end

local function createSurvivorRow(player)
	local humanoid = player.Character.Humanoid
	local ability = player:GetAttribute("EquippedAbility") or "None"

	local row = rowTemplate:Clone()
	row.Name = player.Name .. "_Row"
	row.Visible = true
	row.Parent = scrollingFrame

	row.NameText.Text = player.DisplayName
	UIHelpers.setAvatarImage(row.AvatarImage, player.UserId)
	UIHelpers.setAbilityImage(row.AbilityImage, ability)

	local deathConn = humanoid.Died:Connect(function()
		if row.Parent then
			row:Destroy()
		end
	end)
	table.insert(liveMenuConnections, deathConn)

	local defaultCheerText = row.CheerButton.Title.Text
	row:SetAttribute("DefaultCheerText", defaultCheerText)

	row.CheerButton.Activated:Connect(function()
		if hasSponsoredThisRound then
			return
		end
		pendingCheerRow = row
		row.CheerButton.Title.Text = "..."
		sponsorEvent:FireServer(player)
	end)
end

sponsorResultEvent.OnClientEvent:Connect(function(success, message)
	if success then
		hasSponsoredThisRound = true
		if pendingCheerRow and pendingCheerRow.Parent then
			pendingCheerRow.CheerButton.Title.Text = "CHEERED!"
		end
		pendingCheerRow = nil
		task.wait(0.6)
		closeSponsorTerminal()
	else
		if pendingCheerRow and pendingCheerRow.Parent then
			local title = pendingCheerRow.CheerButton:FindFirstChild("Title")
			if title and title:IsA("TextLabel") then
				title.Text = pendingCheerRow:GetAttribute("DefaultCheerText") or "CHEER"
			end
		end
		pendingCheerRow = nil
		if message and message ~= "" then
			showCheerToast(message)
		end
	end
end)

-- =========================================================
--  (Now with Live Updates!)
-- =========================================================
local LOBBY_ZONE_RADIUS = 45
local BOOTH_ZONE_RADIUS = 18

local function getFlatDistance(posA, posB)
	return (Vector3.new(posA.X, 0, posA.Z) - Vector3.new(posB.X, 0, posB.Z)).Magnitude
end

local function getArcadeBooths()
	local booths = {}
	for _, inst in ipairs(workspace:GetChildren()) do
		if inst.Name == "Arcade Machine" and inst:IsA("BasePart") then
			table.insert(booths, inst)
		end
	end
	return booths
end

local function isAtSponsorBooth()
	local character = localPlayer.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, booth in ipairs(getArcadeBooths()) do
		if getFlatDistance(root.Position, booth.Position) <= BOOTH_ZONE_RADIUS then
			return true
		end
	end
	return false
end

local function isPhysicallyInLobby()
	if isAtSponsorBooth() then
		return true
	end

	local character = localPlayer.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local lobbySpawn = workspace:FindFirstChild("LobbySpawn")
	if lobbySpawn and lobbySpawn:IsA("BasePart") then
		return getFlatDistance(root.Position, lobbySpawn.Position) <= LOBBY_ZONE_RADIUS
	end

	return false
end

local function isInLobby()
	return isPhysicallyInLobby() or localPlayer:GetAttribute("InArena") ~= true
end

local function isMatchActive()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true then
			return true
		end
	end
	return false
end

local function canUseSponsorUi()
	if isPhysicallyInLobby() and isMatchActive() then
		return true
	end
	if localPlayer:GetAttribute("CanSponsorThisRound") == true then return true end
	if eliminatedThisRound then return true end
	if localPlayer:GetAttribute("IsEliminated") == true then return true end
	return false
end

local function openSponsorTerminal()
	-- 1. ALWAYS open the UI now! No early returns blocking it.
	askFrame.Visible = false
	listFrame.Visible = true

	clearScrollContent()

	for _, connection in ipairs(liveMenuConnections) do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(liveMenuConnections)

	-- Helper function to easily slap text on the screen
	local function showMessage(text)
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 60)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = text
		emptyLabel.TextColor3 = STYLE.MUTED 
		emptyLabel.Font = Enum.Font.GothamBold
		emptyLabel.TextSize = 20
		emptyLabel.Parent = scrollingFrame
	end

	-- 2. Check the rules and display the proper message instead of closing
	if not canUseSponsorUi() then
		showMessage("WAITING FOR NEXT ROUND...")
		return
	end

	if hasSponsoredThisRound then
		showMessage("YOU ALREADY CHEERED THIS ROUND!")
		return
	end

	-- 3. If they pass the checks, load the players!
	local survivorCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer and player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true and player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				survivorCount += 1
				createSurvivorRow(player)
			end
		end
	end

	-- 4. Just in case a match is active but everyone died exactly as they clicked
	if survivorCount == 0 then
		showMessage("NO ELIGIBLE SURVIVORS")
	end
end

local refreshSponsorTerminal
refreshSponsorTerminal = function()
	if listFrame.Visible then
		openSponsorTerminal()
	end
end

local function bindPlayerRefreshSignals(player)
	player:GetAttributeChangedSignal("InArena"):Connect(refreshSponsorTerminal)
	player:GetAttributeChangedSignal("IsEliminated"):Connect(refreshSponsorTerminal)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayerRefreshSignals(player)
end

Players.PlayerAdded:Connect(function(player)
	bindPlayerRefreshSignals(player)
	refreshSponsorTerminal()
end)

Players.PlayerRemoving:Connect(refreshSponsorTerminal)

local showRollCall = ReplicatedStorage:WaitForChild("ShowRollCall")
showRollCall.OnClientEvent:Connect(refreshSponsorTerminal)

survivalTimeValue.Changed:Connect(function()
	if listFrame.Visible then
		refreshSponsorTerminal()
	end
end)

if closeBtn then
	closeBtn.Activated:Connect(function()
		closeSponsorTerminal()
	end)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, playerTrigged)
	if prompt.Name == "SponsorPrompt" and playerTrigged == localPlayer then
		openSponsorTerminal()
	end
end)

yesBtn.Activated:Connect(function()
	askFrame.Visible = false
	openSponsorTerminal()
end)

noBtn.Activated:Connect(function()
	askFrame.Visible = false
end)

local function maybeShowSponsorAsk()
	if not canUseSponsorUi() then return end
	if hasSponsoredThisRound then
		return
	end
	if countArenaSurvivors() <= 1 then
		return
	end

	askFrame.Visible = true
	task.delay(8, function()
		if askFrame.Visible then
			askFrame.Visible = false
		end
	end)
end

local function bindDeathHandler(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		if localPlayer:GetAttribute("InArena") == true or localPlayer:GetAttribute("CanSponsorThisRound") == true then
			eliminatedThisRound = true
			task.defer(maybeShowSponsorAsk)
		end
	end)
end

localPlayer.CharacterAdded:Connect(bindDeathHandler)
if localPlayer.Character then
	bindDeathHandler(localPlayer.Character)
end

local resetClientSponsors = ReplicatedStorage:WaitForChild("ResetClientSponsors")

resetClientSponsors.OnClientEvent:Connect(function()
	hasSponsoredThisRound = false
	pendingCheerRow = nil

	eliminatedThisRound = false	-- Also close the terminal if it happens to be open when the round fully resets
	closeSponsorTerminal() 
	print("Client: Menus unlocked for the new round!")
end)


localPlayer:GetAttributeChangedSignal("CanSponsorThisRound"):Connect(function()
	if localPlayer:GetAttribute("CanSponsorThisRound") == true then
		eliminatedThisRound = true
		task.defer(maybeShowSponsorAsk)
	end
end)

-- Arcade booth prompts handled via ProximityPromptService
