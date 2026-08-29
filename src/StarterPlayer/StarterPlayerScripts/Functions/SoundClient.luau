--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundController = require(ReplicatedStorage:WaitForChild("Systems"):WaitForChild("SoundController"))

export type PlayOptions = SoundController.PlayOptions
export type StepProgressiveOptions = SoundController.StepProgressiveOptions
export type ContinuousProgressiveOptions = SoundController.ContinuousProgressiveOptions
export type SoundTarget = BasePart | Attachment | Vector3
export type SoundHandle = {
	Stop: (self: SoundHandle, fadeTime: number?) -> (),
	IsValid: (self: SoundHandle) -> boolean,
}
export type ProgressiveSoundHandle = SoundHandle & {
	SetProgress: (self: ProgressiveSoundHandle, progress: number) -> (),
}

local SoundClient = {}
local activeSounds: { [string]: ProgressiveSoundHandle } = {}

function SoundClient.Play2D(soundTemplate: Sound, options: PlayOptions?): SoundHandle?
	return SoundController.Play2D(soundTemplate, options)
end

function SoundClient.Play3D(
	soundTemplate: Sound,
	target: SoundTarget,
	options: PlayOptions?
): SoundHandle?
	return SoundController.Play3D(soundTemplate, target, options)
end

function SoundClient.PlayProgressive2D(
	soundTemplate: Sound,
	sequenceId: string,
	options: StepProgressiveOptions?
): SoundHandle?
	return SoundController.PlayProgressive2D(soundTemplate, sequenceId, options)
end

function SoundClient.PlayProgressive3D(
	soundTemplate: Sound,
	target: SoundTarget,
	sequenceId: string,
	options: StepProgressiveOptions?
): SoundHandle?
	return SoundController.PlayProgressive3D(soundTemplate, target, sequenceId, options)
end

function SoundClient.Stop(soundId: string, fadeTime: number?): boolean
	local handle = activeSounds[soundId]
	if not handle then
		return false
	end
	activeSounds[soundId] = nil
	handle:Stop(fadeTime)
	return true
end

function SoundClient.SetProgress(soundId: string, progress: number): boolean
	local handle = activeSounds[soundId]
	if not handle or not handle:IsValid() then
		activeSounds[soundId] = nil
		return false
	end
	handle:SetProgress(progress)
	return true
end

function SoundClient.CreateProgressive2D(
	soundId: string,
	soundTemplate: Sound,
	options: ContinuousProgressiveOptions?
): ProgressiveSoundHandle?
	SoundClient.Stop(soundId)
	local handle = SoundController.CreateProgressive2D(soundTemplate, options) :: ProgressiveSoundHandle?
	if handle then
		activeSounds[soundId] = handle
	end
	return handle
end

function SoundClient.CreateProgressive3D(
	soundId: string,
	soundTemplate: Sound,
	target: SoundTarget,
	options: ContinuousProgressiveOptions?
): ProgressiveSoundHandle?
	SoundClient.Stop(soundId)
	local handle = SoundController.CreateProgressive3D(soundTemplate, target, options) :: ProgressiveSoundHandle?
	if handle then
		activeSounds[soundId] = handle
	end
	return handle
end

function SoundClient.Init()
	-- Reusable initialization belongs here. Test bindings stay in ClientManager.
end

function SoundClient.Destroy()
	for soundId, handle in activeSounds do
		activeSounds[soundId] = nil
		handle:Stop()
	end
	SoundController.StopAll()
end

return SoundClient
