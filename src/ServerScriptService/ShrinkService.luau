local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local shrinkTileEvent = ReplicatedStorage:WaitForChild("ShrinkTileEvent")

local ShrinkService = {}

local BASE_TILE_COLOR = BrickColor.new("Smoky grey")
local BASE_MATERIAL = Enum.Material.Concrete
local WARN_COLOR = Color3.fromRGB(170, 95, 30)
local FALL_DEPTH = 40

local GRACE_SECONDS = 10
local WARN_SECONDS = 1.2
local FALL_SECONDS = 1.35
local RING_DROP_SECONDS = 20 -- peel one ring over this duration
local SAFE_RING_MAX = 1 -- rings 0 and 1 stay

local active = false
local runToken = 0
local fallenTiles = {} -- [BasePart] = true
local originals = {} -- [BasePart] = { cf }
local homeCFrames = {} -- persistent spawn CFrames for full grid reset
local activeTweens = {} -- [BasePart] = { Tween }
local arenaBaseState = nil -- { transparency, canCollide, canQuery }

local function getArenaBase()
	local env = workspace:FindFirstChild("Environment")
	if not env then
		return nil
	end
	local base = env:FindFirstChild("Arena Base")
	if base and base:IsA("BasePart") then
		return base
	end
	return nil
end

local function setArenaBaseVisible(visible)
	local base = getArenaBase()
	if not base then
		return
	end
	if visible then
		if arenaBaseState then
			base.Transparency = arenaBaseState.transparency
			base.CanCollide = arenaBaseState.canCollide
			base.CanQuery = arenaBaseState.canQuery
		else
			base.Transparency = 0
			base.CanCollide = true
			base.CanQuery = true
		end
		arenaBaseState = nil
	else
		if not arenaBaseState then
			arenaBaseState = {
				transparency = base.Transparency,
				canCollide = base.CanCollide,
				canQuery = base.CanQuery,
			}
		end
		-- Hidden + non-collidable so fallen tiles create real holes
		base.Transparency = 1
		base.CanCollide = false
		base.CanQuery = false
	end
end

local function cancelTileTweens(tile)
	local tweens = activeTweens[tile]
	if not tweens then
		return
	end
	for _, tween in ipairs(tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	activeTweens[tile] = nil
end

local function trackTween(tile, tween)
	if not tile or not tween then
		return
	end
	activeTweens[tile] = activeTweens[tile] or {}
	table.insert(activeTweens[tile], tween)
	tween.Completed:Once(function()
		local list = activeTweens[tile]
		if not list then
			return
		end
		for i = #list, 1, -1 do
			if list[i] == tween then
				table.remove(list, i)
			end
		end
		if #list == 0 then
			activeTweens[tile] = nil
		end
	end)
end

local function applyBaseLook(tile)
	tile.BrickColor = BASE_TILE_COLOR
	tile.Color = BASE_TILE_COLOR.Color
	tile.Material = BASE_MATERIAL
	tile.CanCollide = true
	tile.Transparency = 0
	tile.Anchored = true
end

local function storeOriginal(tile)
	if originals[tile] then
		return
	end
	-- Only store CFrame; always restore to base look (never capture hazard red / warn amber)
	originals[tile] = {
		cf = tile.CFrame,
	}
end

local function buildRings(tiles)
	local cx, cz = 0, 0
	for _, tile in ipairs(tiles) do
		cx += tile.Position.X
		cz += tile.Position.Z
	end
	cx /= math.max(#tiles, 1)
	cz /= math.max(#tiles, 1)

	local tileSize = 7.6
	if tiles[1] then
		tileSize = math.max(tiles[1].Size.X, tiles[1].Size.Z)
	end

	local byRing = {}
	local maxRing = 0
	for _, tile in ipairs(tiles) do
		local dx = math.abs(tile.Position.X - cx) / tileSize
		local dz = math.abs(tile.Position.Z - cz) / tileSize
		local ring = math.floor(math.max(dx, dz) + 0.05)
		byRing[ring] = byRing[ring] or {}
		table.insert(byRing[ring], tile)
		maxRing = math.max(maxRing, ring)
	end
	return byRing, maxRing
end

function ShrinkService.isFallen(tile)
	return fallenTiles[tile] == true
end

function ShrinkService.isActive()
	return active
end

local function restoreTile(tile)
	cancelTileTweens(tile)
	local cf = homeCFrames[tile] or (originals[tile] and originals[tile].cf)
	if cf then
		tile.Anchored = true
		tile.CFrame = cf
	end
	applyBaseLook(tile)
	fallenTiles[tile] = nil
end

function ShrinkService.restoreAll()
	-- Cancel in-flight fall tweens first so they can't re-hide tiles after restore
	for tile in pairs(activeTweens) do
		cancelTileTweens(tile)
	end

	local grid = workspace:FindFirstChild("ArenaGrid")
	if grid then
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("BasePart") then
				restoreTile(child)
			end
		end
	end

	for tile in pairs(originals) do
		if tile and tile.Parent then
			restoreTile(tile)
		end
	end

	table.clear(fallenTiles)
	table.clear(originals)
	setArenaBaseVisible(true)
	pcall(function()
		shrinkTileEvent:FireAllClients("Clear", nil, 0)
	end)
end

function ShrinkService.stop()
	runToken += 1
	active = false
end

local function dropTile(tile, token)
	if token ~= runToken or not tile or not tile.Parent then
		return
	end
	if fallenTiles[tile] then
		return
	end

	storeOriginal(tile)
	fallenTiles[tile] = true

	local startCF = homeCFrames[tile] or originals[tile].cf
	local tip = CFrame.Angles(math.rad(math.random(12, 22) * (math.random(0, 1) == 0 and -1 or 1)), 0, math.rad(math.random(8, 16) * (math.random(0, 1) == 0 and -1 or 1)))
	local midCF = startCF * tip * CFrame.new(0, -2, 0)
	local endCF = startCF * tip * CFrame.new(0, -FALL_DEPTH, 0)

	shrinkTileEvent:FireAllClients("Fall", tile, FALL_SECONDS)

	cancelTileTweens(tile)
	tile.CanCollide = false
	local tipTween = TweenService:Create(tile, TweenInfo.new(FALL_SECONDS * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = midCF })
	trackTween(tile, tipTween)
	tipTween:Play()
	tipTween.Completed:Wait()
	if token ~= runToken then
		return
	end

	local fallTween = TweenService:Create(tile, TweenInfo.new(FALL_SECONDS * 0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = endCF, Transparency = 1 })
	trackTween(tile, fallTween)
	fallTween:Play()
	fallTween.Completed:Wait()
end

local function shuffleInPlace(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
end

local function warnAndDropRing(tiles, token)
	if #tiles == 0 then
		return
	end

	-- Peel tiles one-by-one across RING_DROP_SECONDS (not all at once)
	local order = table.clone(tiles)
	shuffleInPlace(order)
	local spacing = RING_DROP_SECONDS / math.max(#order, 1)

	for i, tile in ipairs(order) do
		if token ~= runToken then
			return
		end
		if not fallenTiles[tile] and tile.Parent then
			storeOriginal(tile)
			tile.Color = WARN_COLOR
			tile.Material = Enum.Material.SmoothPlastic
			shrinkTileEvent:FireAllClients("Warn", tile, WARN_SECONDS)
			task.spawn(function()
				task.wait(WARN_SECONDS)
				if token ~= runToken then
					return
				end
				dropTile(tile, token)
			end)
		end
		if i < #order then
			task.wait(spacing)
		end
	end

	-- Next layer starts immediately after this ring's peels are queued
	task.wait(0.2)
end

function ShrinkService.start(tiles)
	ShrinkService.stop()
	ShrinkService.restoreAll()

	if typeof(tiles) ~= "table" or #tiles == 0 then
		return
	end

	-- Snapshot pristine CFrames + force base look before any hazards paint tiles
	table.clear(homeCFrames)
	for _, tile in ipairs(tiles) do
		if tile and tile:IsA("BasePart") then
			applyBaseLook(tile)
			homeCFrames[tile] = tile.CFrame
			originals[tile] = { cf = tile.CFrame }
		end
	end

	setArenaBaseVisible(false)

	active = true
	runToken += 1
	local token = runToken

	local byRing, maxRing = buildRings(tiles)
	local dropOrder = {}
	for ring = maxRing, SAFE_RING_MAX + 1, -1 do
		if byRing[ring] then
			table.insert(dropOrder, byRing[ring])
		end
	end

	task.spawn(function()
		task.wait(GRACE_SECONDS)
		if token ~= runToken then
			return
		end

		for _, ringTiles in ipairs(dropOrder) do
			if token ~= runToken then
				return
			end
			warnAndDropRing(ringTiles, token)
		end
	end)
end

return ShrinkService
