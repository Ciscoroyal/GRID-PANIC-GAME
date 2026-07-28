local Players = game:GetService("Players")

local PlayerSettings = {}

local DEFAULTS = {
	Music = true,
	SFX = true,
	ScreenShake = true,
	HitEffects = true,
	WorldVFX = true,
}

local ATTR_PREFIX = "Setting_"

local function attributeName(key)
	return ATTR_PREFIX .. key
end

function PlayerSettings.getDefaults()
	local copy = {}
	for key, value in pairs(DEFAULTS) do
		copy[key] = value
	end
	return copy
end

function PlayerSettings.ensure(player)
	player = player or Players.LocalPlayer
	if not player then
		return
	end

	for key, defaultValue in pairs(DEFAULTS) do
		local attr = attributeName(key)
		if player:GetAttribute(attr) == nil then
			player:SetAttribute(attr, defaultValue)
		end
	end
end

function PlayerSettings.get(key, player)
	player = player or Players.LocalPlayer
	if not player then
		return DEFAULTS[key]
	end

	PlayerSettings.ensure(player)
	local value = player:GetAttribute(attributeName(key))
	if value == nil then
		return DEFAULTS[key]
	end
	return value == true
end

function PlayerSettings.set(key, enabled, player)
	player = player or Players.LocalPlayer
	if not player or DEFAULTS[key] == nil then
		return
	end

	player:SetAttribute(attributeName(key), enabled == true)
end

function PlayerSettings.toggle(key, player)
	local current = PlayerSettings.get(key, player)
	PlayerSettings.set(key, not current, player)
	return not current
end

function PlayerSettings.isMusicEnabled(player)
	return PlayerSettings.get("Music", player)
end

function PlayerSettings.isSFXEnabled(player)
	return PlayerSettings.get("SFX", player)
end

function PlayerSettings.isScreenShakeEnabled(player)
	return PlayerSettings.get("ScreenShake", player)
end

function PlayerSettings.isHitEffectsEnabled(player)
	return PlayerSettings.get("HitEffects", player)
end

function PlayerSettings.isWorldVFXEnabled(player)
	return PlayerSettings.get("WorldVFX", player)
end

function PlayerSettings.onChanged(key, callback, player)
	player = player or Players.LocalPlayer
	if not player then
		return nil
	end

	PlayerSettings.ensure(player)
	return player:GetAttributeChangedSignal(attributeName(key)):Connect(function()
		callback(PlayerSettings.get(key, player))
	end)
end

return PlayerSettings
