local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local localPlayer = Players.LocalPlayer
local gui = script.Parent
local practiceBtn = gui:WaitForChild("PracticeButton")
local afkBtn = gui:WaitForChild("AFKButton")
local friendBtn = gui:FindFirstChild("FriendButton")
local afkEvent = ReplicatedStorage:WaitForChild("AFKEvent")
local practiceEvent = ReplicatedStorage:WaitForChild("PracticeEvent")

local STYLE = {
	PRACTICE = Color3.fromRGB(0, 170, 85),
	RETURN = Color3.fromRGB(255, 120, 0),
	AFK_ON = Color3.fromRGB(210, 60, 60),
	AFK_OFF = Color3.fromRGB(90, 92, 105),
	FRIEND = Color3.fromRGB(60, 120, 255),
}

local isAFK = false
local inPractice = false

local function setButtonTitle(button, text)
	button.Text = ""
	local title = button:FindFirstChild("Title")
	if not title then
		button.Text = text
		return
	end

	local innerTitle = title:FindFirstChild("Title")
	if innerTitle and innerTitle:IsA("TextLabel") then
		innerTitle.Text = text
	else
		title.Text = text
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
		setButtonColor(practiceBtn, STYLE.PRACTICE)
	end
end

local function updateAfkButton()
	if isAFK then
		setButtonTitle(afkBtn, "AFK ON")
		setButtonColor(afkBtn, STYLE.AFK_ON)
	else
		setButtonTitle(afkBtn, "AFK OFF")
		setButtonColor(afkBtn, STYLE.AFK_OFF)
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
	isAFK = not isAFK
	updateAfkButton()
	afkEvent:FireServer(isAFK)
end)

if friendBtn then
	friendBtn.MouseButton1Click:Connect(function()
		pcall(function()
			SocialService:PromptGameInvite(localPlayer)
		end)
	end)
end