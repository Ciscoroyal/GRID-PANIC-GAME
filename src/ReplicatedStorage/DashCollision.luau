local Debris = game:GetService("Debris")

local DashCollision = {}

local ATTACHMENT_NAME = "DashForceAttachment"
local VELOCITY_NAME = "DashLinearVelocity"

-- Finite force so CanCollide walls/Barriers can stop the dash (math.huge tunnels).
local FORCE_PER_MASS = 12000
local MIN_MAX_FORCE = 80000

local function flattenDirection(direction)
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.001 then
		return nil
	end
	return direction.Unit
end

local function clearDashForce(rootPart)
	if not rootPart then
		return
	end
	local existing = rootPart:FindFirstChild(VELOCITY_NAME)
	if existing then
		existing:Destroy()
	end
	local attachment = rootPart:FindFirstChild(ATTACHMENT_NAME)
	if attachment then
		attachment:Destroy()
	end
end

--[[
	Physics dash via LinearVelocity so solid geometry blocks travel.
	Y velocity is held at 0 for the dash so air and ground feel the same.
	Open-space travel ~= distance over duration.
]]
function DashCollision.applyPhysicsDash(rootPart, direction, distance, duration)
	if not rootPart or not rootPart.Parent then
		return false
	end

	local flatDir = flattenDirection(direction)
	if not flatDir then
		return false
	end

	distance = math.max(0, distance or 0)
	duration = math.max(0.05, duration or 0.25)
	if distance <= 0.05 then
		return false
	end

	clearDashForce(rootPart)

	local attachment = Instance.new("Attachment")
	attachment.Name = ATTACHMENT_NAME
	attachment.Parent = rootPart

	local speed = distance / duration
	local maxForce = math.max(MIN_MAX_FORCE, rootPart.AssemblyMass * FORCE_PER_MASS)

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = VELOCITY_NAME
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	-- Vector mode with Y=0 locks height so air dashes feel like ground dashes.
	-- Finite MaxForce still lets CanCollide walls/Barriers stop travel.
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	linearVelocity.VectorVelocity = Vector3.new(flatDir.X * speed, 0, flatDir.Z * speed)
	linearVelocity.MaxForce = maxForce
	linearVelocity.Parent = rootPart

	rootPart.AssemblyLinearVelocity = Vector3.new(flatDir.X * speed, 0, flatDir.Z * speed)

	Debris:AddItem(linearVelocity, duration)
	Debris:AddItem(attachment, duration + 0.05)

	task.delay(duration, function()
		if linearVelocity.Parent then
			linearVelocity:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
		if rootPart.Parent then
			local v = rootPart.AssemblyLinearVelocity
			rootPart.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end)

	return true
end

function DashCollision.cancel(rootPart)
	clearDashForce(rootPart)
	if rootPart and rootPart.Parent then
		local v = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
	end
end

return DashCollision
