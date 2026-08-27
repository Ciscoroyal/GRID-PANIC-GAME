local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LevelData = require(ReplicatedStorage:WaitForChild("LevelData"))

local levelStateEvent = ReplicatedStorage:WaitForChild("LevelStateEvent")
local levelUpEvent = ReplicatedStorage:WaitForChild("LevelUpEvent")

local LevelService = {}
local synced = {}

local function getXPValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("XP")
end

local function awardFlatCoins(player, amount)
	if amount <= 0 then
		return
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if coins then
		coins.Value += amount
	end
end

local function pushAttributes(player, snapshot)
	player:SetAttribute("PlayerLevel", snapshot.level)
	player:SetAttribute("XPIntoLevel", snapshot.xpIntoLevel)
	player:SetAttribute("XPForNext", snapshot.xpForNext)
	player:SetAttribute("LevelProgress", snapshot.progress)
end

local function grantLevelUpRewards(player, fromLevel, toLevel)
	local granted = {}
	for level = fromLevel + 1, toLevel do
		local reward = LevelData.getLevelUpReward(level)
		if reward.coins > 0 then
			awardFlatCoins(player, reward.coins)
		end
		if reward.cosmetic then
			local key = LevelData.getCosmeticAttributeKey(reward.cosmetic.id)
			player:SetAttribute(key, true)
		end
		table.insert(granted, {
			level = level,
			coins = reward.coins,
			cosmetic = reward.cosmetic and reward.cosmetic.name or nil,
		})
		levelUpEvent:FireClient(player, {
			level = level,
			coins = reward.coins,
			cosmetic = reward.cosmetic and reward.cosmetic.name or nil,
		})
	end
	return granted
end

function LevelService.getSnapshot(player)
	local xpVal = getXPValue(player)
	local totalXP = xpVal and xpVal.Value or 0
	return LevelData.buildSnapshot(totalXP)
end

function LevelService.sync(player, fireClient)
	if not player then
		return nil
	end
	local snapshot = LevelService.getSnapshot(player)
	pushAttributes(player, snapshot)
	if fireClient ~= false then
		levelStateEvent:FireClient(player, snapshot, LevelService.getMilestonesForPlayer(player))
	end
	return snapshot
end

function LevelService.awardXP(player, baseAmount)
	if not player or not baseAmount or baseAmount <= 0 then
		return 0, LevelService.getSnapshot(player)
	end

	local xpVal = getXPValue(player)
	if not xpVal then
		return 0, LevelService.getSnapshot(player)
	end

	local beforeLevel = LevelData.getLevelFromXP(xpVal.Value)
	local multiplier = player:GetAttribute("FriendBoostMultiplier") or 1
	local gained = math.floor(baseAmount * multiplier)
	if gained <= 0 then
		return 0, LevelService.getSnapshot(player)
	end

	local newTotal = math.min(LevelData.MAX_TOTAL_XP, xpVal.Value + gained)
	local actualGained = newTotal - xpVal.Value
	xpVal.Value = newTotal

	local afterLevel = LevelData.getLevelFromXP(newTotal)
	if afterLevel > beforeLevel then
		grantLevelUpRewards(player, beforeLevel, afterLevel)
	end

	local snapshot = LevelService.sync(player, true)
	return actualGained, snapshot
end

function LevelService.getMilestonesForPlayer(player)
	local level = player:GetAttribute("PlayerLevel") or LevelService.getSnapshot(player).level
	local rows = {}
	for _, milestone in ipairs(LevelData.UI_MILESTONES) do
		local reward = LevelData.getLevelUpReward(milestone)
		local cosmetic = LevelData.MILESTONE_COSMETICS[milestone]
		table.insert(rows, {
			level = milestone,
			coins = reward.coins,
			cosmetic = cosmetic and cosmetic.name or nil,
			unlocked = level >= milestone,
		})
	end
	return rows
end

local function hookPlayer(player)
	if synced[player] then
		return
	end
	synced[player] = true

	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 30)
		if not leaderstats then
			return
		end
		local xpVal = leaderstats:WaitForChild("XP", 30)
		if not xpVal then
			return
		end

		-- Cap legacy XP that may exceed max
		if xpVal.Value > LevelData.MAX_TOTAL_XP then
			xpVal.Value = LevelData.MAX_TOTAL_XP
		end

		LevelService.sync(player, true)

		xpVal:GetPropertyChangedSignal("Value"):Connect(function()
			if xpVal.Value > LevelData.MAX_TOTAL_XP then
				xpVal.Value = LevelData.MAX_TOTAL_XP
				return
			end
			LevelService.sync(player, true)
		end)
	end)
end

levelStateEvent.OnServerEvent:Connect(function(player)
	local snapshot = LevelService.sync(player, false)
	if snapshot then
		levelStateEvent:FireClient(player, snapshot, LevelService.getMilestonesForPlayer(player))
	end
end)

Players.PlayerAdded:Connect(hookPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	synced[player] = nil
end)

return LevelService
