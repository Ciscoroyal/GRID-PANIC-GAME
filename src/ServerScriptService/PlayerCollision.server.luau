local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local PLAYER_GROUP = "ArenaPlayers"

pcall(function()
	PhysicsService:RegisterCollisionGroup(PLAYER_GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(PLAYER_GROUP, PLAYER_GROUP, false)

local function applyCharacterCollision(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = PLAYER_GROUP
		end
	end

	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_GROUP
		end
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	end
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(applyCharacterCollision)
	if player.Character then
		applyCharacterCollision(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
