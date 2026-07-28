local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") 
local Players = game:GetService("Players")
local Debris = game:GetService("Debris") -- Added for VFX/SFX cleanup

local PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))

local localPlayer = Players.LocalPlayer
PlayerSettings.ensure(localPlayer)
local useAbilityEvent = ReplicatedStorage:WaitForChild("UseAbilityEvent")
local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))

local gameAssets = ReplicatedStorage:FindFirstChild("GameAssets")
local swooshTemplate = gameAssets and gameAssets:FindFirstChild("Sounds") and gameAssets.Sounds:FindFirstChild("DashSwoosh")
local dustTemplate = gameAssets and gameAssets:FindFirstChild("Particles") and gameAssets.Particles:FindFirstChild("DashDust")

local dashAnimation = Instance.new("Animation")
dashAnimation.AnimationId = "rbxassetid://77329448433602"

local CLIENT_SPAM_GUARD = 0.15
local lastUseTime = 0

local function isAbilityOnCooldown()
	local cooldownEnd = localPlayer:GetAttribute("AbilityCooldownEnd")
	if not cooldownEnd then return false end
	return workspace:GetServerTimeNow() < cooldownEnd
end

local function getCooldownRemaining()
	local cooldownEnd = localPlayer:GetAttribute("AbilityCooldownEnd")
	if not cooldownEnd then return 0 end
	return math.max(0, cooldownEnd - workspace:GetServerTimeNow())
end

local function waitForAbilityAccepted(previousCooldownEnd, timeout)
	if localPlayer:GetAttribute("AbilityCooldownEnd") ~= previousCooldownEnd then
		return true
	end

	local accepted = false
	local connection = localPlayer:GetAttributeChangedSignal("AbilityCooldownEnd"):Connect(function()
		accepted = true
	end)

	local deadline = os.clock() + (timeout or 0.25)
	while not accepted and os.clock() < deadline do
		task.wait()
	end

	connection:Disconnect()
	return accepted
end

-- =========================================================
-- HELPER: LOCAL HIT DETECTION (Fixes the pushing bug!)
-- =========================================================
local function getLocalTarget(character, range)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil, range end

	local bestTarget = nil
	local closestDist = range

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= localPlayer and otherPlayer.Character and otherPlayer:GetAttribute("InArena") then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local vectorToTarget = otherRoot.Position - root.Position
				local distance = vectorToTarget.Magnitude

				if distance <= range then
					local directionToTarget = vectorToTarget.Unit
					local dotProduct = root.CFrame.LookVector:Dot(directionToTarget)

					if dotProduct > 0.5 and distance < closestDist then
						closestDist = distance
						bestTarget = otherPlayer.Character
					end
				end
			end
		end
	end

	return bestTarget, closestDist
end

local function performDashStrike()
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local targetChar, distToTarget = getLocalTarget(character, 15)
	local dashDistance = 10

	if targetChar then
		local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
		if targetPlayer and targetPlayer:GetAttribute("HasShield") == true then
			dashDistance = math.max(0, distToTarget - 4)
		else
			dashDistance = distToTarget
		end
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChild("Animator")
		if animator then
			local dashTrack = animator:LoadAnimation(dashAnimation)
			dashTrack.Priority = Enum.AnimationPriority.Action
			dashTrack:Play()
		end
	end

	if PlayerSettings.isSFXEnabled() and swooshTemplate then
		local dashSound = swooshTemplate:Clone()
		dashSound.Parent = rootPart
		dashSound.PlaybackSpeed = math.random(90, 110) / 100
		dashSound:Play()
		Debris:AddItem(dashSound, 2)
	end

	if PlayerSettings.isWorldVFXEnabled() and dustTemplate then
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

	local dashVelocity = rootPart.CFrame.LookVector
	local targetCFrame = rootPart.CFrame + (dashVelocity * dashDistance)

	local tweenInfo = TweenInfo.new(
		0.25,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local dashTween = TweenService:Create(rootPart, tweenInfo, {CFrame = targetCFrame})
	dashTween:Play()
end

local function triggerAbility()
	if localPlayer:GetAttribute("InArena") ~= true then return end
	if localPlayer:GetAttribute("IsEliminated") == true then return end

	local equippedAbility = localPlayer:GetAttribute("EquippedAbility")
	if not equippedAbility or equippedAbility == "None" then return end

	if isAbilityOnCooldown() then
		return
	end

	local currentTime = os.clock()
	if currentTime - lastUseTime < CLIENT_SPAM_GUARD then return end

	lastUseTime = currentTime
	local previousCooldownEnd = localPlayer:GetAttribute("AbilityCooldownEnd")
	useAbilityEvent:FireServer(equippedAbility)

	if equippedAbility == "Dash Strike" and waitForAbilityAccepted(previousCooldownEnd) then
		performDashStrike()
	end
end

-- =========================================================
-- KEYBOARD INPUT ('E')
-- =========================================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end 

	if input.KeyCode == Enum.KeyCode.E then
		if localPlayer:GetAttribute("IsEliminated") == true then
			return
		end
		triggerAbility()
	end
end)

-- =========================================================
-- MOBILE BUTTON SUPPORT
-- =========================================================
local function getAbilityButton(mobileGui)
	for _, child in ipairs(mobileGui:GetChildren()) do
		if child.Name == "AbilityButton" and child:IsA("ImageButton") then
			return child
		end
	end
	return nil
end

local function getCooldownLabel(abilityButton)
	local abilityImage = abilityButton:FindFirstChild("AbilityImage")
	if not abilityImage then
		return nil
	end

	local cooldownLabel = abilityImage:FindFirstChild("CooldownLabel")
	if not cooldownLabel then
		cooldownLabel = Instance.new("TextLabel")
		cooldownLabel.Name = "CooldownLabel"
		cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
		cooldownLabel.BackgroundTransparency = 1
		cooldownLabel.Text = ""
		cooldownLabel.Font = Enum.Font.GothamBold
		cooldownLabel.TextScaled = true
		cooldownLabel.TextColor3 = Color3.new(1, 1, 1)
		cooldownLabel.ZIndex = abilityImage.ZIndex + 2

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = cooldownLabel

		cooldownLabel.Parent = abilityImage
	end

	return cooldownLabel, abilityImage
end

local function refreshEquippedAbilityIcon(abilityImage)
	if not abilityImage then
		return
	end
	abilityImage.Visible = true
end

local function bindMobileAbilityButton(mobileGui)
	local abilityButton = getAbilityButton(mobileGui)
	if not abilityButton or abilityButton:GetAttribute("CombatBound") == true then
		return
	end

	local cooldownLabel, abilityImage = getCooldownLabel(abilityButton)
	abilityButton:SetAttribute("CombatBound", true)
	abilityButton.Active = true
	abilityButton.Selectable = true
	for _, desc in ipairs(abilityButton:GetDescendants()) do
		if desc:IsA("GuiObject") then
			desc.Active = false
			pcall(function()
				desc.Interactable = false
			end)
		end
	end

	abilityButton.Activated:Connect(triggerAbility)
	refreshEquippedAbilityIcon(abilityImage)
	localPlayer:GetAttributeChangedSignal("EquippedAbility"):Connect(function()
		refreshEquippedAbilityIcon(abilityImage)
	end)

	local function refreshAbilityButton()
		if localPlayer:GetAttribute("InArena") ~= true then
			if cooldownLabel then
				cooldownLabel.Text = ""
			end
			if abilityImage then
				abilityImage.ImageTransparency = 0
			end
			return
		end

		local remaining = getCooldownRemaining()
		if cooldownLabel then
			if remaining > 0 then
				cooldownLabel.Text = string.format("%.1fs", remaining)
			else
				cooldownLabel.Text = ""
			end
		end

		if abilityImage then
			abilityImage.ImageTransparency = remaining > 0 and 0.35 or 0
		end
	end

	local cooldownLoopActive = false

	local function startCooldownLoop()
		if cooldownLoopActive then
			return
		end
		cooldownLoopActive = true
		task.spawn(function()
			while cooldownLoopActive and abilityButton.Parent do
				if localPlayer:GetAttribute("InArena") ~= true then
					refreshAbilityButton()
					break
				end

				local remaining = getCooldownRemaining()
				if remaining > 0 then
					if cooldownLabel then
						cooldownLabel.Text = string.format("%.1fs", remaining)
					end
					if abilityImage then
						abilityImage.ImageTransparency = 0.35
					end
					task.wait(0.1)
				else
					refreshAbilityButton()
					break
				end
			end
			cooldownLoopActive = false
		end)
	end

	local function onCooldownStateChanged()
		refreshAbilityButton()
		if localPlayer:GetAttribute("InArena") == true and getCooldownRemaining() > 0 then
			startCooldownLoop()
		end
	end

	localPlayer:GetAttributeChangedSignal("AbilityCooldownEnd"):Connect(onCooldownStateChanged)
	localPlayer:GetAttributeChangedSignal("InArena"):Connect(onCooldownStateChanged)
	onCooldownStateChanged()
end

local playerGui = localPlayer:WaitForChild("PlayerGui")
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "MobileGui" then
		task.defer(function()
			bindMobileAbilityButton(child)
		end)
	end
end)

local existingMobileGui = playerGui:FindFirstChild("MobileGui")
if existingMobileGui then
	bindMobileAbilityButton(existingMobileGui)
else
	task.spawn(function()
		bindMobileAbilityButton(playerGui:WaitForChild("MobileGui", 10))
	end)
end