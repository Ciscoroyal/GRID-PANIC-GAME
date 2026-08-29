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
		pcall(function()
			guiObject.Interactable = true
		end)
		return guiObject
	end

	local existing = guiObject:FindFirstChild("ClickTarget")
	if existing and existing:IsA("GuiButton") then
		existing.Active = true
		pcall(function()
			existing.Interactable = true
		end)
		return existing
	end

	local clickTarget = Instance.new("TextButton")
	clickTarget.Name = "ClickTarget"
	clickTarget.BackgroundTransparency = 1
	clickTarget.Text = ""
	clickTarget.Size = UDim2.fromScale(1, 1)
	clickTarget.Position = UDim2.fromScale(0, 0)
	clickTarget.ZIndex = (guiObject.ZIndex or 1) + 10
	clickTarget.Active = true
	clickTarget.AutoButtonColor = false
	pcall(function()
		clickTarget.Interactable = true
	end)
	clickTarget.Parent = guiObject
	return clickTarget
end

local function bindClickable(guiObject, callback)
	if not guiObject then
		return
	end

	-- Remove stale overlays from earlier experiments
	local stale = guiObject:FindFirstChild("ClickTarget")
	if stale and guiObject:IsA("GuiButton") then
		stale:Destroy()
	end

	local target = ensureClickTarget(guiObject)
	if not target then
		return
	end

	for _, desc in ipairs(guiObject:GetDescendants()) do
		if desc:IsA("GuiObject") and desc ~= target then
			desc.Active = false
			pcall(function()
				desc.Interactable = false
			end)
		end
	end

	-- Keep a real hit surface even when the image is empty
	if target:IsA("GuiButton") then
		if target.BackgroundTransparency >= 1 then
			target.BackgroundTransparency = 0.99
		end
		target.Active = true
		pcall(function()
			target.Interactable = true
		end)
	end

	local lastFire = 0
	local function guarded()
		local now = os.clock()
		if now - lastFire < 0.25 then
			return
		end
		lastFire = now
		callback()
	end
	-- Activated (touch/gamepad) + MouseButton1Click (mouse) with shared debounce
	target.Activated:Connect(guarded)
	if target:IsA("GuiButton") then
		target.MouseButton1Click:Connect(guarded)
	end

	UIHelpers.bindButtonHover(target, { visual = guiObject })
end

local function canOpenLobbyPanels()
	-- Lobby, intermission, practice, or eliminated → allow
	if localPlayer:GetAttribute("InPractice") == true then
		return true
	end
	if localPlayer:GetAttribute("InArena") ~= true then
		return true
	end
	if localPlayer:GetAttribute("IsEliminated") == true then
		return true
	end
	-- Actively surviving in the arena → lock lobby menus
	return false
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
end

local function openCurrentAbility()
	if not canOpenAbilityMenu() then
		return
	end
	toggleLoadout:Fire("Close")
	toggleStore:Fire("Close")
	toggleRewards:Fire("Close")
	toggleSettings:Fire("Close")
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

local function updateMenuButtonsVisibility()
	local menuButtons = menuGui:FindFirstChild("Buttons")
	if not menuButtons then
		return
	end
	local inMatch = localPlayer:GetAttribute("InArena") == true
		and localPlayer:GetAttribute("IsEliminated") ~= true
	menuButtons.Visible = not inMatch
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

--[[
	CurrencyBurstController marks a counter "BurstOwned" when it is animating
	the number up as the icons land. We must not snap the label to the new
	total underneath it, or the number jumps ahead and then falls back.
]]
local function bindCurrency(frame, getValue)
	local valueObject = getValue()
	if valueObject then
		if frame:GetAttribute("BurstOwned") == true then
			return
		end
		setNestedTitle(frame, valueObject.Value)
		valueObject:GetPropertyChangedSignal("Value"):Connect(function()
			if frame:GetAttribute("BurstOwned") == true then
				return
			end
			setNestedTitle(frame, valueObject.Value)
		end)
	end
end

-- Bind lobby strip FIRST (before any WaitForChild that can yield)
bindClickable(menuGui:FindFirstChild("PouchButton"), openLoadout)
bindClickable(menuGui:FindFirstChild("StoreButton"), openStore)
bindClickable(menuGui:FindFirstChild("TrophyButton"), openRewards)
bindClickable(menuGui:FindFirstChild("SettingButton"), openSettings)

local menuButtons = menuGui:FindFirstChild("Buttons")
if menuButtons then
	-- Active=false is fine (parent doesn't need to sink input).
	-- Do NOT set Interactable=false — that disables all child buttons.
	menuButtons.Active = false
	pcall(function()
		menuButtons.Interactable = true
	end)
	bindClickable(menuButtons:FindFirstChild("Loadout"), openLoadout)
	bindClickable(menuButtons:FindFirstChild("Store"), openStore)
	bindClickable(menuButtons:FindFirstChild("Rewards"), openRewards)
	bindClickable(menuButtons:FindFirstChild("Setting"), openSettings)
end

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
	updateMenuButtonsVisibility()
	if localPlayer:GetAttribute("InArena") == true then
		closeAllPanels()
	end
end)

localPlayer:GetAttributeChangedSignal("IsEliminated"):Connect(updateMenuButtonsVisibility)

localPlayer:GetAttributeChangedSignal("FriendBoostPercent"):Connect(updateFriendBoost)
updateFriendBoost()
updateMenuButtonsVisibility()

local friendBoostFrame = menuGui:FindFirstChild("FriendBoost")
if friendBoostFrame then
	local inviteBtn = friendBoostFrame:FindFirstChild("FriendButton")
	if inviteBtn and inviteBtn:IsA("GuiButton") then
		inviteBtn.MouseButton1Click:Connect(function()
			pcall(function()
				SocialService:PromptGameInvite(localPlayer)
			end)
		end)
		UIHelpers.bindButtonHover(inviteBtn, { visual = friendBoostFrame })
	end
end

-- Currency binds last — these WaitForChild calls must not delay button wiring
task.spawn(function()
	bindCurrency(menuGui:WaitForChild("Money"), function()
		local leaderstats = localPlayer:WaitForChild("leaderstats", 15)
		return leaderstats and leaderstats:WaitForChild("Coins", 15)
	end)

	bindCurrency(menuGui:WaitForChild("Fans"), function()
		return localPlayer:WaitForChild("AllTimeFans", 15)
	end)
end)
