local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))

local player = Players.LocalPlayer
PlayerSettings.ensure(player)

local DASH_COOLDOWN = 0.75
local DASH_DISTANCE = 10
local DASH_DURATION = 0.45

local isDashing = false
local lastDashTime = 0
local activeDashTween = nil
local dashFinishToken = 0
local dashCooldownLoopActive = false
local boundDashButton = nil
local boundCooldownLabel = nil
local boundDashImage = nil
local mobileBindToken = 0
local dashTrack = nil

local function canDash()
	if player:GetAttribute("IsEliminated") == true then
		return false
	end
	return true
end

local function getDashAnimObject()
	return script:FindFirstChild("DashAnim") or script.Parent:FindFirstChild("DashAnim")
end

local function stopMovementAnimations(animator)
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Priority == Enum.AnimationPriority.Movement then
			track:Stop(0.1)
		end
	end
end

local function bindDashAnimation(character)
	dashTrack = nil
	local humanoid = character:WaitForChild("Humanoid")
	local animator = humanoid:WaitForChild("Animator")
	local dashAnimObject = getDashAnimObject()
	if dashAnimObject then
		dashTrack = animator:LoadAnimation(dashAnimObject)
		dashTrack.Priority = Enum.AnimationPriority.Action4
		dashTrack.Looped = false
	end
end

local function playDashAnimation(animator)
	if not animator then
		return
	end

	stopMovementAnimations(animator)

	local track = dashTrack
	if not track then
		local dashAnimObject = getDashAnimObject()
		if dashAnimObject then
			track = animator:LoadAnimation(dashAnimObject)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			dashTrack = track
		end
	end

	if track then
		track:Stop(0)
		track:AdjustSpeed(1)
		track:Play(0.05)
	end
end

local function cancelDashTween()
	if activeDashTween then
		activeDashTween:Cancel()
		activeDashTween = nil
	end
end

local function stopDashAnimation()
	if dashTrack and dashTrack.IsPlaying then
		dashTrack:Stop(0.1)
	end
end

local function resetDashState()
	dashFinishToken += 1
	isDashing = false
	cancelDashTween()
	stopDashAnimation()
end

local function getDashCooldownRemaining()
	return math.max(0, DASH_COOLDOWN - (os.clock() - lastDashTime))
end

local function refreshDashButton()
	if not boundDashButton then
		return
	end

	local remaining = getDashCooldownRemaining()
	if boundCooldownLabel then
		boundCooldownLabel.Text = remaining > 0 and string.format("%.1fs", remaining) or ""
	end
	if boundDashImage then
		boundDashImage.ImageTransparency = remaining > 0 and 0.35 or 0
	end
end

local function startDashCooldownLoop()
	if dashCooldownLoopActive then
		return
	end

	dashCooldownLoopActive = true
	task.spawn(function()
		while dashCooldownLoopActive and boundDashButton and boundDashButton.Parent do
			local remaining = getDashCooldownRemaining()
			if remaining > 0 then
				refreshDashButton()
				task.wait(0.1)
			else
				refreshDashButton()
				break
			end
		end
		dashCooldownLoopActive = false
	end)
end

local function performDash(directionVector)
	if not canDash() then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	local currentTime = os.clock()
	if currentTime - lastDashTime < DASH_COOLDOWN or isDashing then
		return
	end

	dashFinishToken += 1
	cancelDashTween()

	isDashing = true
	lastDashTime = currentTime
	local finishToken = dashFinishToken
	refreshDashButton()
	startDashCooldownLoop()

	local animator = humanoid:FindFirstChildOfClass("Animator")
	playDashAnimation(animator)

	local dashVelocity = (rootPart.CFrame.RightVector * directionVector.X) + (rootPart.CFrame.LookVector * directionVector.Z)
	dashVelocity = Vector3.new(dashVelocity.X, 0, dashVelocity.Z)
	if dashVelocity.Magnitude < 0.001 then
		dashVelocity = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	dashVelocity = dashVelocity.Unit
	local startPos = rootPart.Position
	local newPos = startPos + (dashVelocity * DASH_DISTANCE)
	newPos = Vector3.new(newPos.X, startPos.Y, newPos.Z)
	local look = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if look.Magnitude < 0.001 then
		look = dashVelocity
	else
		look = look.Unit
	end
	local targetCFrame = CFrame.new(newPos, newPos + look)

	local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
	if PlayerSettings.isSFXEnabled() and gameAssets and gameAssets:FindFirstChild("Sounds") then
		local swooshTemplate = gameAssets.Sounds:FindFirstChild("DashSwoosh")
		if swooshTemplate then
			local dashSound = swooshTemplate:Clone()
			dashSound.Parent = rootPart
			dashSound.PlaybackSpeed = math.random(90, 110) / 100
			dashSound:Play()
			Debris:AddItem(dashSound, 2)
		end
	end

	if PlayerSettings.isWorldVFXEnabled() and gameAssets and gameAssets:FindFirstChild("Particles") then
		local dustTemplate = gameAssets.Particles:FindFirstChild("DashDust")
		if dustTemplate then
			local dustAnchor = Instance.new("Part")
			dustAnchor.Size = Vector3.new(1, 1, 1)
			dustAnchor.Transparency = 1
			dustAnchor.Anchored = true
			dustAnchor.CanCollide = false
			dustAnchor.Position = rootPart.Position - Vector3.new(0, 2.5, 0)
			dustAnchor.Parent = workspace

			local dashDust = dustTemplate:Clone()
			dashDust.Parent = dustAnchor
			dashDust:Emit(15)
			Debris:AddItem(dustAnchor, 1.5)
		end
	end

	local camera = workspace.CurrentCamera
	if camera and PlayerSettings.isScreenShakeEnabled() then
		local originalFOV = camera.FieldOfView
		local zoomOut = TweenService:Create(camera, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = originalFOV + 15})
		zoomOut:Play()
		zoomOut.Completed:Connect(function()
			local zoomIn = TweenService:Create(camera, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {FieldOfView = originalFOV})
			zoomIn:Play()
		end)
	end

	local wasAutoRotate = humanoid.AutoRotate
	local wasWalkSpeed = humanoid.WalkSpeed
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)

	local dashTween = TweenService:Create(rootPart, TweenInfo.new(DASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = targetCFrame})
	activeDashTween = dashTween
	dashTween:Play()

	local function finishDash()
		if finishToken ~= dashFinishToken then
			return
		end

		if humanoid.Parent then
			humanoid.AutoRotate = wasAutoRotate
			humanoid.WalkSpeed = wasWalkSpeed
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
		end

		isDashing = false
		cancelDashTween()
	end

	dashTween.Completed:Connect(finishDash)
	task.delay(DASH_DURATION + 0.15, finishDash)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		performDash(Vector3.new(0, 0, 1))
	end
end)

local function getDashButton(mobileGui)
	for _, child in ipairs(mobileGui:GetChildren()) do
		if child.Name == "DashButton" and child:IsA("ImageButton") then
			return child
		end
	end
	return nil
end

local function getCooldownLabel(dashButton)
	local dashImage = dashButton:FindFirstChild("DashImage")
	if not dashImage then
		return nil
	end

	local cooldownLabel = dashImage:FindFirstChild("CooldownLabel")
	if not cooldownLabel then
		cooldownLabel = Instance.new("TextLabel")
		cooldownLabel.Name = "CooldownLabel"
		cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
		cooldownLabel.BackgroundTransparency = 1
		cooldownLabel.Text = ""
		cooldownLabel.Font = Enum.Font.GothamBold
		cooldownLabel.TextScaled = true
		cooldownLabel.TextColor3 = Color3.new(1, 1, 1)
		cooldownLabel.ZIndex = dashImage.ZIndex + 2

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = cooldownLabel

		cooldownLabel.Parent = dashImage
	end

	return cooldownLabel, dashImage
end

local function bindMobileDashButton(mobileGui)
	local dashButton = getDashButton(mobileGui)
	if not dashButton then
		return
	end

	mobileBindToken += 1
	local token = mobileBindToken

	local cooldownLabel, dashImage = getCooldownLabel(dashButton)
	boundDashButton = dashButton
	boundCooldownLabel = cooldownLabel
	boundDashImage = dashImage

	dashButton.Active = true
	dashButton.Selectable = true
	for _, desc in ipairs(dashButton:GetDescendants()) do
		if desc:IsA("GuiObject") then
			desc.Active = false
			pcall(function()
				desc.Interactable = false
			end)
		end
	end

	local function onDashPressed()
		if token ~= mobileBindToken then
			return
		end
		performDash(Vector3.new(0, 0, 1))
	end

	dashButton.Activated:Connect(onDashPressed)

	refreshDashButton()
end

local function onPlayerGuiReady(playerGui)
	local mobileGui = playerGui:WaitForChild("MobileGui", 10)
	if mobileGui then
		bindMobileDashButton(mobileGui)
	end

	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "MobileGui" then
			task.defer(function()
				bindMobileDashButton(child)
			end)
		end
	end)
end

player.CharacterAdded:Connect(function(character)
	resetDashState()
	task.spawn(function()
		bindDashAnimation(character)
	end)
end)

if player.Character then
	task.spawn(function()
		bindDashAnimation(player.Character)
	end)
end

player:GetAttributeChangedSignal("InArena"):Connect(function()
	if player:GetAttribute("InArena") ~= true then
		resetDashState()
	end
end)

player:GetAttributeChangedSignal("IsEliminated"):Connect(function()
	if player:GetAttribute("IsEliminated") == true then
		resetDashState()
	end
end)

local playerGui = player:FindFirstChild("PlayerGui")
if playerGui then
	onPlayerGuiReady(playerGui)
else
	task.spawn(function()
		onPlayerGuiReady(player:WaitForChild("PlayerGui"))
	end)
end
