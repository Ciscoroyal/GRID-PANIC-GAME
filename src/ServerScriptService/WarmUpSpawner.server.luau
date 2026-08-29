local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HazardHitService = require(ServerScriptService:WaitForChild("HazardHitService"))

local warmUpGrid = Workspace:WaitForChild("WarmUpGrid")
local hazardCubeModel = ServerStorage:WaitForChild("HazardCube")

-- Same visual pipeline the arena uses, so practice blocks fall identically.
local hazardVisualEvent = ReplicatedStorage:WaitForChild("HazardVisualEvent")
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")

local BASE_TILE_COLOR = BrickColor.new("Smoky grey")
local MAX_ACTIVE_HAZARDS = 3
local activeHazardCount = 0

-- Matched to HazardSpawner so the drop reads the same in both places.
local SPAWN_HEIGHT = 20
local FALL_SPEED = 50
local TELEGRAPH_SECONDS = 1

local reservedTiles = {}
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

local function resetTile(tile)
	tile.BrickColor = BASE_TILE_COLOR
	tile.Color = BASE_TILE_COLOR.Color
	tile.Material = Enum.Material.Concrete
end

local function pickAvailableTile(tiles)
	local available = {}
	for _, tile in ipairs(tiles) do
		if not reservedTiles[tile] then
			table.insert(available, tile)
		end
	end
	if #available == 0 then
		return nil
	end
	return available[math.random(1, #available)]
end

local function hasPracticePlayer()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InPractice") == true then
			return true
		end
	end
	return false
end

--[[
	Identical drop to the arena: the tile telegraphs, every client tweens the
	visual cube against an absolute server timestamp, and the server checks the
	impact box on the exact millisecond it lands. Practice keeps its own gentle
	spawn rate and only warns the player instead of eliminating them.
]]
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

	local targetTile = pickAvailableTile(tiles)
	if not targetTile then
		return
	end

	activeHazardCount += 1
	reservedTiles[targetTile] = true

	targetTile.Color = Color3.fromRGB(210, 40, 40)
	targetTile.Material = Enum.Material.Concrete

	local fallTime = (SPAWN_HEIGHT - 2) / FALL_SPEED
	local dropTimestamp = Workspace:GetServerTimeNow() + TELEGRAPH_SECONDS
	local impactTimestamp = dropTimestamp + fallTime

	-- Clients start the fall immediately; the tween is anchored to dropTimestamp.
	hazardVisualEvent:FireAllClients(targetTile, SPAWN_HEIGHT, fallTime, dropTimestamp)

	local waitTime = impactTimestamp - Workspace:GetServerTimeNow()
	if waitTime > 0 then
		task.wait(waitTime)
	end

	resetTile(targetTile)

	-- Impact check on the exact frame the cube lands, using the same rules as
	-- the arena so practice teaches the real hitbox.
	local hitPlayers = HazardHitService.getPlayersHit(targetTile, function(player)
		return player:GetAttribute("InPractice") == true
	end)

	for _, player in ipairs(hitPlayers) do
		vfxEvent:FireClient(player, "PracticeHit", "You were hit by a practice block!")
	end

	-- Brief invisible server hitbox, mirroring the arena, for anything that
	-- still relies on touching a real part.
	local serverHitbox = hazardCubeModel:Clone()
	-- Strip both touch-based scripts: the check above is authoritative and uses
	-- the fair hitbox, so a second touch path would only reintroduce the old
	-- over-reach.
	for _, descendant in ipairs(serverHitbox:GetDescendants()) do
		if descendant:IsA("BaseScript")
			and (descendant.Name == "EliminationScript" or descendant.Name == "PracticeHitScript")
		then
			descendant:Destroy()
		end
	end

	for _, part in ipairs(serverHitbox:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 1
			part.Anchored = true
			part.CanCollide = false
		end
	end

	local tileTopY = targetTile.Position.Y + (targetTile.Size.Y / 2)
	local restingHeight = (serverHitbox.PrimaryPart and serverHitbox.PrimaryPart.Size.Y / 2) or 4
	serverHitbox:PivotTo(targetTile.CFrame * CFrame.new(0, tileTopY + restingHeight, 0))
	serverHitbox.Parent = Workspace

	task.wait(0.03)

	if serverHitbox and serverHitbox.Parent then
		serverHitbox:Destroy()
	end

	task.delay(0.4, function()
		reservedTiles[targetTile] = nil
	end)

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