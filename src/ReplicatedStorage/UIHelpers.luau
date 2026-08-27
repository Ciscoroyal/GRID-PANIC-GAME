local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))

local UIHelpers = {}

local HOVER_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function UIHelpers.prepareImageLabel(imageLabel)
	if not imageLabel then
		return
	end
	imageLabel.BackgroundTransparency = 1
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.Visible = true
end

function UIHelpers.setAvatarImage(imageLabel, userId)
	UIHelpers.prepareImageLabel(imageLabel)
	imageLabel.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"

	if not userId then
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok and imageLabel.Parent then
			imageLabel.Image = content
		end
	end)
end

function UIHelpers.setAbilityImage(imageLabel, abilityName)
	UIHelpers.prepareImageLabel(imageLabel)

	local abilityInfo = AbilityData[abilityName]
	if abilityInfo and abilityInfo.ImageId and abilityInfo.ImageId ~= "" then
		imageLabel.Image = abilityInfo.ImageId
		imageLabel.Visible = true
	else
		imageLabel.Image = ""
		imageLabel.Visible = false
	end
end

local function getOrCreateUIScale(parent, name)
	local scale = name and parent:FindFirstChild(name) or parent:FindFirstChildOfClass("UIScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end
	scale = Instance.new("UIScale")
	if name then
		scale.Name = name
	end
	scale.Scale = 1
	scale.Parent = parent
	return scale
end

local function tweenScale(scale, value, info)
	TweenService:Create(scale, info or HOVER_INFO, { Scale = value }):Play()
end

-- Soft hover / press feedback. `hitTarget` receives input; `visual` gets the UIScale.
function UIHelpers.bindButtonHover(hitTarget, opts)
	opts = opts or {}
	if not hitTarget or not hitTarget:IsA("GuiObject") then
		return
	end
	if hitTarget:GetAttribute("HoverBound") == true then
		return
	end
	hitTarget:SetAttribute("HoverBound", true)

	local visual = opts.visual or hitTarget
	if not visual:IsA("GuiObject") then
		visual = hitTarget
	end

	local hoverScale = opts.hoverScale or 1.06
	local pressScale = opts.pressScale or 0.96
	local useStroke = opts.useStroke == true or hoverScale == 1
	local allowScale = hoverScale ~= 1 or pressScale ~= 1
	local scale = allowScale and getOrCreateUIScale(visual, "HoverUIScale") or nil
	if scale then
		scale.Scale = 1
	end

	local stroke = visual:FindFirstChildOfClass("UIStroke")
	local baseStrokeThickness = stroke and stroke.Thickness or 2
	local baseStrokeColor = stroke and stroke.Color or Color3.new(0, 0, 0)

	if hitTarget:IsA("GuiButton") then
		hitTarget.AutoButtonColor = false
	end

	local hovering = false
	local function toIdle()
		if scale then
			tweenScale(scale, 1, HOVER_INFO)
		end
		if useStroke and stroke then
			stroke.Thickness = baseStrokeThickness
			stroke.Color = baseStrokeColor
		end
	end
	local function toHover()
		if scale then
			tweenScale(scale, hoverScale, HOVER_INFO)
		end
		if useStroke and stroke then
			stroke.Thickness = baseStrokeThickness + 1.25
			stroke.Color = Color3.fromRGB(255, 220, 80)
		end
	end
	local function toPress()
		if scale then
			tweenScale(scale, pressScale, PRESS_INFO)
		end
	end

	hitTarget.MouseEnter:Connect(function()
		hovering = true
		toHover()
	end)
	hitTarget.MouseLeave:Connect(function()
		hovering = false
		toIdle()
	end)

	if hitTarget:IsA("GuiButton") then
		hitTarget.MouseButton1Down:Connect(toPress)
		hitTarget.MouseButton1Up:Connect(function()
			if hovering then
				toHover()
			else
				toIdle()
			end
		end)
	end
end

function UIHelpers.bindHoversUnder(root, opts)
	if not root then
		return
	end
	if root:IsA("GuiButton") then
		UIHelpers.bindButtonHover(root, opts)
	end
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("GuiButton") then
			UIHelpers.bindButtonHover(desc, opts)
		end
	end
end

function UIHelpers.animatePanelOpen(frame, opts)
	opts = opts or {}
	if not frame or not frame:IsA("GuiObject") then
		return
	end

	local center = opts.center or UDim2.new(0.5, 0, 0.5, 0)
	local startPos = opts.startPos or UDim2.new(0.5, 0, 0.56, 0)
	local duration = opts.duration or 0.35

	-- Invalidate any in-flight close callback
	frame:SetAttribute("CloseToken", (frame:GetAttribute("CloseToken") or 0) + 1)
	frame.Visible = true
	frame.Position = startPos

	local scale = getOrCreateUIScale(frame, "PanelUIScale")
	scale.Scale = 0.96
	TweenService:Create(
		scale,
		TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	):Play()

	frame:TweenPosition(
		center,
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Back,
		duration,
		true
	)
end

function UIHelpers.animatePanelClose(frame, opts, onDone)
	opts = opts or {}
	if not frame or not frame:IsA("GuiObject") then
		if onDone then onDone() end
		return
	end
	if not frame.Visible then
		if onDone then onDone() end
		return
	end

	local endPos = opts.endPos or UDim2.new(0.5, 0, 0.56, 0)
	local duration = opts.duration or 0.2
	local token = (frame:GetAttribute("CloseToken") or 0) + 1
	frame:SetAttribute("CloseToken", token)

	local scale = frame:FindFirstChild("PanelUIScale")
	if scale and scale:IsA("UIScale") then
		TweenService:Create(
			scale,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.96 }
		):Play()
	end

	frame:TweenPosition(
		endPos,
		Enum.EasingDirection.In,
		Enum.EasingStyle.Quad,
		duration,
		true,
		function()
			if frame:GetAttribute("CloseToken") ~= token then
				return
			end
			frame.Visible = false
			if onDone then
				onDone()
			end
		end
	)
end

return UIHelpers
