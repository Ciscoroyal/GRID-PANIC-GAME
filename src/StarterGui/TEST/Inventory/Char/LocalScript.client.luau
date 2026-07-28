local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local playerscripts = game:GetService("Players").LocalPlayer.PlayerScripts

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

repeat wait(4) until game:IsLoaded()


local viewportFrame = script.Parent

character.Archivable = true
local clone = character:Clone()
clone.PrimaryPart.Anchored = true

local worldModel = Instance.new("WorldModel")
worldModel.Parent = viewportFrame
clone.Parent = worldModel

local camera = viewportFrame.CurrentCamera
if not camera then
	camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera
end

local cf, size = clone:GetBoundingBox()

local maxSize = math.max(size.X, size.Y, size.Z)
local fov = math.rad(camera.FieldOfView)
local distance = (maxSize / 2) / math.tan(fov / 2)

distance = distance * 1.5

camera.CFrame = CFrame.new(cf.Position + Vector3.new(-distance * 0.2, 0, -distance), cf.Position)


--local npc = script.Parent
--local humanoid = npc:WaitForChild("Humanoid")

--local success, appearanceData = pcall(function()
--	return Remotes.Get("RequestHumanoidDescription"):InvokeServer(player.UserId) -- Replace with the actual player's User ID
--end)

--if success and appearanceData then
--	-- Apply the downloaded outfit, accessories, and body parts to the dummy
--	humanoid:ApplyDescriptionAsync(appearanceData)
--else
--	warn("Failed to load the player's appearance. Check the User ID or your connection.")
--end