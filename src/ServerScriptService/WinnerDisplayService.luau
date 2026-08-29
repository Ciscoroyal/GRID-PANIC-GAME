--[[
	The giant winner that appears after a match, so it is obvious who took the
	round. It stands in the middle of the arena - where the match was just
	fought - facing the lobby, cycling through the dance clips below.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local WinnerDisplayService = {}

-- Played in order, then looped back to the first. All R15.
local DANCE_ANIMATION_IDS = {
	"rbxassetid://88617628368324",
	"rbxassetid://126014879484448",
	"rbxassetid://114576657969453",
	"rbxassetid://101096583914510",
}

-- Crossfade between clips, in seconds.
local DANCE_BLEND = 0.3

local MODEL_NAME = "WinnerDisplay"
local SCALE = 9

--[[
	Resting height above the floor. The per-frame correction below always reacts
	one frame after the animation poses the rig, so a fast dip can still clip
	through before it is caught - and the size of that overshoot scales with the
	model, so this is expressed per unit of scale rather than as a fixed number.
	Roughly 0.2 studs in character terms at any size.
]]
local GROUND_CLEARANCE = 0.22 * SCALE

-- Set once the giant is standing in its final spot. The client correction
-- waits for this before measuring, and nothing is shown until it is set.
local READY_ATTRIBUTE = "Ready"

-- How long to let the dance settle before revealing him.
local DANCE_SETTLE = 0.5

local currentModel = nil
local buildToken = 0

--[[
	Hide and reveal the whole model.

	The rig has to be in the workspace for physics to settle its limbs before we
	can measure where its feet actually are - but if it is visible while that
	happens, players watch it sitting in the floor and then jump up into place.
	So it goes in invisible and is only revealed once it is final.
]]
local function setModelHidden(model, hidden, saved)
	saved = saved or {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if hidden then
				saved[d] = d.Transparency
				d.Transparency = 1
			elseif saved[d] then
				d.Transparency = saved[d]
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			if hidden then
				saved[d] = d.Transparency
				d.Transparency = 1
			elseif saved[d] then
				d.Transparency = saved[d]
			end
		end
	end
	return saved
end

--[[
	The giant is assembled far below the map and only moved into the arena once
	he is already dancing.

	He has to be in the workspace before he can be measured - the limbs need a
	moment to settle against the root, and accessories stream in after the model
	is created - so there is unavoidably a second or so of him snapping into
	shape. Doing that in the arena is what looked like him climbing out of the
	floor. Hiding him with transparency did not work: the accessories that load
	in afterwards arrive fully opaque.
]]

function WinnerDisplayService.clear()
	buildToken += 1
	if currentModel then
		pcall(function()
			currentModel:Destroy()
		end)
		currentModel = nil
	end
	-- Catch any stragglers from a previous server state.
	local existing = Workspace:FindFirstChild(MODEL_NAME)
	while existing do
		existing:Destroy()
		existing = Workspace:FindFirstChild(MODEL_NAME)
	end
end

local function prepareModel(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	--[[
		The root is pinned after placement; everything else stays free so the
		clip can pose the body. Letting it stand as a real character instead was
		worse: a 9x Humanoid cannot balance itself and it fell through the world.
	]]
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			part.Anchored = false
		end
	end
end

-- Fisher-Yates, so the running order differs every time.
local function shuffled(list)
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = math.random(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Plays the dances back to back in a shuffled order, reshuffling after each
	pass. The same clip never plays twice in a row - including across the seam
	between one pass and the next.
]]
local function playDance(model, token)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return false
	end

	local tracks = {}
	for _, id in ipairs(DANCE_ANIMATION_IDS) do
		local ok, track = pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			tracks[#tracks + 1] = track
		end
	end

	if #tracks == 0 then
		return false
	end

	task.spawn(function()
		local order = shuffled(tracks)
		local index = 0
		local lastPlayed = nil

		while token == buildToken and model.Parent do
			index += 1
			if index > #order then
				-- New pass. Reshuffle, and if the first pick repeats the clip we
				-- just finished, swap it with the next one.
				order = shuffled(tracks)
				if #order > 1 and order[1] == lastPlayed then
					order[1], order[2] = order[2], order[1]
				end
				index = 1
			end

			local track = order[index]
			lastPlayed = track

			track:Play(DANCE_BLEND)

			-- Length reads 0 until the asset finishes loading.
			local deadline = os.clock() + 5
			while (typeof(track.Length) ~= "number" or track.Length <= 0) and os.clock() < deadline do
				task.wait()
			end
			local length = 3
			if typeof(track.Length) == "number" and track.Length > 0 then
				length = track.Length
			end

			-- Hand over just before the end so the blend covers the seam.
			task.wait(math.max(0.2, length - DANCE_BLEND))
			if token ~= buildToken then
				break
			end
			track:Stop(DANCE_BLEND)
		end

		for _, track in ipairs(tracks) do
			pcall(function()
				track:Stop(0)
			end)
		end
	end)

	return true
end

--[[
	Shows `player` as a giant in the lobby. Safe to call with nil (clears).
]]
function WinnerDisplayService.show(player)
	WinnerDisplayService.clear()

	if not player or not player.Parent then
		return
	end

	local spawn = Workspace:FindFirstChild("LobbySpawn")
	if not spawn then
		return
	end

	-- Centre of the arena floor: the giant stands where the match was fought.
	local grid = Workspace:FindFirstChild("ArenaGrid")
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	local tileTopY = nil
	if grid then
		for _, tile in ipairs(grid:GetChildren()) do
			if tile:IsA("BasePart") then
				minX = math.min(minX, tile.Position.X)
				maxX = math.max(maxX, tile.Position.X)
				minZ = math.min(minZ, tile.Position.Z)
				maxZ = math.max(maxZ, tile.Position.Z)
				tileTopY = tile.Position.Y + (tile.Size.Y / 2)
			end
		end
	end

	if minX == math.huge then
		return
	end

	local arenaCentre = Vector3.new((minX + maxX) / 2, tileTopY or 0, (minZ + maxZ) / 2)

	buildToken += 1
	local token = buildToken
	local userId = player.UserId

	task.spawn(function()
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromUserId(userId)
		end)
		if not ok or not model then
			return
		end
		-- A newer round started while the avatar was loading.
		if token ~= buildToken then
			model:Destroy()
			return
		end

		model.Name = MODEL_NAME
		model:SetAttribute("WinnerUserId", userId)

		-- Anim needs to be loaded before the parts are anchored, or the pose
		-- will not apply.
		prepareModel(model)
		pcall(function()
			model:ScaleTo(SCALE)
		end)

		-- The tile surface is exact; raycasting would land on arena decor.
		local groundY = arenaCentre.Y

		--[[
			Built in place, hidden, rather than assembled somewhere else and moved.

			The old approach staged him 900 studs below the arena and lifted him in
			when he was ready, which had two problems. The lift is instant but the
			rig's joints are physics-driven, so the limbs streamed up after the
			root over several frames - that is the climbing-out-of-the-ground look.
			And worse, -900 is past FallenPartsDestroyHeight (-500), so the engine
			was destroying the unanchored limbs while they waited down there; the
			model arrived as a Humanoid, Shirt and Pants with no body at all.

			Since he is invisible until finished anyway, none of that staging is
			needed: assemble him exactly where he will dance.
		]]
		local savedTransparency = setModelHidden(model, true)

		model.Parent = Workspace
		currentModel = model
		local root = model:FindFirstChild("HumanoidRootPart")

		-- Face the lobby, so the winner is looking at everyone watching.
		local facePos = Vector3.new(spawn.Position.X, groundY, spawn.Position.Z)
		if (Vector3.new(facePos.X, 0, facePos.Z) - Vector3.new(arenaCentre.X, 0, arenaCentre.Z)).Magnitude < 1 then
			facePos = arenaCentre + Vector3.new(0, 0, 1)
		end
		model:PivotTo(CFrame.lookAt(Vector3.new(arenaCentre.X, groundY, arenaCentre.Z), facePos))

		--[[
			Measuring the rig has to wait. Straight after scaling and placing, the
			unanchored limbs have not caught up to the root yet, so "lowest part"
			reads far below the body - garbage that previously either buried the
			giant or, once the tracker latched onto it, parked him 22 studs in the
			air. A few frames of settling first makes every later reading real.
		]]
		task.wait(0.4)
		if token ~= buildToken or not model.Parent then
			return
		end

		-- Measure only limbs, ignoring anything absurdly far from the body: a
		-- stray accessory should not define where the feet are.
		local modelHeight = select(2, model:GetBoundingBox()).Y
		local function lowestPoint()
			local rootY = root and root.Position.Y or groundY
			local lowest = math.huge
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					local bottom = part.Position.Y - (part.Size.Y / 2)
					if rootY - bottom < modelHeight then
						lowest = math.min(lowest, bottom)
					end
				end
			end
			return lowest
		end

		local settledLowest = lowestPoint()
		if settledLowest < math.huge then
			model:PivotTo(model:GetPivot() + Vector3.new(0, (groundY + GROUND_CLEARANCE) - settledLowest, 0))
		end

		-- Pin the root only, now that it is in place.
		if root then
			root.Anchored = true
		end

		--[[
			The server only sets the resting height. Keeping the feet planted while
			the dance runs is done client-side, in
			StarterPlayerScripts.WinnerDisplayGround - every client evaluates the
			animation locally each render frame, so a correction computed here
			always arrives a network hop after the dip is already on screen.
		]]

		if not playDance(model, token) then
			-- Nothing loaded: hold a neutral standing pose rather than a T-pose.
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.PlatformStand = true
			end
		end

		-- Let the first frames of the dance settle, then hand the baseline to
		-- the client stabiliser and reveal him mid-performance.
		task.wait(DANCE_SETTLE)
		if token ~= buildToken or not model.Parent then
			return
		end

		model:SetAttribute(READY_ATTRIBUTE, true)
		setModelHidden(model, false, savedTransparency)
	end)
end

return WinnerDisplayService
