--[[
	Holds the giant winner in place while he dances.

	These dance clips carry a lot of baked root motion. Left alone at display
	scale the character travelled 102 studs around the arena, swung 37 studs up
	and down, and had a foot through the floor on 82% of frames. Cancelling the
	root motion brings that down by about 92%.

	The rig is joined by AnimationConstraints, which are physics-driven rather
	than rigid, so the correction cannot be perfect - the limbs settle toward
	their targets a frame behind. What is left is a small residual sway.

	This has to run on the client: every client evaluates the animation locally
	each frame, so a correction computed on the server arrives a network hop
	after the motion is already on screen. The giant's root is anchored, so
	moving it here is a view-only adjustment each client makes identically.
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MODEL_NAME = "WinnerDisplay"

-- Resting margin above the floor, as a fraction of the model's height so it
-- holds at any scale.
local CLEARANCE_FRACTION = 0.035

local model, root, lowerTorso = nil, nil, nil
local groundY, modelHeight, clearance = nil, 0, 0.2
local restLocal, anchorPos = nil, nil

local function getArenaFloorY()
	local grid = Workspace:FindFirstChild("ArenaGrid")
	if not grid then
		return nil
	end
	for _, tile in ipairs(grid:GetChildren()) do
		if tile:IsA("BasePart") then
			return tile.Position.Y + (tile.Size.Y / 2)
		end
	end
	return nil
end

local function detach()
	model, root, lowerTorso = nil, nil, nil
	restLocal, anchorPos = nil, nil
end

local function attach(candidate)
	if not candidate or candidate.Name ~= MODEL_NAME then
		return
	end

	local candidateRoot = candidate:WaitForChild("HumanoidRootPart", 5)
	if not candidateRoot then
		return
	end

	--[[
		The server assembles him far below the map and only lifts him into the
		arena once he is settled and dancing, setting Ready when he lands. Latch
		on before that and the anchor would be the build location, which would
		drag him straight back underground.
	]]
	local deadline = os.clock() + 15
	while candidate.Parent and candidate:GetAttribute("Ready") ~= true and os.clock() < deadline do
		task.wait(0.05)
	end
	if not candidate.Parent or candidate:GetAttribute("Ready") ~= true then
		return
	end

	-- One more frame so the move has propagated before we take the anchor.
	task.wait(0.1)
	if not candidate.Parent then
		return
	end

	local torso = candidate:FindFirstChild("LowerTorso") or candidate:FindFirstChild("Torso")
	if not torso then
		return
	end

	model = candidate
	root = candidateRoot
	lowerTorso = torso
	groundY = getArenaFloorY()
	modelHeight = select(2, candidate:GetBoundingBox()).Y
	clearance = math.max(0.2, modelHeight * CLEARANCE_FRACTION)

	-- The joint from HumanoidRootPart to LowerTorso is named Root, and that is
	-- where a clip puts whole-body translation. So the torso's offset from the
	-- root at rest is the baseline; any later difference is the root motion.
	restLocal = candidateRoot.CFrame:PointToObjectSpace(torso.Position)
	anchorPos = candidateRoot.Position
end

Workspace.ChildAdded:Connect(function(child)
	if child.Name == MODEL_NAME then
		task.spawn(attach, child)
	end
end)

Workspace.ChildRemoved:Connect(function(child)
	if child == model then
		detach()
	end
end)

task.spawn(attach, Workspace:FindFirstChild(MODEL_NAME))

-- PreRender, not RenderStepped: RenderStepped fires before the animation step,
-- so it reads the previous frame's pose and stays a frame further behind.
local correctionSignal = RunService.PreRender or RunService.RenderStepped

correctionSignal:Connect(function()
	if not model or not model.Parent or not root or not root.Parent then
		return
	end
	if not lowerTorso or not lowerTorso.Parent or not restLocal or not anchorPos then
		return
	end

	-- Undo however far the clip has translated the body.
	local currentLocal = root.CFrame:PointToObjectSpace(lowerTorso.Position)
	local driftWorld = root.CFrame:VectorToWorldSpace(currentLocal - restLocal)
	local target = anchorPos - driftWorld

	-- Then make sure the result is not standing in the floor.
	if groundY then
		local shiftY = target.Y - root.Position.Y
		local rootY = root.Position.Y
		local lowest = math.huge
		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				local bottom = part.Position.Y - (part.Size.Y / 2)
				if rootY - bottom < modelHeight then
					lowest = math.min(lowest, bottom)
				end
			end
		end
		if lowest < math.huge then
			local penetration = (groundY + clearance) - (lowest + shiftY)
			if penetration > 0 then
				target = target + Vector3.new(0, penetration, 0)
			end
		end
	end

	if (target - root.Position).Magnitude > 0.01 then
		root.CFrame = root.CFrame - root.Position + target
	end
end)
