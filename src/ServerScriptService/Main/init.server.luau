local ORDER = {
	
}
local Services = script:FindFirstChild("Services") or script.Parent:WaitForChild("Services")

for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(string.format("[Main] Missing service %q", name))
		continue
	end

	local ok, service = pcall(require, module)
	if not ok then
		warn(string.format("[Main] Failed to require %s: %s", name, tostring(service)))
		continue
	end

	if type(service) == "table" and type(service.Init) == "function" then
		local started, err = pcall(service.Init)
		if not started then
			warn(string.format("[Main] %s.Init errored: %s", name, tostring(err)))
		end
	end
end

--local Appearanceconnections = {}

--function overWriteCharacter(chr)
--	local hDescription = chr:WaitForChild("Humanoid"):GetAppliedDescription()
--	hDescription.Torso = 0
--	hDescription.LeftArm = 0
--	hDescription.RightArm = 0
--	hDescription.LeftLeg = 0
--	hDescription.RightLeg = 0
--	chr.Humanoid:ApplyDescription(hDescription)
--end

--game.Players.PlayerAdded:Connect(function(player)
--	Appearanceconnections[player.UserId] = player.CharacterAppearanceLoaded:Connect(overWriteCharacter)
--end)
--game.Players.PlayerRemoving:Connect(function(player)
--	Appearanceconnections[player.UserId]:Disconnect()
--end)
