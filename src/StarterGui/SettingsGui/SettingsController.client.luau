local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))
local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

local localPlayer = Players.LocalPlayer
local settingsGui = script.Parent
local settingsFrame = settingsGui:WaitForChild("Settings")
local scrolling = settingsFrame:WaitForChild("ScrollingFrame")
local closeBtn = settingsFrame:WaitForChild("Top"):WaitForChild("Close")
local toggleSettings = settingsGui:WaitForChild("ToggleSettings")

local STYLE = {
	ON = Color3.fromRGB(0, 170, 85),
	OFF = Color3.fromRGB(90, 92, 105),
}

local SETTING_ROWS = {
	Setting_Music = "Music",
	Setting_SFX = "SFX",
	Setting_ScreenShake = "ScreenShake",
	Setting_HitEffects = "HitEffects",
	Setting_WorldVFX = "WorldVFX",
}

PlayerSettings.ensure(localPlayer)

local function setToggleVisual(toggle, enabled)
	if not toggle then
		return
	end
	toggle.Text = enabled and "ON" or "OFF"
	toggle.BackgroundColor3 = enabled and STYLE.ON or STYLE.OFF
end

local function refreshRow(row, key)
	setToggleVisual(row:FindFirstChild("Toggle"), PlayerSettings.get(key))
end

local function refreshAll()
	for rowName, key in pairs(SETTING_ROWS) do
		local row = scrolling:FindFirstChild(rowName)
		if row then
			refreshRow(row, key)
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

local function setSettingsVisible(isVisible)
	if isVisible and not canShowLobbyPanel() then
		return
	end

	if isVisible then
		refreshAll()
		UIHelpers.animatePanelOpen(settingsFrame, { duration = 0.3 })
	else
		UIHelpers.animatePanelClose(settingsFrame)
	end
end

for rowName, key in pairs(SETTING_ROWS) do
	local row = scrolling:FindFirstChild(rowName)
	if not row then
		continue
	end

	local toggle = row:FindFirstChild("Toggle")
	if toggle and toggle:IsA("GuiButton") then
		toggle.Activated:Connect(function()
			PlayerSettings.toggle(key)
			refreshRow(row, key)
		end)
		UIHelpers.bindButtonHover(toggle)
	end

	PlayerSettings.onChanged(key, function()
		refreshRow(row, key)
	end)
end

closeBtn.Activated:Connect(function()
	setSettingsVisible(false)
end)

toggleSettings.Event:Connect(function(action)
	if action == "Close" then
		setSettingsVisible(false)
		return
	end
	if action == "Open" then
		setSettingsVisible(true)
		return
	end
	setSettingsVisible(not settingsFrame.Visible)
end)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	if localPlayer:GetAttribute("InArena") == true then
		setSettingsVisible(false)
	end
end)

UIHelpers.bindButtonHover(closeBtn)

settingsFrame.Visible = false
refreshAll()
