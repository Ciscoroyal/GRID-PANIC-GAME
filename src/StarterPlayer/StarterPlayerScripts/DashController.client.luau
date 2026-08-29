local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))
local DashCollision = require(ReplicatedStorage:WaitForChild("DashCollision"))
local dashQuestEvent = ReplicatedStorage:WaitForChild("DashQuestEvent", 10)

local player = Players.LocalPlayer
PlayerSettings.ensure(player)

local DASH_COOLDOWN = 0.75
local DASH_DISTANCE = 15
local DASH_DURATION = 0.45

-- Forward declaration: performDash sits above the trail code that defines it.
local playDashTrails

local isDashing = false
local lastDashTime = 0
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
	-- Pre-match countdown: no dashing until GO.
	if player:GetAttribute("MatchLocked") == true then
		return false
	end
	return true
end

local function getDashAnimObject()
	return script:FindFirstChild("DashAnim") or script.Parent:FindFirstChild("DashAnim")
end

local function stopCompetingAnimations(animator, keepTrack)
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track ~= keepTrack then
			track:AdjustWeight(0, 0)
			track:Stop(0)
		end
	end
end

local function setLocomotionEnabled(character, enabled)
	local animate = character and character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Disabled = not enabled
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
		return nil, DASH_DURATION
	end

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

	stopCompetingAnimations(animator, track)

	if track then
		track:Stop(0)
		track:AdjustSpeed(1)
		track:Play(0, 1, 1)
		local animLength = track.Length
		if animLength and animLength > 0 then
			return track, math.max(DASH_DURATION, animLength)
		end
	end

	return track, DASH_DURATION
end

local function stopDashAnimation()
	if dashTrack and dashTrack.IsPlaying then
		dashTrack:Stop(0.1)
	end
end

local function cancelActiveDash()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		DashCollision.cancel(rootPart)
	end
end

--[[
	States suppressed for the duration of a dash.
	FallingDown / GettingUp / Ragdoll are the important ones: without them the
	humanoid tips over when the dash slams into geometry and burns ~3 seconds
	in the get-up animation before the player has control again.
]]
local DASH_SUPPRESSED_STATES = {
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.PlatformStanding,
}

local function setDashStatesEnabled(humanoid, enabled)
	if not humanoid or not humanoid.Parent then
		return
	end
	for _, state in ipairs(DASH_SUPPRESSED_STATES) do
		pcall(function()
			humanoid:SetStateEnabled(state, enabled)
		end)
	end
end

local function getDefaultWalkSpeed()
	local defaultSpeed = game:GetService("StarterPlayer").CharacterWalkSpeed
	if typeof(defaultSpeed) ~= "number" or defaultSpeed <= 0 then
		defaultSpeed = 16
	end
	return defaultSpeed
end

local function restoreHumanoidMovement(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.WalkSpeed = getDefaultWalkSpeed()
	humanoid.AutoRotate = true
	setDashStatesEnabled(humanoid, true)
	pcall(function()
		humanoid.PlatformStand = false
		humanoid.Sit = false
	end)

	-- Nudge out of any transient state the dash left behind.
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Ragdoll
		or state == Enum.HumanoidStateType.PlatformStanding
	then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end
end

--[[
	Published on the character so MovementWatchdog can tell a legitimate dash
	freeze from a humanoid that got stuck in one.
]]
local function setDashingFlag(value)
	local character = player.Character
	if character then
		character:SetAttribute("Dashing", value or nil)
	end
end

local function resetDashState()
	dashFinishToken += 1
	isDashing = false
	setDashingFlag(false)
	cancelActiveDash()
	stopDashAnimation()
	local character = player.Character
	if character then
		setLocomotionEnabled(character, true)
		-- Cancelling finishDash skips its WalkSpeed/AutoRotate restore — apply it here.
		restoreHumanoidMovement(character)
	end
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
	cancelActiveDash()

	isDashing = true
	setDashingFlag(true)
	lastDashTime = currentTime
	local finishToken = dashFinishToken
	refreshDashButton()
	startDashCooldownLoop()
	if dashQuestEvent and player:GetAttribute("InArena") == true and player:GetAttribute("IsEliminated") ~= true then
		dashQuestEvent:FireServer()
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	-- Physics dash makes Animate play run even from standstill; mute until dash anim ends.
	setLocomotionEnabled(character, false)
	local _, muteFor = playDashAnimation(animator)

	local dashVelocity = (rootPart.CFrame.RightVector * directionVector.X) + (rootPart.CFrame.LookVector * directionVector.Z)
	dashVelocity = Vector3.new(dashVelocity.X, 0, dashVelocity.Z)
	if dashVelocity.Magnitude < 0.001 then
		dashVelocity = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	dashVelocity = dashVelocity.Unit

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

	if PlayerSettings.isWorldVFXEnabled() then
		playDashTrails(character)
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
	-- Never restore a 0 walk speed (can happen if a dash starts during another
	-- freeze) or the player is stuck standing still after the dash.
	if typeof(wasWalkSpeed) ~= "number" or wasWalkSpeed <= 0 then
		wasWalkSpeed = getDefaultWalkSpeed()
	end
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	setDashStatesEnabled(humanoid, false)

	DashCollision.applyPhysicsDash(rootPart, dashVelocity, DASH_DISTANCE, DASH_DURATION)

	-- Keep only the dash clip visible for the full animation window.
	task.spawn(function()
		local endAt = os.clock() + muteFor
		while os.clock() < endAt and finishToken == dashFinishToken do
			stopCompetingAnimations(animator, dashTrack)
			task.wait()
		end
		if finishToken == dashFinishToken and character.Parent then
			setLocomotionEnabled(character, true)
		end
	end)

	local function finishDash()
		if finishToken ~= dashFinishToken then
			return
		end

		if humanoid.Parent then
			humanoid.AutoRotate = wasAutoRotate
			humanoid.WalkSpeed = wasWalkSpeed
			setDashStatesEnabled(humanoid, true)

			-- If the dash ended flat on the ground, put the humanoid straight back
			-- into Running rather than letting it settle through a fall state.
			local state = humanoid:GetState()
			if state ~= Enum.HumanoidStateType.Jumping
				and state ~= Enum.HumanoidStateType.Freefall
				and state ~= Enum.HumanoidStateType.Dead
			then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end
		end

		isDashing = false
		setDashingFlag(false)
	end

	task.delay(DASH_DURATION, finishDash)

	-- Watchdog: if anything swallowed finishDash, force the player back to normal.
	task.delay(DASH_DURATION + 0.5, function()
		if isDashing and finishToken == dashFinishToken then
			resetDashState()
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		performDash(Vector3.new(0, 0, 1))
	end
end)

--[[
	Jump cancels an active dash. The dash holds Y velocity at 0, so without this
	the jump impulse gets eaten by the constraint and the character plays a broken
	mid-air clip before locking up. Cancelling first frees the humanoid; if the
	jump was swallowed anyway we re-issue it on the next frame.
]]
UserInputService.JumpRequest:Connect(function()
	if not isDashing then
		return
	end

	resetDashState()

	task.defer(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Running or state == Enum.HumanoidStateType.RunningNoPhysics then
			humanoid.Jump = true
		end
	end)
end)

local function getDashButton(mobileGui)
	for _, child in ipairs(mobileGui:GetChildren()) do
		if child.Name == "DashButton" and child:IsA("ImageButton") then
			return child
		end
	end
	return nil
end

--[[
	Dash trails.

	GameAssets.DashTrails holds one folder per limb, each with the two
	attachments that limb's Trail spans plus the Trail itself. A dash clones
	that set onto the matching limb of the character, lets it draw for the
	length of the dash, then stops emitting and lets the existing streak fade
	out on its own before cleaning up - killing the trail outright would snap
	the streak out of the air mid-flight.
]]
local DASH_TRAIL_HOLD = 0.28
local DASH_TRAIL_TAG = "DashTrailVFX"

local function clearDashTrails(character)
	if not character then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:GetAttribute(DASH_TRAIL_TAG) == true then
			d:Destroy()
		end
	end
end

playDashTrails = function(character)
	local assets = ReplicatedStorage:FindFirstChild("GameAssets")
	local template = assets and assets:FindFirstChild("DashTrails")
	if not template or not character then
		return
	end

	-- A second dash before the first has faded would otherwise stack trails.
	clearDashTrails(character)

	local live = {}
	for _, limbFolder in ipairs(template:GetChildren()) do
		local limb = character:FindFirstChild(limbFolder.Name)
		if limb and limb:IsA("BasePart") then
			local sourceTrail = limbFolder:FindFirstChildOfClass("Trail")
			local a0 = limbFolder:FindFirstChild("Attachment")
			local a1 = limbFolder:FindFirstChild("Attachment1")
			if sourceTrail and a0 and a1 then
				local newA0 = a0:Clone()
				local newA1 = a1:Clone()
				newA0:SetAttribute(DASH_TRAIL_TAG, true)
				newA1:SetAttribute(DASH_TRAIL_TAG, true)
				newA0.Parent = limb
				newA1.Parent = limb

				local trail = sourceTrail:Clone()
				trail.Attachment0 = newA0
				trail.Attachment1 = newA1
				trail.Enabled = true
				trail:SetAttribute(DASH_TRAIL_TAG, true)
				trail.Parent = limb
				table.insert(live, trail)
			end
		end
	end

	if #live == 0 then
		return
	end

	task.delay(DASH_TRAIL_HOLD, function()
		local longest = 0
		for _, trail in ipairs(live) do
			if trail.Parent then
				trail.Enabled = false
				longest = math.max(longest, trail.Lifetime)
			end
		end
		-- Wait out the tail so the streak fades instead of vanishing.
		task.delay(longest + 0.1, function()
			clearDashTrails(character)
		end)
	end)
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
