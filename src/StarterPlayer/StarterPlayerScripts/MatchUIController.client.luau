local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local LOBBY_MENU_BUTTONS = {
	"PouchButton",
	"StoreButton",
	"TrophyButton",
	"TaskButton",
	"SettingButton",
}

local function getMobileGui()
	return playerGui:FindFirstChild("MobileGui")
end

local function getMenuGui()
	return playerGui:FindFirstChild("MenuGui")
end

local function getLobbyControlsGui()
	return playerGui:FindFirstChild("LobbyControlsGui")
end

local function getKillFeedGui()
	return playerGui:FindFirstChild("KillFeedGui")
end

local function setVisible(instance, visible)
	if instance then
		instance.Visible = visible
	end
end

local function shouldShowMobileControls()
	return UserInputService.TouchEnabled
end

local function restoreFollowCamera(character)
	local camera = workspace.CurrentCamera
	if not camera or not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid then
		camera.CameraSubject = humanoid
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function ensureFollowCamera()
	local character = localPlayer.Character
	if character then
		restoreFollowCamera(character)
	end
end

local function updateMatchUI()
	local inArena = localPlayer:GetAttribute("InArena") == true
	local eliminated = localPlayer:GetAttribute("IsEliminated") == true
	local inMatch = inArena and not eliminated
	local showMobile = shouldShowMobileControls()

	local mobileGui = getMobileGui()
	if mobileGui then
		mobileGui.Enabled = true
		local abilityButton = mobileGui:FindFirstChild("AbilityButton")
		local dashButton = mobileGui:FindFirstChild("DashButton")
		setVisible(abilityButton, showMobile and inMatch)
		setVisible(dashButton, showMobile and not eliminated)
	end

	local menuGui = getMenuGui()
	if menuGui then
		for _, buttonName in ipairs(LOBBY_MENU_BUTTONS) do
			local button = menuGui:FindFirstChild(buttonName)
			setVisible(button, not inMatch)
			if button then
				local clickTarget = button:FindFirstChild("ClickTarget")
				setVisible(clickTarget, not inMatch)
			end
		end
		local currentAbilityFrame = menuGui:FindFirstChild("Current Ablilty")
		setVisible(currentAbilityFrame, not inMatch)
		if currentAbilityFrame then
			local currentAbilityBtn = currentAbilityFrame:FindFirstChild("CurrentAbility")
			setVisible(currentAbilityBtn, not inMatch)
			if currentAbilityBtn then
				local clickTarget = currentAbilityBtn:FindFirstChild("ClickTarget")
				setVisible(clickTarget, not inMatch)
			end
		end
	end

	local lobbyControls = getLobbyControlsGui()
	if lobbyControls then
		lobbyControls.Enabled = not inMatch
	end

	local killFeedGui = getKillFeedGui()
	if killFeedGui then
		killFeedGui.Enabled = inArena
	end
end

local function hookPlayerGui()
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "MobileGui" or child.Name == "MenuGui" or child.Name == "LobbyControlsGui" or child.Name == "KillFeedGui" then
			task.defer(updateMatchUI)
		end
	end)
end

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	updateMatchUI()
	if localPlayer:GetAttribute("InArena") ~= true then
		task.defer(ensureFollowCamera)
	end
end)
localPlayer:GetAttributeChangedSignal("IsEliminated"):Connect(function()
	updateMatchUI()
	if localPlayer:GetAttribute("IsEliminated") == true then
		task.defer(ensureFollowCamera)
	end
end)
localPlayer.CharacterAdded:Connect(function(character)
	restoreFollowCamera(character)
end)
if localPlayer.Character then
	task.defer(function()
		restoreFollowCamera(localPlayer.Character)
	end)
end
UserInputService.LastInputTypeChanged:Connect(updateMatchUI)

hookPlayerGui()
task.defer(updateMatchUI)
