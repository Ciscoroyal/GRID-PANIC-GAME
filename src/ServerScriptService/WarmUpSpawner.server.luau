local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local warmUpGrid = Workspace:WaitForChild("WarmUpGrid")
local hazardCubeModel = ServerStorage:WaitForChild("HazardCube")
local practiceHitTemplate = ServerStorage:WaitForChild("PracticeHitScript")

local BASE_TILE_COLOR = BrickColor.new("Smoky grey")
local MAX_ACTIVE_HAZARDS = 3
local activeHazardCount = 0

local cachedPracticeTiles = {}

local function getGridTiles(grid)
	local tiles = {}
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(tiles, child)
		end
	end
	return tiles
end

local function getTrackingPart(hazardModel)
	return hazardModel:FindFirstChild("Hitbox", true)
		or hazardModel.PrimaryPart
		or hazardModel:FindFirstChild("VisualCube", true)
end

local function resetTile(tile)
	tile.BrickColor = BASE_TILE_COLOR
	tile.Color = BASE_TILE_COLOR.Color
	tile.Material = Enum.Material.Concrete
end

local function dropHazardToTile(hazardModel, targetTile)
	local tileTopY = targetTile.Position.Y + (targetTile.Size.Y / 2)
	local sinkTargetY = tileTopY - 2
	local fallSpeed = 50
	local sinkSettleTime = 0.15
	local deadline = os.clock() + 5

	for _, part in ipairs(hazardModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end

	local finished = false
	local sinking = false
	local tileReset = false
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if finished or not hazardModel.Parent then
			connection:Disconnect()
			return
		end
		if os.clock() > deadline then
			finished = true
			connection:Disconnect()
			if not tileReset then
				resetTile(targetTile)
			end
			return
		end
		local trackingPart = getTrackingPart(hazardModel)
		if not trackingPart then
			return
		end
		hazardModel:PivotTo(hazardModel:GetPivot() * CFrame.new(0, -fallSpeed * dt, 0))
		local partBottomY = trackingPart.Position.Y - (trackingPart.Size.Y / 2)
		if not sinking and partBottomY <= tileTopY + 0.25 then
			sinking = true
			if not tileReset then
				resetTile(targetTile)
				tileReset = true
			end
		end
		if sinking and partBottomY <= sinkTargetY then
			finished = true
			connection:Disconnect()
		end
	end)

	while not finished and hazardModel.Parent and os.clock() < deadline do
		task.wait()
	end

	if connection.Connected then
		connection:Disconnect()
	end

	if sinking and hazardModel.Parent then
		task.wait(sinkSettleTime)
	end

	if not tileReset then
		resetTile(targetTile)
	end
end

local function hasPracticePlayer()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InPractice") == true then
			return true
		end
	end
	return false
end

local function preparePracticeHazard(hazardModel)
	local hitbox = hazardModel:FindFirstChild("Hitbox", true)
	if not hitbox then
		return
	end

	local eliminationScript = hitbox:FindFirstChild("EliminationScript")
	if eliminationScript then
		eliminationScript:Destroy()
	end

	if not hitbox:FindFirstChild("PracticeHitScript") then
		practiceHitTemplate:Clone().Parent = hitbox
	end
end

local function spawnPracticeHazard()
	if not hasPracticePlayer() then
		return
	end

	if activeHazardCount >= MAX_ACTIVE_HAZARDS then
		return
	end

	if #cachedPracticeTiles == 0 then
		cachedPracticeTiles = getGridTiles(warmUpGrid)
	end
	local tiles = cachedPracticeTiles
	if #tiles == 0 then
		return
	end

	activeHazardCount += 1

	local randomTile = tiles[math.random(1, #tiles)]
	randomTile.Color = Color3.fromRGB(210, 40, 40)
	randomTile.Material = Enum.Material.Concrete

	task.wait(1)

	local newHazard = hazardCubeModel:Clone()
	preparePracticeHazard(newHazard)
	local spawnHeight = 20 + ((newHazard.PrimaryPart and newHazard.PrimaryPart.Size.Y or 8) / 2)
	newHazard:PivotTo(randomTile.CFrame * CFrame.new(0, spawnHeight, 0))
	newHazard.Parent = Workspace

	dropHazardToTile(newHazard, randomTile)

	if newHazard and newHazard.Parent then
		newHazard:Destroy()
	end

	activeHazardCount -= 1
end

-- The Upgraded Practice Loop
while true do
	if hasPracticePlayer() then
		task.spawn(spawnPracticeHazard)
		task.wait(math.random(60, 100) / 100)
	else
		task.wait(1)
	end
end