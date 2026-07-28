local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris") 
local Workspace = game:GetService("Workspace")

local hazardVisualEvent = ReplicatedStorage:WaitForChild("HazardVisualEvent")
local visualHazardModel = ReplicatedStorage:WaitForChild("VisualHazardCube")

hazardVisualEvent.OnClientEvent:Connect(function(targetTile, spawnHeight, fallTime, dropTimestamp)
	local currentTime = workspace:GetServerTimeNow()
	local delayNeeded = dropTimestamp - currentTime

	if delayNeeded > 0 then
		task.wait(delayNeeded)
	end

	local visualCube = visualHazardModel:Clone()
	visualCube.Parent = Workspace

	-- FIX 3: The Debris Safety Net. 
	-- Even if the player's computer freezes and the Tween breaks, Debris forces it into the trash.
	Debris:AddItem(visualCube, fallTime + 1)

	local startCFrame = targetTile.CFrame * CFrame.new(0, spawnHeight, 0)
	local endCFrame = targetTile.CFrame * CFrame.new(0, 2, 0) 

	visualCube:PivotTo(startCFrame)

	local tweenInfo = TweenInfo.new(
		fallTime, 
		Enum.EasingStyle.Linear, 
		Enum.EasingDirection.Out
	)

	local primaryPart = visualCube.PrimaryPart
	if not primaryPart then return end

	local tween = TweenService:Create(primaryPart, tweenInfo, {CFrame = endCFrame})
	tween:Play()

	tween.Completed:Connect(function()
		task.wait(0.15)
		if visualCube and visualCube.Parent then
			visualCube:Destroy()
		end
	end)
end)