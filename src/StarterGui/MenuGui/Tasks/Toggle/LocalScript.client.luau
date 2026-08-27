local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

local toggleRoot = script.Parent
local button = toggleRoot
local tasksFrame = toggleRoot.Parent
local title = tasksFrame:WaitForChild("Title")
local contentFrame = tasksFrame:WaitForChild("Frame")

local TWEEN_INFO = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local isOpen = true
local openPosition = tasksFrame.Position
local collapsedPosition = UDim2.new(0.018, 0, openPosition.Y.Scale, openPosition.Y.Offset)
local openTogglePosition = button.Position
-- Sit on the collapsed Tasks anchor (far left of the screen)
local closedTogglePosition = UDim2.new(0.5, 0, openTogglePosition.Y.Scale, openTogglePosition.Y.Offset)
local activeTween
local activeToggleTween

local function setToggleText(text)
	if button:IsA("TextButton") then
		button.Text = text
	end

	local label = button:FindFirstChildOfClass("TextLabel")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function setOpen(nextOpen)
	isOpen = nextOpen

	if activeTween then
		activeTween:Cancel()
	end
	if activeToggleTween then
		activeToggleTween:Cancel()
	end

	title.Visible = nextOpen
	contentFrame.Visible = nextOpen
	button.Visible = true

	local targetPosition = isOpen and openPosition or collapsedPosition
	activeTween = TweenService:Create(tasksFrame, TWEEN_INFO, { Position = targetPosition })
	activeTween:Play()

	local targetTogglePosition = isOpen and openTogglePosition or closedTogglePosition
	activeToggleTween = TweenService:Create(button, TWEEN_INFO, { Position = targetTogglePosition })
	activeToggleTween:Play()

	setToggleText(isOpen and "<" or ">")
end

setOpen(true)

button.Activated:Connect(function()
	setOpen(not isOpen)
end)

UIHelpers.bindButtonHover(button)
