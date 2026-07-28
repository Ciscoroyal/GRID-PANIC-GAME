local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")

local isShaking = false

-- =========================================================
-- SYSTEM: SCREEN SHAKE
-- =========================================================
local function shakeCamera(intensity, duration)
	if isShaking then return end
	isShaking = true

	local startTime = os.clock()

	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startTime
		if elapsed < duration then
			-- Fade out the shake over time
			local currentIntensity = intensity * (1 - (elapsed / duration))

			-- Generate random camera offsets
			local offsetX = (math.random() - 0.5) * currentIntensity
			local offsetY = (math.random() - 0.5) * currentIntensity
			local offsetZ = (math.random() - 0.5) * currentIntensity

			camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(offsetX), math.rad(offsetY), math.rad(offsetZ))
		else
			connection:Disconnect()
			isShaking = false
		end
	end)
end

-- =========================================================
-- SYSTEM: HIT-STOP (The Micro-Pause)
-- =========================================================
local function triggerHitStop()
	-- Pause all playing animations on the character for 0.05 seconds to simulate impact weight
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChild("Animator")
		if animator then
			local activeTracks = animator:GetPlayingAnimationTracks()

			-- Freeze animations
			for _, track in ipairs(activeTracks) do
				track:AdjustSpeed(0)
			end

			task.wait(0.05)

			-- Resume animations
			for _, track in ipairs(activeTracks) do
				track:AdjustSpeed(1)
			end
		end
	end
end

-- =========================================================
-- EVENT LISTENER
-- =========================================================
vfxEvent.OnClientEvent:Connect(function(effectType, arg1, arg2)
	if effectType == "HeavyShake" then
		-- Parameters: Intensity, Duration
		shakeCamera(2, 0.4)

	elseif effectType == "LightShake" then
		shakeCamera(0.8, 0.2)

	elseif effectType == "PracticeHit" then
		local message = arg1 or "You were hit by a practice block!"
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = "Practice";
				Text = message;
				Duration = 3;
			})
		end)
		shakeCamera(0.8, 0.2)

	elseif effectType == "HitStop" then
		triggerHitStop()
	end
end)