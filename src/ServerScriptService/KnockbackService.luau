--[[
	Knockback for combat abilities.

	The original implementation tweened the victim's HumanoidRootPart CFrame.
	That writes position directly, so it ignored the world completely: a punched
	player passed straight through collidable walls, and because the tween held
	Y at the starting height for its full 0.25s, victims glided level out over
	the void (and clean over one-tile holes) before gravity was allowed to act.
	It also fought the client that owns the character, causing rubber-banding.

	This launches them instead. We set the assembly velocity once and let the
	physics engine do the rest, exactly as the dash does - so walls stop them,
	gravity arcs them, holes catch them, and the owning client simulates it
	smoothly.

	Distances are expressed in TILES and converted using the arena's real tile
	size, so "one tile" in an ability description means one tile on the floor.
]]
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local KnockbackService = {}

local ATTACHMENT_NAME = "KnockbackAttachment"
local VELOCITY_NAME = "KnockbackVelocity"

-- Finite force, same reasoning as the dash: enough to overpower the Humanoid's
-- braking, but low enough that a CanCollide wall still stops the victim.
local FORCE_PER_MASS = 16000
local MIN_MAX_FORCE = 100000

-- How high the victim pops. The arc is what makes a hit read as a hit; it also
-- sets how long they are airborne, which is how the distance is delivered.
local POP_HEIGHT_STUDS = 3

-- Used only if the arena grid cannot be measured.
local DEFAULT_TILE_SIZE = 7.6



local cachedTileSize = nil

function KnockbackService.getTileSize()
	if cachedTileSize then
		return cachedTileSize
	end
	local grid = Workspace:FindFirstChild("ArenaGrid")
	if grid then
		for _, child in ipairs(grid:GetChildren()) do
			if child:IsA("BasePart") then
				cachedTileSize = math.max(child.Size.X, child.Size.Z)
				return cachedTileSize
			end
		end
	end
	return DEFAULT_TILE_SIZE
end

function KnockbackService.tilesToStuds(tiles)
	return (tiles or 0) * KnockbackService.getTileSize()
end

--[[
	Launches `character` along `direction` so that, left undisturbed, it lands
	roughly `distanceStuds` away. Returns false if the hit could not be applied.
]]
function KnockbackService.apply(character, direction, distanceStuds)
	if not character or not character.Parent then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.001 then
		return false
	end
	flat = flat.Unit

	distanceStuds = math.max(0, distanceStuds or 0)
	if distanceStuds <= 0.05 then
		return false
	end

	local gravity = Workspace.Gravity
	if gravity <= 0 then
		gravity = 196.2
	end

	-- Vertical speed for the requested pop, and the airtime it buys us.
	local upSpeed = math.sqrt(2 * gravity * POP_HEIGHT_STUDS)
	local airTime = (2 * upSpeed) / gravity

	-- Horizontal speed chosen so they cover the distance while airborne.
	local horizontalSpeed = distanceStuds / airTime

	--[[
		Leave the ground first: a Humanoid in the Running state damps the launch.
		The state change is a request, so give the controller a beat to act on it
		before the velocity is written - setting velocity on the same frame meant
		the brake sometimes ate the push, which is the other half of the
		inconsistency.
	]]
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end)
	task.wait()

	--[[
		Mute the default Animate script for the flight. Without this the victim
		keeps playing the run cycle while sailing backwards through the air, which
		looks absurd. Re-enabled when they land.
	]]
	local animate = character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Disabled = true

		local token = (character:GetAttribute("KnockbackToken") or 0) + 1
		character:SetAttribute("KnockbackToken", token)

		task.delay(airTime + 0.1, function()
			-- Only the most recent knockback restores, so overlapping hits do not
			-- un-mute someone who has just been hit again.
			if character.Parent and character:GetAttribute("KnockbackToken") == token then
				animate.Disabled = false
			end
		end)
	end

	-- Stop any ability/locomotion tracks already running on them.
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			pcall(function()
				track:Stop(0.05)
			end)
		end
	end

	-- Clear any knockback still in flight so hits do not compound.
	local existing = root:FindFirstChild(VELOCITY_NAME)
	if existing then
		existing:Destroy()
	end
	local oldAttachment = root:FindFirstChild(ATTACHMENT_NAME)
	if oldAttachment then
		oldAttachment:Destroy()
	end

	--[[
		Launch with the full ballistic vector - horizontal AND vertical - in one
		write. The old version set only the vertical component here and left the
		constraint below to build up the horizontal speed, so how far a victim
		travelled depended on how quickly the constraint took hold. That is the
		main reason the same punch sometimes shoved someone a tile and sometimes
		barely moved them.
	]]
	root.AssemblyLinearVelocity = (flat * horizontalSpeed) + Vector3.new(0, upSpeed, 0)

	--[[
		The horizontal push has to be a constraint, not a one-shot velocity. The
		Humanoid controller brakes horizontal motion - even in freefall - so a
		velocity set once is wiped within a frame or two (measured: 1.6 studs of
		travel on a 7.6 stud push). Line mode holds speed along the push axis
		while leaving every other axis free, so gravity still arcs them down.
	]]
	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = VELOCITY_NAME
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	velocity.LineDirection = flat
	velocity.LineVelocity = horizontalSpeed
	velocity.MaxForce = math.max(MIN_MAX_FORCE, root.AssemblyMass * FORCE_PER_MASS)
	velocity.Parent = root

	--[[
		End the push the moment they touch down, not on a fixed timer.

		airTime is derived from the pop height, but the real flight rarely matches
		it: a victim knocked into a wall, off an edge, or hit while already
		airborne lands early or late. On an early landing the constraint kept
		shoving them along the floor - the same hit could deliver well over its
		intended distance. Cutting it on landing makes the travel repeatable.
	]]
	local finished = false
	local landedConnection

	local function endPush()
		if finished then
			return
		end
		finished = true
		if landedConnection then
			landedConnection:Disconnect()
			landedConnection = nil
		end
		if velocity.Parent then
			velocity:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
	end

	landedConnection = humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics
			or newState == Enum.HumanoidStateType.Dead
		then
			endPush()
		end
	end)

	-- Backstop: never let the constraint outlive the expected flight by much,
	-- even if the landing state never arrives.
	task.delay(airTime, endPush)

	-- And a hard guarantee that nothing is left attached to drag the player.
	Debris:AddItem(velocity, airTime + 0.5)
	Debris:AddItem(attachment, airTime + 0.6)

	return true
end

return KnockbackService
