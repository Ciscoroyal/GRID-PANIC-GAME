local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))
local localPlayer = Players.LocalPlayer
PlayerSettings.ensure(localPlayer)

local combatAnimEvent = ReplicatedStorage:WaitForChild("CombatAnimEvent")
local animationsFolder = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("Animations")
local gameAssets = ReplicatedStorage:WaitForChild("GameAssets")

local ANIM_SETTINGS = {
	-- Long clip with ~1.5s windup: skip ahead, then play the punch fast
	GridPunch = {
		playbackSpeed = 5,
		startTime = 1.5,
	},
	DashStrike = {
		playbackSpeed = 1,
	},
	ShieldBubble = {
		playbackSpeed = 1,
	},
	-- Ground impact lands near the end of this short slam clip
	Shockwave = {
		playbackSpeed = 1,
	},
}

local WARM_ANIM_NAMES = { "GridPunch", "DashStrike", "ShieldBubble", "Shockwave" }

local trackCache = {}

local function getAnimationObject(animName)
	local animObject = animationsFolder:FindFirstChild(animName)
	if animObject and animObject:IsA("Animation") then
		return animObject
	end
	return nil
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

local function clearCharacterCache(character)
	trackCache[character] = nil
end

local function getAnimator(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end
	return humanoid:FindFirstChild("Animator") or humanoid:WaitForChild("Animator", 2)
end

local function getOrCreateTrack(character, animName, animator, animObject)
	local charCache = trackCache[character]
	if not charCache then
		charCache = {}
		trackCache[character] = charCache
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				clearCharacterCache(character)
			end
		end)
	end

	local cacheKey = animName .. "_" .. animObject.AnimationId
	local track = charCache[cacheKey]
	if not track then
		track = animator:LoadAnimation(animObject)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		charCache[cacheKey] = track
	end

	return track
end

local function collectAnimationAssets()
	local assets = {}
	for _, child in ipairs(animationsFolder:GetChildren()) do
		if child:IsA("Animation") then
			table.insert(assets, child)
		end
	end
	return assets
end

local function preloadAnimationAssets()
	task.spawn(function()
		local assets = collectAnimationAssets()
		if #assets == 0 then
			return
		end
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end)
end

local function warmCharacterTracks(character)
	if not character then
		return
	end
	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid then
			return
		end
		local animator = getAnimator(humanoid)
		if not animator then
			return
		end
		for _, animName in ipairs(WARM_ANIM_NAMES) do
			local animObject = getAnimationObject(animName)
			if animObject then
				pcall(function()
					getOrCreateTrack(character, animName, animator, animObject)
				end)
			end
		end
	end)
end

local function hookPlayerCharacterWarm(player)
	player.CharacterAdded:Connect(warmCharacterTracks)
	if player.Character then
		warmCharacterTracks(player.Character)
	end
end

preloadAnimationAssets()
for _, player in ipairs(Players:GetPlayers()) do
	hookPlayerCharacterWarm(player)
end
Players.PlayerAdded:Connect(hookPlayerCharacterWarm)

local function playPunchSound(character, targetPlayer)
	if targetPlayer ~= localPlayer then
		return
	end
	if not PlayerSettings.isSFXEnabled() then
		return
	end

	local sounds = gameAssets:FindFirstChild("Sounds")
	local swooshTemplate = sounds and sounds:FindFirstChild("DashSwoosh")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not swooshTemplate or not rootPart then
		return
	end

	local punchSound = swooshTemplate:Clone()
	punchSound.PlaybackSpeed = 1.25
	punchSound.Volume = math.min(punchSound.Volume * 1.1, 1)
	punchSound.Parent = rootPart
	punchSound:Play()
	Debris:AddItem(punchSound, 1)
end

local function playCombatAnim(userId, animName)
	local animObject = getAnimationObject(animName)
	if not animObject then
		warn("[CombatAnimController] Missing Animation object:", animName)
		return
	end

	local targetPlayer = Players:GetPlayerByUserId(userId)
	if not targetPlayer then
		return
	end

	local character = targetPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local animator = getAnimator(humanoid)
	if not animator then
		return
	end

	local settings = ANIM_SETTINGS[animName]
	local playbackSpeed = settings and settings.playbackSpeed or 1
	local startTime = settings and settings.startTime or 0

	local ok, err = pcall(function()
		-- Dash Strike / other ability clips: mute default run for the ability anim length.
		local muteLocomotion = animName == "DashStrike" and targetPlayer == localPlayer
		if muteLocomotion then
			setLocomotionEnabled(character, false)
		end

		local track = getOrCreateTrack(character, animName, animator, animObject)
		-- Only dash should hard-stop run/locomotion tracks; other abilities overlay at Action4.
		if muteLocomotion then
			stopCompetingAnimations(animator, track)
		end
		track:Stop(0)
		track:Play(0, 1, playbackSpeed)
		if startTime > 0 then
			track.TimePosition = startTime
		end

		if animName == "GridPunch" then
			playPunchSound(character, targetPlayer)
		end

		if muteLocomotion then
			local muteToken = (character:GetAttribute("AbilityMuteToken") or 0) + 1
			character:SetAttribute("AbilityMuteToken", muteToken)
			local animLength = track.Length
			local duration = 0.25
			if animLength and animLength > 0 and playbackSpeed > 0 then
				local remaining = math.max(0, animLength - startTime)
				duration = math.max(duration, remaining / playbackSpeed)
			end
			task.spawn(function()
				local endAt = os.clock() + duration
				while os.clock() < endAt and character.Parent and character:GetAttribute("AbilityMuteToken") == muteToken do
					stopCompetingAnimations(animator, track)
					task.wait()
				end
				if character.Parent and character:GetAttribute("AbilityMuteToken") == muteToken then
					setLocomotionEnabled(character, true)
				end
			end)
		end
	end)

	if not ok then
		warn("[CombatAnimController] Failed to play", animName, "for", targetPlayer.Name, err)
	end
end

combatAnimEvent.OnClientEvent:Connect(function(animName, userId)
	if typeof(animName) ~= "string" or typeof(userId) ~= "number" then
		return
	end
	playCombatAnim(userId, animName)
end)

local function clearLocomotionMute(character)
	if not character then
		return
	end
	character:SetAttribute("AbilityMuteToken", (character:GetAttribute("AbilityMuteToken") or 0) + 1)
	setLocomotionEnabled(character, true)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if track.Priority == Enum.AnimationPriority.Action
				or track.Priority == Enum.AnimationPriority.Action2
				or track.Priority == Enum.AnimationPriority.Action3
				or track.Priority == Enum.AnimationPriority.Action4
			then
				track:Stop(0.1)
			end
		end
	end
end

localPlayer:GetAttributeChangedSignal("IsEliminated"):Connect(function()
	if localPlayer:GetAttribute("IsEliminated") == true then
		clearLocomotionMute(localPlayer.Character)
	end
end)

localPlayer:GetAttributeChangedSignal("InArena"):Connect(function()
	if localPlayer:GetAttribute("InArena") ~= true then
		clearLocomotionMute(localPlayer.Character)
	end
end)

localPlayer.CharacterAdded:Connect(function(character)
	clearCharacterCache(character)
	clearLocomotionMute(character)
end)