--[[
	Fireworks -- client-side celebration rockets, ported from the Tutorial
	System Pack. Clones Assets.Effects.FireworkEffect, flies it up along a
	slight curve, then pops the particle emitters with a random color.

	Purely cosmetic and purely local: clones live under the camera, so
	nothing replicates. Used by the tutorial's finish celebration.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLIGHT_DURATION = { 0.15, 0.6 }
local FLIGHT_STUDS = { 10, 15 }
local CURVE_ANGLE = 60

local COLORS = {
	Color3.fromRGB(255, 34, 34),
	Color3.fromRGB(255, 107, 38),
	Color3.fromRGB(255, 196, 46),
	Color3.fromRGB(158, 255, 94),
	Color3.fromRGB(156, 255, 247),
	Color3.fromRGB(160, 174, 255),
	Color3.fromRGB(222, 156, 255),
	Color3.fromRGB(255, 179, 226),
}

local random = Random.new()
local lastColor: Color3? = nil

local Fireworks = {}

local function pickColor(): Color3
	local color = COLORS[random:NextInteger(1, #COLORS)]

	while color == lastColor do
		color = COLORS[random:NextInteger(1, #COLORS)]
	end

	lastColor = color
	return color
end

local function template(): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local effects = assets and assets:FindFirstChild("Effects")
	local effect = effects and effects:FindFirstChild("FireworkEffect")

	if effect and effect:IsA("BasePart") then
		return effect
	end

	warn("[Fireworks] Assets.Effects.FireworkEffect is missing")
	return nil
end

function Fireworks.Launch(startPosition: Vector3)
	local effect = template()

	if not effect then
		return
	end

	task.spawn(function()
		local rocket = effect:Clone()
		rocket.CFrame = CFrame.new(startPosition) * CFrame.Angles(0, math.rad(random:NextInteger(1, 360)), 0)
		rocket.Anchored = true
		rocket.CanCollide = false
		rocket.CanQuery = false
		rocket.CanTouch = false
		-- NOT the camera: it is recreated on respawn, which would destroy every
		-- rocket in flight. The tutorial's celebration fires right after the
		-- rebirth respawn, so that is the common case, not the rare one.
		rocket.Parent = workspace

		local launchSound = script.FireworkLaunch:Clone()
		launchSound.PlaybackSpeed = 1 + random:NextNumber(0, 0.15)
		launchSound.Parent = rocket
		launchSound:Play()

		local seed = random:NextNumber()
		local duration = FLIGHT_DURATION[1] + (FLIGHT_DURATION[2] - FLIGHT_DURATION[1]) * seed
		local studs = FLIGHT_STUDS[1] + (FLIGHT_STUDS[2] - FLIGHT_STUDS[1]) * seed

		local elapsed = 0
		local connection

		connection = RunService.RenderStepped:Connect(function(deltaTime)
			elapsed += deltaTime

			if elapsed < duration then
				rocket.CFrame *= CFrame.Angles(math.rad(CURVE_ANGLE * deltaTime / duration), 0, 0)
					* CFrame.new(0, studs * deltaTime / duration, 0)
			else
				connection:Disconnect()
			end
		end)

		task.delay(duration, function()
			local explosion = rocket:FindFirstChild("Explosion")

			if not explosion then
				return -- rocket was destroyed mid-flight
			end

			local lines = explosion.Lines
			local sparks = explosion.Sparks

			local explodeSound = script.FireworkExplode:Clone()
			explodeSound.PlaybackSpeed = 1 + random:NextNumber(0.3, 0.35)
			explodeSound.Parent = rocket
			explodeSound:Play()

			local color = pickColor()
			lines.Color = ColorSequence.new(color)
			sparks.Color = ColorSequence.new(color)

			lines:Emit(random:NextInteger(60, 100))
			sparks:Emit(random:NextInteger(40, 80))

			task.delay(0.3, function()
				sparks.Enabled = false
			end)

			task.delay(2, function()
				rocket:Destroy()
			end)
		end)
	end)
end

function Fireworks.Play(startPosition: Vector3, amount: number?, interval: number?)
	task.spawn(function()
		for _ = 1, amount or random:NextInteger(5, 7) do
			Fireworks.Launch(startPosition)
			task.wait(interval or random:NextNumber(0.05, 0.085))
		end
	end)
end

return Fireworks