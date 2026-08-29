local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local KillFeedService = require(ServerScriptService:WaitForChild("KillFeedService"))
local LobbySpawnService = require(ServerScriptService:WaitForChild("LobbySpawnService"))
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")

local EliminationService = {}

--[[
	Hazard deaths play a clip before the body is pulled back to the lobby.

	The clip must be authored on an R15 rig - this game is R15, and an R6 export
	loads and reports a valid length while moving nothing, which just looks like
	a frozen character. Set this to false to skip the animation and hold, and
	teleport eliminated players out immediately.
]]
local HAZARD_DEATH_ANIM_ENABLED = true
local DEATH_ANIM_NAME = "HazardDeath"

-- How long the fall itself takes: the clip is fitted to this.
local DEATH_FALL_SECONDS = 0.5

-- How long the body then lies still on the floor before the teleport. The clip
-- is frozen on its last frame for this stretch, so the pose holds instead of
-- snapping back to idle.
local DEATH_GROUND_HOLD_SECONDS = 0.45

-- The clip is stretched to run slightly longer than the fall, so it is still
-- mid-play when we freeze it. Letting it reach its own end first makes the
-- character blend back up to standing in the arena.
local TELEPORT_LEAD = 0.05

local animationsFolder = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("Animations")

-- Track length is 0 until the asset loads. Resolving it during a death costs a
-- visible stall, so it is warmed up in the background at server start instead.
local cachedClipLength = nil

local function warmDeathClip()
	local animObject = animationsFolder:FindFirstChild(DEATH_ANIM_NAME)
	if not animObject or not animObject:IsA("Animation") or animObject.AnimationId == "" then
		return
	end

	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ animObject })
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if cachedClipLength then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			pcall(function()
				local track = animator:LoadAnimation(animObject)
				local deadline = os.clock() + 2
				while (typeof(track.Length) ~= "number" or track.Length <= 0) and os.clock() < deadline do
					task.wait()
				end
				if typeof(track.Length) == "number" and track.Length > 0 then
					cachedClipLength = track.Length
				end
				track:Destroy()
			end)
		end
	end
end

if HAZARD_DEATH_ANIM_ENABLED then
	task.spawn(function()
		-- Keep trying until a character exists and the asset resolves.
		for _ = 1, 20 do
			if cachedClipLength then
				return
			end
			warmDeathClip()
			task.wait(2)
		end
	end)
end

--[[
	Plays the hazard death clip and holds the character still while it runs.
	Returns how long to wait before teleporting, plus a finish() to call once the
	player has been moved - it drops the death pose and restores the humanoid, so
	they arrive in the lobby standing rather than face down.
]]
local function playHazardDeath(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0, nil
	end

	local animObject = animationsFolder:FindFirstChild(DEATH_ANIM_NAME)
	if not animObject or not animObject:IsA("Animation") or animObject.AnimationId == "" then
		return 0, nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return 0, nil
	end

	local savedJumpPower = humanoid.JumpPower
	local savedJumpHeight = humanoid.JumpHeight

	local root = character:FindFirstChild("HumanoidRootPart")
	local savedAnchored = root and root.Anchored or false

	local function restore()
		if root and root.Parent then
			root.Anchored = savedAnchored
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		if humanoid.Parent then
			humanoid.JumpPower = savedJumpPower
			humanoid.JumpHeight = savedJumpHeight
			humanoid.AutoRotate = true
		end
	end

	-- Hold the body still so the clip reads cleanly.
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		-- Zeroing walk speed does not stop carried momentum or knockback, and a
		-- corpse sliding across the floor mid-animation looks broken. Anchoring
		-- pins them; PivotTo still moves them for the teleport.
		root.Anchored = true
	end

	local deathTrack = nil

	local function finish()
		-- Cut the pose instantly. Called after the teleport, so the character is
		-- already in the lobby when the idle animation takes back over.
		if deathTrack then
			pcall(function()
				deathTrack:Stop(0)
			end)
		end
		restore()
	end

	local ok = pcall(function()
		local track = animator:LoadAnimation(animObject)
		deathTrack = track
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false

		for _, other in ipairs(animator:GetPlayingAnimationTracks()) do
			if other ~= track then
				other:Stop(0)
			end
		end

		-- Fit the clip to the fall time. Never yield here - a stall means the
		-- player stands frozen before the clip starts. If the warm-up has not
		-- resolved yet, play at normal speed.
		local speed = 1
		if cachedClipLength and cachedClipLength > 0 then
			speed = cachedClipLength / (DEATH_FALL_SECONDS + TELEPORT_LEAD)
		end

		-- No fade-in: a death clip that eases in from weight 0 reads as nothing
		-- happening for the first tenth of a second.
		track:Play(0, 1, speed)
		track:AdjustWeight(1, 0)

		-- Once they have hit the floor, stop the clip advancing so the body stays
		-- down instead of playing on and blending back up.
		task.delay(DEATH_FALL_SECONDS, function()
			if track and track.IsPlaying then
				pcall(function()
					track:AdjustSpeed(0)
				end)
			end
		end)
	end)

	if not ok then
		return 0, finish
	end

	return DEATH_FALL_SECONDS + DEATH_GROUND_HOLD_SECONDS, finish
end

local teleporting = {}
local eliminatedCallbacks = {}
local SHIELD_BREAK_IMMUNITY = 1.0 -- seconds; stops multi-hit hazards from killing after shield breaks

function EliminationService.onEliminated(callback)
	if typeof(callback) == "function" then
		table.insert(eliminatedCallbacks, callback)
	end
end

local function getLobbySpawn()
	local lobbySpawn = Workspace:FindFirstChild("LobbySpawn")
	if lobbySpawn and (lobbySpawn:IsA("SpawnLocation") or lobbySpawn:IsA("BasePart")) then
		return lobbySpawn
	end
	return nil
end

local function clearShield(player, character)
	player:SetAttribute("HasShield", nil)
	if character then
		local shieldVis = character:FindFirstChild("ShieldVisual")
		if shieldVis then
			shieldVis:Destroy()
		end
	end
end

function EliminationService.teleportToLobby(player)
	if not player or not player.Parent then
		return false
	end
	if teleporting[player] then
		return false
	end

	teleporting[player] = true

	local lobbySpawn = getLobbySpawn()
	if lobbySpawn and lobbySpawn:IsA("SpawnLocation") then
		player.RespawnLocation = lobbySpawn
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	-- Soft return: keep the living character and move them to lobby
	if character and root and humanoid and humanoid.Health > 0 then
		if not LobbySpawnService.placeCharacter(character) then
			local spawnCF = (lobbySpawn and lobbySpawn.CFrame or root.CFrame) * CFrame.new(0, 3, 0)
			character:PivotTo(spawnCF)
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = game:GetService("StarterPlayer").CharacterWalkSpeed
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
		humanoid.AutoRotate = true
		player:SetAttribute("InPractice", nil)
		task.delay(0.5, function()
			teleporting[player] = nil
		end)
		return true
	end

	-- Fallback if character is already dead/missing
	player:LoadCharacter()
	character = player.Character or player.CharacterAdded:Wait()
	root = character:WaitForChild("HumanoidRootPart", 10)
	humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and lobbySpawn then
		if not LobbySpawnService.placeCharacter(character) then
			character:PivotTo(lobbySpawn.CFrame * CFrame.new(0, 3, 0))
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	player:SetAttribute("InPractice", nil)
	task.delay(0.5, function()
		teleporting[player] = nil
	end)
	return true
end

--[[
	opts = {
		cause = "hazard" | "fall" | "water" | nil,
		respectShield = boolean (default true),
	}
	Survival rewards are granted at match end by HazardSpawner.
]]
--[[
	Played from the server on the body so everyone nearby hears the kill, not
	just the player who died. The asset lives in GameAssets.Sounds so it can be
	swapped without touching this file.
]]
local function playEliminationSound(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local assets = ReplicatedStorage:FindFirstChild("GameAssets")
	local sounds = assets and assets:FindFirstChild("Sounds")
	local template = sounds and sounds:FindFirstChild("Eliminated")
	if not template or template.SoundId == "" then
		return
	end
	local sound = template:Clone()
	sound.SoundGroup = game:GetService("SoundService"):FindFirstChild("SFX")
	sound.RollOffMaxDistance = 100
	sound.Parent = root
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	game:GetService("Debris"):AddItem(sound, 8)
end

function EliminationService.eliminate(player, opts)
	opts = opts or {}
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if not player.Parent then
		return false
	end
	if player:GetAttribute("InArena") ~= true then
		return false
	end
	if player:GetAttribute("IsEliminated") == true then
		return false
	end

	-- Juggernaut is immune to every falling-hazard path (grid math kill AND the
	-- cloned HazardCube hitbox). They still die to falls, kill floor, water and combat.
	if opts.cause == "hazard" and player:GetAttribute("IsJuggernaut") == true then
		return false
	end

	local character = player.Character
	local respectShield = opts.respectShield
	if respectShield == nil then
		respectShield = true
	end

	local now = os.clock()
	local immunityUntil = player:GetAttribute("ShieldBreakImmunityUntil")
	if respectShield and typeof(immunityUntil) == "number" and now < immunityUntil then
		return false
	end

	if respectShield and player:GetAttribute("HasShield") == true then
		clearShield(player, character)
		player:SetAttribute("ShieldBreakImmunityUntil", now + SHIELD_BREAK_IMMUNITY)
		vfxEvent:FireClient(player, "LightShake")
		return false
	end

	player:SetAttribute("IsEliminated", true)
	player:SetAttribute("CanSponsorThisRound", true)
	clearShield(player, character)

	if opts.cause == "hazard" then
		KillFeedService.markHazardKill(player)
	elseif opts.cause == "fall" or opts.cause == "water" then
		KillFeedService.setPendingCause(player, opts.cause)
	end

	KillFeedService.reportElimination(player)
	vfxEvent:FireClient(player, "HeavyShake")
	playEliminationSound(character)

	for _, callback in ipairs(eliminatedCallbacks) do
		pcall(callback, player, opts.cause)
	end

	if opts.cause == "hazard" and HAZARD_DEATH_ANIM_ENABLED then
		-- Let the death clip play out where they died, then pull them back.
		task.spawn(function()
			local holdFor, finish = playHazardDeath(player)
			if holdFor > 0 then
				task.wait(holdFor)
			end
			-- Move them first, THEN drop the pose, so the stand-up never happens
			-- in the arena and they land in the lobby upright.
			EliminationService.teleportToLobby(player)
			if finish then
				finish()
			end
		end)
	else
		EliminationService.teleportToLobby(player)
	end

	return true
end

Players.PlayerRemoving:Connect(function(player)
	teleporting[player] = nil
end)

return EliminationService
