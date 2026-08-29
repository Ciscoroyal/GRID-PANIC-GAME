local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()

local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

local Head = Character:FindFirstChild("Head")

local connections = {}
local settings = {
	xShake = 0,
	yShake = 0,
	zShake = 0,
}

connections["HeartBeat"] = RunService.Heartbeat:Connect(function( deltaTime )
	if not Character or not HumanoidRootPart then return end

	local defaultOffset = Vector3.new( 0 + settings.xShake, -1.25 + settings.yShake, 0 + settings.zShake )
	local camOffset = defaultOffset

	if not Character:HasTag('NoHeadFollow') then
		camOffset += HumanoidRootPart.CFrame:ToObjectSpace(Head.CFrame).Position
	end

	local offsetLerp = Humanoid.CameraOffset:Lerp(camOffset, 1 - 2.5E-5 ^ deltaTime)
	local offsetMagnitude = (HumanoidRootPart.Position - (HumanoidRootPart.Position + offsetLerp)).Magnitude

	local offsetCFrame = HumanoidRootPart.CFrame * CFrame.new(Vector3.new(0, 1.5, 0) + offsetLerp)

	if (offsetMagnitude > 1000) or (offsetCFrame.Position - HumanoidRootPart.Position).Magnitude > 1000 then
		offsetLerp = defaultOffset
	end

	Humanoid.CameraOffset = offsetLerp
end)