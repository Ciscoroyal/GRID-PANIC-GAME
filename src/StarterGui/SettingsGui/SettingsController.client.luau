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

local TweenService = game:GetService("TweenService")

local STYLE = {
	ON = Color3.fromRGB(60, 205, 110),
	OFF = Color3.fromRGB(96, 100, 120),
}

local TOGGLE_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--[[
	HitEffects is intentionally not listed: no script in the game reads that
	setting, so the row was a switch that did nothing. Add it back once the
	effect actually honours it.
]]
local SETTING_ROWS = {
	Setting_Music = "Music",
	Setting_SFX = "SFX",
	Setting_ScreenShake = "ScreenShake",
	Setting_WorldVFX = "WorldVFX",
}

PlayerSettings.ensure(localPlayer)

--[[
	The toggle is a dark base with a coloured "Pill" inset into it, and the
	label is the usual black shadow with the white face nested inside. Write
	both text layers or the shadow keeps the old word.
]]
local function setToggleVisual(toggle, enabled, animate)
	if not toggle then
		return
	end

	local pill = toggle:FindFirstChild("Pill")
	local target = enabled and STYLE.ON or STYLE.OFF
	if pill then
		if animate then
			TweenService:Create(pill, TOGGLE_INFO, { BackgroundColor3 = target }):Play()
		else
			pill.BackgroundColor3 = target
		end
	else
		toggle.BackgroundColor3 = target
	end

	local text = enabled and "ON" or "OFF"
	local host = pill or toggle
	local label = host:FindFirstChild("Shadow")
	if label then
		while label and label:IsA("TextLabel") do
			label.Text = text
			label = label:FindFirstChild("Title")
		end
	else
		toggle.Text = text
	end

	-- A small nudge on the pill so a tap has some weight to it.
	if animate then
		local scale = toggle:FindFirstChild("ToggleScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Name = "ToggleScale"
			scale.Parent = pill or toggle
		end
		scale.Scale = 0.88
		TweenService:Create(scale, TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
	end
end

local function refreshRow(row, key, animate)
	setToggleVisual(row:FindFirstChild("Face") and row.Face:FindFirstChild("Toggle")
		or row:FindFirstChild("Toggle"), PlayerSettings.get(key), animate)
end

local function refreshAll()
	for rowName, key in pairs(SETTING_ROWS) do
		local row = scrolling:FindFirstChild(rowName)
		if row then
			refreshRow(row, key)
		end
	end
end

--[[
	Rows drop in one after another when the panel opens. Cheap, but it turns a
	static list into something that feels built rather than pasted.
]]
local function staggerRowsIn()
	local ordered = {}
	for _, row in ipairs(scrolling:GetChildren()) do
		if row:IsA("Frame") then
			table.insert(ordered, row)
		end
	end
	table.sort(ordered, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)

	for index, row in ipairs(ordered) do
		local face = row:FindFirstChild("Face")
		if face then
			local scale = face:FindFirstChild("IntroScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Name = "IntroScale"
				scale.Parent = face
			end
			scale.Scale = 0.9
			face.BackgroundTransparency = 0.6
			task.delay(0.04 * index, function()
				if not face.Parent then
					return
				end
				TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Scale = 1,
				}):Play()
				TweenService:Create(face, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 0,
				}):Play()
			end)
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
		staggerRowsIn()
	else
		UIHelpers.animatePanelClose(settingsFrame)
	end
end

for rowName, key in pairs(SETTING_ROWS) do
	local row = scrolling:FindFirstChild(rowName)
	if not row then
		continue
	end

	local face = row:FindFirstChild("Face")
	local toggle = (face and face:FindFirstChild("Toggle")) or row:FindFirstChild("Toggle")
	if toggle and toggle:IsA("GuiButton") then
		toggle.Activated:Connect(function()
			PlayerSettings.toggle(key)
			refreshRow(row, key, true)
		end)
		UIHelpers.bindButtonHover(toggle)
	end

	PlayerSettings.onChanged(key, function()
		refreshRow(row, key, true)
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
