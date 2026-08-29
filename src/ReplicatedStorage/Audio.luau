--[[
	One place to play a sound effect by name.

	Templates live in ReplicatedStorage.GameAssets.Sounds; every one is routed to
	the SoundService.SFX group, so muting SFX is a single volume write on the
	group rather than a check in every caller. The isSFXEnabled() guard here is
	belt-and-braces for anything that plays before the group volume is applied.

	UI sounds are 2D (parented to SoundService). Anything that should attenuate
	with distance goes through playAt(), which parents to a part instead.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))

local Audio = {}

local GROUP_NAME = "SFX"
local MAX_LIFETIME = 12 -- hard cleanup ceiling for a clone that never ends

local soundsFolder = nil
local lastPlayed = {}

local function getFolder()
	if soundsFolder and soundsFolder.Parent then
		return soundsFolder
	end
	local assets = ReplicatedStorage:FindFirstChild("GameAssets")
	soundsFolder = assets and assets:FindFirstChild("Sounds")
	return soundsFolder
end

--[[
	The SFX group is created in Studio, but a fresh server may replicate it a
	moment late; make one rather than dropping the routing on the floor.
]]
local function getGroup()
	local group = SoundService:FindFirstChild(GROUP_NAME)
	if group and group:IsA("SoundGroup") then
		return group
	end
	group = Instance.new("SoundGroup")
	group.Name = GROUP_NAME
	group.Volume = 1
	group.Parent = SoundService
	return group
end

-- Returns the template so callers can inspect it (TimeLength, etc).
function Audio.get(name)
	local folder = getFolder()
	local sound = folder and folder:FindFirstChild(name)
	if sound and sound:IsA("Sound") then
		return sound
	end
	return nil
end

local function prepare(name, opts)
	if not RunService:IsClient() then
		return nil
	end
	opts = opts or {}

	if opts.ignoreSetting ~= true and not PlayerSettings.isSFXEnabled() then
		return nil
	end

	--[[
		Throttle: hovering across a dense list would otherwise fire one sound per
		row per frame. Callers that repeat on purpose (coin pickups) pass their
		own small throttle or none at all.
	]]
	local throttle = opts.throttle
	if throttle and throttle > 0 then
		local now = os.clock()
		if lastPlayed[name] and now - lastPlayed[name] < throttle then
			return nil
		end
		lastPlayed[name] = now
	end

	local template = Audio.get(name)
	if not template or template.SoundId == "" then
		return nil
	end

	local sound = template:Clone()
	sound.SoundGroup = getGroup()

	if opts.volume then
		sound.Volume = opts.volume
	end
	if opts.volumeScale then
		sound.Volume = sound.Volume * opts.volumeScale
	end

	-- Pitch jitter keeps repeated sounds from reading as a machine gun.
	local jitter = opts.pitchJitter
	if jitter and jitter > 0 then
		sound.PlaybackSpeed = (opts.pitch or 1) + ((math.random() * 2 - 1) * jitter)
	elseif opts.pitch then
		sound.PlaybackSpeed = opts.pitch
	end

	return sound
end

local function launch(sound)
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, MAX_LIFETIME)
	return sound
end

--[[
	Play a 2D sound (UI, notifications). opts:
		volume, volumeScale, pitch, pitchJitter, throttle, ignoreSetting
	Returns the playing Sound, or nil if it was suppressed.
]]
function Audio.play(name, opts)
	local sound = prepare(name, opts)
	if not sound then
		return nil
	end
	sound.Parent = SoundService
	return launch(sound)
end

-- Play positioned in the world so it attenuates with distance.
function Audio.playAt(name, part, opts)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return Audio.play(name, opts)
	end
	local sound = prepare(name, opts)
	if not sound then
		return nil
	end
	sound.RollOffMaxDistance = (opts and opts.maxDistance) or 90
	sound.Parent = part
	return launch(sound)
end

-- Mirrors the SFX setting onto the group. Called once by the settings hookup.
function Audio.applySettingToGroup()
	getGroup().Volume = PlayerSettings.isSFXEnabled() and 1 or 0
end

return Audio
