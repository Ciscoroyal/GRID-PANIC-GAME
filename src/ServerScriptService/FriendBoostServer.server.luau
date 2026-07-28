local Players = game:GetService("Players")

local BOOST_PER_FRIEND = 10
local UPDATE_INTERVAL = 30

local function updateFriendBoost(player)
	local friendCount = 0

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local success, isFriend = pcall(function()
				return player:IsFriendsWith(other.UserId)
			end)
			if success and isFriend then
				friendCount += 1
			end
		end
	end

	local boostPercent = friendCount * BOOST_PER_FRIEND
	player:SetAttribute("FriendCountInServer", friendCount)
	player:SetAttribute("FriendBoostPercent", boostPercent)
	player:SetAttribute("FriendBoostMultiplier", 1 + (boostPercent / 100))
end

local function updateAllPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(updateFriendBoost, player)
	end
end

Players.PlayerAdded:Connect(function()
	task.defer(updateAllPlayers)
end)

Players.PlayerRemoving:Connect(function()
	task.defer(updateAllPlayers)
end)

task.spawn(function()
	while true do
		updateAllPlayers()
		task.wait(UPDATE_INTERVAL)
	end
end)

updateAllPlayers()
