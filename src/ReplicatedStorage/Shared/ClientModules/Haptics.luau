--[[
	Haptics -- controller rumble, defensively.

		Haptics.Pulse(Enum.VibrationMotor.Large, 1, 0.35)

	Three things this has to be careful about, because HapticService throws
	rather than no-opping when asked for something the hardware cannot do:

	  SUPPORT   IsVibrationSupported and IsMotorSupported are BOTH checked. A
	            controller can support vibration but not the motor asked for.
	  WHICH PAD every connected gamepad is tried, not just Gamepad1. A player on
	            Gamepad2 is still a player.
	  STOPPING  the motor is set back to 0 after Duration. A motor left running
	            keeps running -- there is no auto-stop.

	MOBILE: Roblox has no touch-device vibration API. HapticService only routes
	to gamepads, so on a phone this is a no-op today. It is written to try every
	input type rather than only gamepads so that if Roblox ever exposes touch
	vibration, this file is where it gets added and nothing else changes.
]]

local HapticService = game:GetService("HapticService")
local UserInputService = game:GetService("UserInputService")

local Haptics = {}

local active = {}

local function targets(): { Enum.UserInputType }
	local found = {}

	for _, gamepad in UserInputService:GetConnectedGamepads() do
		table.insert(found, gamepad)
	end

	return found
end

function Haptics.IsSupported(): boolean
	for _, inputType in targets() do
		local ok, supported = pcall(function()
			return HapticService:IsVibrationSupported(inputType)
		end)

		if ok and supported then
			return true
		end
	end

	return false
end

function Haptics.Pulse(motor: Enum.VibrationMotor?, amplitude: number?, duration: number?)
	motor = motor or Enum.VibrationMotor.Large
	amplitude = math.clamp(amplitude or 1, 0, 1)
	duration = math.max(duration or 0.3, 0)

	for _, inputType in targets() do
		local ok, supported = pcall(function()
			return HapticService:IsVibrationSupported(inputType)
				and HapticService:IsMotorSupported(inputType, motor)
		end)

		if not ok or not supported then
			continue
		end

		local token = {}
		active[inputType] = token

		pcall(function()
			HapticService:SetMotor(inputType, motor, amplitude)
		end)

		task.delay(duration, function()

			if active[inputType] ~= token then
				return
			end

			active[inputType] = nil

			pcall(function()
				HapticService:SetMotor(inputType, motor, 0)
			end)
		end)
	end
end

return Haptics
