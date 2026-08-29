--!strict

-- Sound templates live under this module so designers can edit Sound properties in Studio.
local templates = script:WaitForChild("Templates")

local SoundConfig = {}

function SoundConfig.Get(name: string?): Sound?
	local requestedName = if name and name ~= "" then name else "Default"
	local sound = templates:FindFirstChild(requestedName)
	if sound and sound:IsA("Sound") then
		return sound
	end

	local fallback = templates:FindFirstChild("Default")
	if fallback and fallback:IsA("Sound") then
		return fallback
	end

	warn(string.format("SoundConfig has no Sound named %s and no Default fallback", requestedName))
	return nil
end

function SoundConfig.GetTemplates(): Folder
	return templates :: Folder
end

return SoundConfig
