local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local EliminationService = require(ServerScriptService:WaitForChild("EliminationService"))

local recent = {}

local function onTouched(part)
	local character = part.Parent
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	if recent[player] then return end

	recent[player] = true
	EliminationService.eliminate(player, { cause = "water", respectShield = true })
	task.delay(0.5, function()
		recent[player] = nil
	end)
end

script.Parent.Touched:Connect(onTouched)
