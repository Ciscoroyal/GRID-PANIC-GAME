local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))
local survivalTimeValue = ReplicatedStorage:WaitForChild("SurvivalTime")

local localPlayer = Players.LocalPlayer
local menuGui = script.Parent
local playerGui = localPlayer:WaitForChild("PlayerGui")

local loadoutGui = playerGui:WaitForChild("LoadoutGui")
local toggleLoadout = loadoutGui:WaitForChild("ToggleLoadout")

local storeGui = playerGui:WaitForChild("StoreGui")
local toggleStore = storeGui:WaitForChild("ToggleStore")

local rewardsGui = playerGui:WaitForChild("RewardsGui")
local toggleRewards = rewardsGui:WaitForChild("ToggleRewards")

local settingsGui = playerGui:WaitForChild("SettingsGui")
local toggleSettings = settingsGui:WaitForChild("ToggleSettings")

local currentAbilityGui = playerGui:WaitForChild("CurrentAbilityGui")
local toggleCurrentAbility = currentAbilityGui:WaitForChild("ToggleCurrentAbility")

local questsGui = playerGui:WaitForChild("QuestsGui")
local toggleQuests = questsGui:WaitForChild("ToggleQuests")

local function setNestedTitle(frame, text)
	local title = frame:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = tostring(text)
	end
	local innerTitle = title and title:FindFirstChild("Title")
	if innerTitle and innerTitle:IsA("TextLabel") then
		innerTitle.Text = tostring(text)
	end
end

local function ensureClickTarget(guiObject)
	if not guiObject then
		return nil
	end
	if guiObject:IsA("GuiButton") then
		guiObject.Active = true
		return guiObject
	end

	local existing = guiObject:FindFirstChild("ClickTarget")
	if existing and existing:IsA("GuiButton") then
		return existing
	end

	local clickTarget = Instance.new("TextButton")
	clickTarget.Name = "ClickTarget"
	clickTarget.BackgroundTransparency = 1
	clickTarget.Text = ""
	clickTarget.Size = UDim2.fromScale(1, 1)
	clickTarget.Position = UDim2.fromScale(0, 0)
	clickTarget.ZIndex = (guiObject.ZIndex or 1) + 5
	clickTarget.Active = true
	clickTarget.AutoButtonColor = false
	clickTarget.Parent = guiObject
	return clickTarget
end

local function bindClickable(guiObject, callback)
	if not guiObject then
		return
	end

	-- Reuse an existing ClickTarget so we don't miss clicks on overlays.
	local existingTarget = guiObject:FindFirstChild("ClickTarget")
	if existingTarget and existingTarget:IsA("GuiButton") then
		existingTarget.Active = true
		existingTarget.Activated:Connect(callback)
		return
	end

	local target = ensureClickTarget(guiObject)
	if not target then
		return
	end
	target.Activated:Connect(callback)
end

local function canOpenLobbyPanels()
	if localPlayer:GetAttribute("InArena") ~= true then
		return true
	end
	local countdown = survivalTimeValue.Value
	return countdown >= 1 and countdown <= 15
end

local function canOpenAbilityMenu()
	local inArena = localPlayer:GetAttribute("InArena") == true
	local eliminated = localPlayer:GetAttribute("IsEliminated") == true
	local inMatch = inArena and not eliminated
	return not inMatch
end

local function closeAllPanels()
	toggleLoadout:Fire("Close")
	toggleStore:Fire("Close")
	toggleRewards:Fire("Close")
	toggleSettings:Fire("Close")
	toggleCurrentAbility:Fire("Close")
	toggleQuests:Fire("Close")
end

local function openQuests()
	if not canOpenLobbyPanels() then
		return
	end
	toggleLoadout:Fire("Close")
	toggleStore:Fire("Close")
	toggleRewards:Fire("Close")
	toggleSettings:Fire("Close")
	toggleCurrentAbility:Fire("Close")
	toggleQuests:Fire("Open")
end

local function openCurrentAbility()
	if not canOpenAbilityMenu() then
		return
	end
	toggleLoadout:Fire("Close")
	toggleStore:Fire("Close")
	toggleRewards:Fire("Close")
	toggleSettings:Fire("Close")
	toggleQuests:Fire("Close")
	toggleCurrentAbility:Fire("Open")
end

local function openLoadout()
	if not canOpenLobbyPanels() then
		return
	end
	toggleStore:Fire("Close")
	toggleRewards:Fire("Close")
	toggleSettings:Fire("Close")
	toggleCurrentAbility:Fire("Close")
	toggleQuests:Fire("Close")
	toggleLoadout:Fire("Ability")
end

local function openStore()
	if not canOpenLobbyPanels() then
		return
	end
	toggleLoadout:Fire("Close")
	toggleRewards:Fire("Close")
	toggleSettings:Fire("Close")
	toggleCurrentAbility:Fire("Close")
	toggleQuests:Fire("Close")
	toggleStore:Fire("SHOP")
end

local function openRewards()
	if not canOpenLobbyPanels() then
		return
	end
	toggleLoadout:Fire("Close")
	toggleStore:Fire("Close")
	toggleSettings:Fire("Close")
	toggleCurrentAbility:Fire("Close")
	toggleQuests:Fire("Close")
	toggleRewards:Fire("Trophy")
end

local function openSettings()
	if not canOpenLobbyPanels() then
		return
	end
	toggleLoadout:Fire("Close")
	toggleStore:Fire("Close")
	toggleRewards:Fire("Close")
	toggleCurrentAbility:Fire("Close")
	toggleQuests:Fire("Close")
	toggleSettings:Fire("Open")
end

local function updateFriendBoost()
	local friendBoost = menuGui:FindFirstChild("FriendBoost")
	if not friendBoost then
		return
	end

	local inLobby = localPlayer:GetAttribute("InArena") ~= true
	friendBoost.Visible = inLobby

	local title = friendBoost:FindFirstChild("Title")
	local boostPercent = localPlayer:GetAttribute("FriendBoostPercent") or 0
	if title and title:IsA("TextLabel") then
		title.Text = "Friend Boost\n+" .. boostPercent .. "% COINS"
	end
end

local function updateCurrentAbilityIcon()
	local frame = menuGui:FindFirstChild("Current Ablilty")
	if not frame then
		return
	end

	local button = frame:FindFirstChild("CurrentAbility")
	if not button then
		return
	end

	local equipped = localPlayer:GetAttribute("EquippedAbility")
	if type(equipped) == "string" and equipped ~= "" and equipped ~= "None" then
		UIHelpers.setAbilityImage(button, equipped)
		button.ImageTransparency = 0
	else
		button.Image = ""
		button.ImageTransparency = 0.35
	end
end

local function bindCurrency(frame, getValue)
	local valueObject = getValue()
	if valueObject then
		setNestedTitle(frame, valueObject.Value)
		valueObject:GetPropertyChangedSignal("Value"):Connect(function()
			setNestedTitle(frame, valueObject.Value)
		end)
	end
end

bindCurrency(menuGui:WaitForChild("Money"), function()
	local leaderstats = localPlayer:WaitForChild("leaderstats", 15)
	return leaderstats and leaderstats:WaitForChild("Coins", 15)
end)

bindCurrency(menuGui:WaitForChild("Fans"), function()
	return localPlayer:WaitForChild("AllTimeFans", 15)
end)

localPlayer:GetAttributeChangedSignal("FriendBoostPercent"):Connect(updateFriendBoost)
updateFriendBoost()

local friendBoostFrame = menuGui:FindFirstChild("FriendBoost")
if friendBoostFrame then
	local inviteBtn = friendBoostFrame:FindFirstChild("FriendButton")
	if inviteBtn and inviteBtn:IsA("GuiButton") then
		inviteBtn.MouseButton1Click:Connect(function()
			pcall(function()
				SocialService:PromptGameInvite(localPlayer)
			end)
		end)
	end
end

bindClickable(menuGui:FindFirstChild("TaskButton"), openQuests)
bindClickable(menuGui:FindFirstChild("PouchButton"), openLoadout)
bindClickable(menuGui:FindFirstChild("StoreButton"), openStore)
bindClickable(menuGui:FindFirstChild("TrophyButton"), openRewards)
bindClickable(menuGui:FindFirstChild("SettingButton"), openSettings)

local currentAbilityFrame = menuGui:FindFirstChild("Current Ablilty")
if currentAbilityFrame then
	local currentAbilityBtn = currentAbilityFrame:FindFirstChild("CurrentAbility")
	if currentAbilityBtn then
		bindClickable(currentAbilityBtn, openCurrentAbility)
	end
end

updateCurrentAbilityIcon()
localPlayer:GetAttributeChangedSignal("EquippedAbility"):Connect(updateCurrentAbilityIcon)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	updateFriendBoost()
	if localPlayer:GetAttribute("InArena") == true then
		closeAllPanels()
	end
end)
