--[[
	Decides who a falling hazard actually hits.

	The original test was workspace:GetPartBoundsInBox over the tile, which
	catches any body part whose AXIS-ALIGNED bounding box overlaps. A rotated
	arm or foot has a far larger box than the limb itself, so in practice the
	kill reached 6.5 studs from the tile centre while the block's visible edge
	sits at 4.0 - players died standing a third of a tile clear of it.

	This tests a single point instead: the character's centre against the tile
	footprint. What you see is what kills you.

	It also projects that point forward by the player's ping. The server's copy
	of a character trails the player's own screen by roughly their latency, so
	someone who had already run off the tile locally would still be standing on
	it in the server's view. Extrapolating along their current velocity spares
	them - the hazard equivalent of favouring the shooter.
]]
local Players = game:GetService("Players")

local HazardHitService = {}

--[[
	Slack around the tile edge, in studs.

	Tiles are 7.60 studs but sit on an 8.00 stud grid, so there is a 0.40 stud
	gap between every one of them. At zero tolerance those seams were dead
	ground the hazard could never reach - standing on a 4-tile corner made you
	permanently immune.

	0.20 would extend the footprint to exactly 8.00 - but then neighbouring
	tiles meet precisely on the seam, and standing dead on it fails the boundary
	comparison on floating point, leaving the corner immune anyway. 0.25 makes
	adjacent footprints overlap by a hair so the seam is always covered by both.
]]
local EDGE_TOLERANCE = 0.25

-- Vertical span, measured from the tile's centre. HEIGHT_ABOVE is deliberately
-- taller than any reachable jump: hazards are not meant to be jumpable.
local HEIGHT_BELOW = 3
local HEIGHT_ABOVE = 14

-- Cap on how much latency we will forgive, so a very laggy client cannot buy
-- itself a large head start.
local MAX_LAG_COMPENSATION = 0.2

local function getCompensatedPosition(player, root)
	local ping = 0
	local ok, value = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and typeof(value) == "number" then
		ping = math.clamp(value, 0, MAX_LAG_COMPENSATION)
	end

	if ping <= 0 then
		return root.Position
	end

	-- Horizontal only: falling or jumping should not shift the footprint test.
	local velocity = root.AssemblyLinearVelocity
	return root.Position + (Vector3.new(velocity.X, 0, velocity.Z) * ping)
end

function HazardHitService.isPlayerHit(player, tile)
	if not player or not player.Parent or not tile or not tile.Parent then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end

	local offset = tile.CFrame:PointToObjectSpace(getCompensatedPosition(player, root))

	if math.abs(offset.X) > (tile.Size.X / 2) + EDGE_TOLERANCE then
		return false
	end
	if math.abs(offset.Z) > (tile.Size.Z / 2) + EDGE_TOLERANCE then
		return false
	end
	if offset.Y < -HEIGHT_BELOW or offset.Y > HEIGHT_ABOVE then
		return false
	end

	return true
end

--[[
	Returns every player the hazard on `tile` should hit. `filter` narrows the
	candidates (in the arena, in practice, and so on).
]]
function HazardHitService.getPlayersHit(tile, filter)
	local hit = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if (not filter or filter(player)) and HazardHitService.isPlayerHit(player, tile) then
			table.insert(hit, player)
		end
	end
	return hit
end

return HazardHitService
