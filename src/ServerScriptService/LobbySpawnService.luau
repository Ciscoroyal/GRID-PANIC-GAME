--[[
	Where players stand when they arrive in the lobby.

	Every path into the lobby - joining, being eliminated, returning from
	practice, the whole field being sent back at the end of a round - used the
	exact same point (LobbySpawn.CFrame * CFrame.new(0, 3, 0)), so everyone
	ended up stacked inside one another. This scatters them over a small disc
	around the spawn instead.
]]
local Workspace = game:GetService("Workspace")

local LobbySpawnService = {}

-- How far out from the spawn pad people may land.
local MIN_RADIUS = 3
local MAX_RADIUS = 11
local HEIGHT = 3

function LobbySpawnService.getSpawn()
	return Workspace:FindFirstChild("LobbySpawn")
end

--[[
	A randomised standing spot near the lobby spawn, facing outward from it so
	arrivals are not all staring the same way.
]]
function LobbySpawnService.getSpawnCFrame()
	local spawn = LobbySpawnService.getSpawn()
	if not spawn then
		return nil
	end

	local angle = math.random() * math.pi * 2
	-- Square root keeps the scatter even across the disc rather than clumping
	-- everyone toward the middle.
	local radius = MIN_RADIUS + ((MAX_RADIUS - MIN_RADIUS) * math.sqrt(math.random()))

	local offset = Vector3.new(math.cos(angle) * radius, HEIGHT, math.sin(angle) * radius)
	local position = spawn.Position + offset

	-- Face away from the pad, so a crowd fans outward.
	local lookAt = position + Vector3.new(offset.X, 0, offset.Z)
	return CFrame.lookAt(position, lookAt)
end

--[[
	Places a character at a scattered lobby spot. Returns false if there is no
	lobby spawn or the character is not ready.
]]
function LobbySpawnService.placeCharacter(character)
	if not character or not character.Parent then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local cframe = LobbySpawnService.getSpawnCFrame()
	if not cframe then
		return false
	end

	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

return LobbySpawnService
