--[[
	Movement self-repair.

	Several systems temporarily take movement away - the dash zeroes WalkSpeed
	and suppresses six humanoid states, the pre-match lock freezes everyone, the
	death animation pins the body, knockback drops the humanoid into Freefall.
	Each one restores what it took, but they can interrupt each other: a dash
	superseded by a second dash, a player eliminated mid-dash, a round ending
	while someone is airborne. When two of them overlap, one restore can be
	skipped and the player is left permanently slower, or unable to jump
	properly because Running or GettingUp is still disabled.

	Rather than trying to enumerate every interleaving, this asserts the correct
	resting values whenever no system is legitimately holding movement. Anything
	that slips through is corrected within a fraction of a second.

	It deliberately does NOT touch the character while a freeze is legitimate:
	during the roll-call lock, after elimination, or mid-dash.
]]
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer

local CHECK_INTERVAL = 0.3

-- The states the dash suppresses; all of them must be back on at rest.
local REQUIRED_STATES = {
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.RunningNoPhysics,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.GettingUp,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.PlatformStanding,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.Freefall,
}

local function expectedWalkSpeed()
	local speed = StarterPlayer.CharacterWalkSpeed
	if typeof(speed) ~= "number" or speed <= 0 then
		speed = 16
	end
	return speed
end

local function expectedJumpPower()
	local power = StarterPlayer.CharacterJumpPower
	if typeof(power) ~= "number" or power <= 0 then
		power = 50
	end
	return power
end

local function expectedJumpHeight()
	local height = StarterPlayer.CharacterJumpHeight
	if typeof(height) ~= "number" or height <= 0 then
		height = 7.2
	end
	return height
end

--[[
	Is something allowed to be holding this character still right now?
	If so, leave it completely alone - correcting a deliberate freeze would let
	players move during the roll call or after they have been knocked out.
]]
local function freezeIsLegitimate(character)
	if localPlayer:GetAttribute("MatchLocked") == true then
		return true
	end
	if localPlayer:GetAttribute("IsEliminated") == true then
		return true
	end
	if character:GetAttribute("Dashing") == true then
		return true
	end
	return false
end

local function check(character)
	if not character or not character.Parent then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if freezeIsLegitimate(character) then
		return
	end

	-- A death animation anchors the root; that is a real hold too.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root.Anchored then
		return
	end

	for _, state in ipairs(REQUIRED_STATES) do
		if not humanoid:GetStateEnabled(state) then
			humanoid:SetStateEnabled(state, true)
		end
	end

	if humanoid.WalkSpeed <= 0 then
		humanoid.WalkSpeed = expectedWalkSpeed()
	end
	if humanoid.JumpPower <= 0 then
		humanoid.JumpPower = expectedJumpPower()
	end
	if humanoid.JumpHeight <= 0 then
		humanoid.JumpHeight = expectedJumpHeight()
	end

	--[[
		A LinearVelocity left behind by knockback keeps dragging the player along
		its axis, which reads as "my character is sluggish for no reason". The
		service cleans up on a timer, so anything still here well past that
		window is orphaned.
	]]
	if root then
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("LinearVelocity") and child.Name == "KnockbackVelocity" then
				local born = child:GetAttribute("SeenAt")
				if not born then
					child:SetAttribute("SeenAt", os.clock())
				elseif os.clock() - born > 1.5 then
					child:Destroy()
				end
			end
		end
	end

	-- The Animate script is muted during knockback; if it never came back the
	-- character slides around with no locomotion clip.
	local animate = character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) and animate.Disabled then
		local state = humanoid:GetState()
		if state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping then
			animate.Disabled = false
		end
	end
end

task.spawn(function()
	while true do
		task.wait(CHECK_INTERVAL)
		local ok, err = pcall(function()
			check(localPlayer.Character)
		end)
		if not ok then
			warn("[MovementWatchdog]", err)
		end
	end
end)
