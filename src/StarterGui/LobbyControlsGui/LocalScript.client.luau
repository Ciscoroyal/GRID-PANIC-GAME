local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

local localPlayer = Players.LocalPlayer
local gui = script.Parent
local practiceBtn = gui:WaitForChild("PracticeButton")
local afkBtn = gui:WaitForChild("AFKButton")
local friendBtn = gui:FindFirstChild("FriendButton")
local afkEvent = ReplicatedStorage:WaitForChild("AFKEvent")
local practiceEvent = ReplicatedStorage:WaitForChild("PracticeEvent")

local STYLE = {
	RETURN = Color3.fromRGB(255, 120, 0),
	AFK_ON = Color3.fromRGB(210, 60, 60),
	AFK_PENDING = Color3.fromRGB(230, 160, 40),
	FRIEND = Color3.fromRGB(60, 120, 255),
}

-- Keep the Studio-authored idle greens; only swap colors when toggled on.
local function getIdleColor(button)
	local frame = button:FindFirstChild("Frame")
	if frame then
		return frame.BackgroundColor3
	end
	return button.BackgroundColor3
end

local practiceIdleColor = getIdleColor(practiceBtn)
local afkIdleColor = getIdleColor(afkBtn)

local inPractice = false

-- AFK state is owned by the server: pressing it mid-round queues it for the
-- next one rather than flagging you immediately.
local function isAfkOn()
	return localPlayer:GetAttribute("IsAFK") == true
end

local function isAfkPending()
	return localPlayer:GetAttribute("PendingAFK") == true
end

--[[
	These buttons render their label twice: an outer black "Title" acting as the
	drop shadow, with the coloured face "Title" nested inside it.

	The old version wrote only to the inner label, so the shadow kept whatever
	text was authored in Studio - RETURN was drawn over a shadow still reading
	PRACTICE, and AFK ON over one reading "AFK: OFF". Write the whole stack.

	The face must also draw above its own shadow. The AFK button had these
	inverted (shadow ZIndex 2 over face ZIndex 1), which is why it looked muddier
	than the Practice button.
]]
local function setButtonTitle(button, text)
	button.Text = ""
	local title = button:FindFirstChild("Title")
	if not title then
		button.Text = text
		return
	end

	local depth = 0
	local label = title
	while label and label:IsA("TextLabel") do
		label.Text = text
		-- Each nested layer sits one step in front of the one behind it.
		label.ZIndex = 1 + depth
		depth += 1
		label = label:FindFirstChild("Title")
	end
end

local function setButtonColor(button, color)
	button.AutoButtonColor = false
	local frame = button:FindFirstChild("Frame")
	if frame then
		frame.BackgroundColor3 = color
	else
		button.BackgroundColor3 = color
	end
end

local function updatePracticeButton()
	if inPractice then
		setButtonTitle(practiceBtn, "RETURN")
		setButtonColor(practiceBtn, STYLE.RETURN)
	else
		setButtonTitle(practiceBtn, "PRACTICE")
		setButtonColor(practiceBtn, practiceIdleColor)
	end
end

local function updateAfkButton()
	if isAfkOn() then
		setButtonTitle(afkBtn, "AFK ON")
		setButtonColor(afkBtn, STYLE.AFK_ON)
	elseif isAfkPending() then
		setButtonTitle(afkBtn, "AFK NEXT ROUND")
		setButtonColor(afkBtn, STYLE.AFK_PENDING)
	else
		setButtonTitle(afkBtn, "AFK OFF")
		setButtonColor(afkBtn, afkIdleColor)
	end
end

updatePracticeButton()
updateAfkButton()
if friendBtn then
	setButtonColor(friendBtn, STYLE.FRIEND)
	setButtonTitle(friendBtn, "+")
end

practiceBtn.MouseButton1Click:Connect(function()
	if not localPlayer.Character or not localPlayer.Character:FindFirstChild("HumanoidRootPart") then
		return
	end

	practiceEvent:FireServer(not inPractice)
end)

localPlayer:GetAttributeChangedSignal("InPractice"):Connect(function()
	inPractice = localPlayer:GetAttribute("InPractice") == true
	updatePracticeButton()
end)

afkBtn.MouseButton1Click:Connect(function()
	-- Toggling off cancels a queued request as well as an active one.
	afkEvent:FireServer(not (isAfkOn() or isAfkPending()))
end)

localPlayer:GetAttributeChangedSignal("IsAFK"):Connect(updateAfkButton)
localPlayer:GetAttributeChangedSignal("PendingAFK"):Connect(updateAfkButton)

if friendBtn then
	friendBtn.MouseButton1Click:Connect(function()
		pcall(function()
			SocialService:PromptGameInvite(localPlayer)
		end)
	end)
end

UIHelpers.bindButtonHover(practiceBtn)
UIHelpers.bindButtonHover(afkBtn)
if friendBtn then
	UIHelpers.bindButtonHover(friendBtn)
end