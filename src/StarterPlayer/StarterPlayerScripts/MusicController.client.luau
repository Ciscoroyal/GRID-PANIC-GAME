local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSettings = require(ReplicatedStorage:WaitForChild("PlayerSettings"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))

local localPlayer = Players.LocalPlayer
PlayerSettings.ensure(localPlayer)

--[[
	This script owns audio settings for the client. Music is handled below;
	effects are muted in one place by dropping the SFX SoundGroup to zero, so a
	new sound added anywhere obeys the toggle without its own check.
]]
Audio.applySettingToGroup()
PlayerSettings.onChanged("SFX", Audio.applySettingToGroup)

local lobbyTemplate = SoundService:WaitForChild("LobbyMusic")
local matchTemplate = SoundService:WaitForChild("MatchMusic")

local function stopTemplates()
	lobbyTemplate:Stop()
	matchTemplate:Stop()
end

stopTemplates()

local musicFolder = SoundService:FindFirstChild("ClientMusic")
if not musicFolder then
	musicFolder = Instance.new("Folder")
	musicFolder.Name = "ClientMusic"
	musicFolder.Parent = SoundService
end

local lobbyMusic
local matchMusic
local BASE_VOLUME = 0.3

local function createLocalSound(template, name)
	local existing = musicFolder:FindFirstChild(name)
	if existing then
		return existing
	end

	local sound = template:Clone()
	sound.Name = name
	sound.Looped = true
	sound.Volume = BASE_VOLUME
	sound.Parent = musicFolder
	return sound
end

local function ensureSounds()
	if not lobbyMusic or not lobbyMusic.Parent then
		lobbyMusic = createLocalSound(lobbyTemplate, "LocalLobbyMusic")
	end
	if not matchMusic or not matchMusic.Parent then
		matchMusic = createLocalSound(matchTemplate, "LocalMatchMusic")
	end
end

local function applyVolumes()
	ensureSounds()
	local volume = PlayerSettings.isMusicEnabled() and BASE_VOLUME or 0
	lobbyMusic.Volume = volume
	matchMusic.Volume = volume
end

local function updateMusic()
	ensureSounds()
	applyVolumes()

	if not PlayerSettings.isMusicEnabled() then
		lobbyMusic:Stop()
		matchMusic:Stop()
		return
	end

	if localPlayer:GetAttribute("InArena") == true then
		lobbyMusic:Stop()
		if not matchMusic.IsPlaying then
			matchMusic:Play()
		end
	else
		matchMusic:Stop()
		if not lobbyMusic.IsPlaying then
			lobbyMusic:Play()
		end
	end
end

updateMusic()

localPlayer:GetAttributeChangedSignal("InArena"):Connect(updateMusic)
PlayerSettings.onChanged("Music", updateMusic)
localPlayer.CharacterAdded:Connect(function()
	task.defer(updateMusic)
end)
