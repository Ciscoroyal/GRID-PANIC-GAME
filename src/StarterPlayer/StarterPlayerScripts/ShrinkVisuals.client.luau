local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local shrinkTileEvent = ReplicatedStorage:WaitForChild("ShrinkTileEvent")

local function pulseWarn(tile, duration)
	if not tile or not tile:IsA("BasePart") then
		return
	end
	local overlay = Instance.new("Part")
	overlay.Name = "ShrinkWarnPulse"
	overlay.Anchored = true
	overlay.CanCollide = false
	overlay.CanQuery = false
	overlay.CanTouch = false
	overlay.Material = Enum.Material.SmoothPlastic
	overlay.Color = Color3.fromRGB(180, 110, 40)
	overlay.Transparency = 0.7
	overlay.Size = Vector3.new(tile.Size.X * 0.92, 0.15, tile.Size.Z * 0.92)
	overlay.CFrame = tile.CFrame * CFrame.new(0, tile.Size.Y * 0.5 + 0.1, 0)
	overlay.Parent = workspace
	Debris:AddItem(overlay, duration + 0.3)

	local tween = TweenService:Create(overlay, TweenInfo.new(duration * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 1, true), {
		Transparency = 0.85,
		Size = Vector3.new(tile.Size.X * 1.02, 0.15, tile.Size.Z * 1.02),
	})
	tween:Play()
end

local function fallDust(tile)
	if not tile or not tile:IsA("BasePart") then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = tile.CFrame
	anchor.Parent = workspace
	Debris:AddItem(anchor, 1.5)

	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(180, 160, 120))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 3.5),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Speed = NumberRange.new(2, 6)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Acceleration = Vector3.new(0, -15, 0)
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(18)
end

shrinkTileEvent.OnClientEvent:Connect(function(phase, tile, duration)
	if typeof(phase) ~= "string" then
		return
	end
	if phase == "Clear" then
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name == "ShrinkWarnPulse" then
				child:Destroy()
			end
		end
		return
	end
	if phase == "Warn" then
		pulseWarn(tile, typeof(duration) == "number" and duration or 2.5)
	elseif phase == "Fall" then
		fallDust(tile)
	end
end)
