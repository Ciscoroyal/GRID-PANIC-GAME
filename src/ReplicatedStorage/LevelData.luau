--[[
	Soft XP curve, max level 100.
	Early levels come quickly; later levels slow gently without feeling grindy.
]]

local LevelData = {}

LevelData.MAX_LEVEL = 100

-- Milestone cosmetics auto-unlocked on reaching these levels
LevelData.MILESTONE_COSMETICS = {
	[10] = { id = "Title_Contender", name = "Contender Title" },
	[25] = { id = "Title_Gladiator", name = "Gladiator Title" },
	[50] = { id = "Title_Champion", name = "Champion Title" },
	[75] = { id = "Title_Legend", name = "Legend Title" },
	[100] = { id = "Title_GridPanic", name = "Grid Panic Title" },
}

-- Display milestones in the Rewards Level list
LevelData.UI_MILESTONES = { 5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 90, 100 }

local function xpToAdvanceFrom(level)
	if level < 1 then
		level = 1
	end
	if level >= LevelData.MAX_LEVEL then
		return 0
	end
	-- Soft: ~35 XP for 1→2, scales gently with level^1.2
	return math.floor(35 + 9 * (level ^ 1.2))
end

LevelData.xpToAdvanceFrom = xpToAdvanceFrom

-- cumulativeXP[level] = total XP required to BE that level
local cumulativeXP = { [1] = 0 }
for level = 1, LevelData.MAX_LEVEL - 1 do
	cumulativeXP[level + 1] = cumulativeXP[level] + xpToAdvanceFrom(level)
end

LevelData.MAX_TOTAL_XP = cumulativeXP[LevelData.MAX_LEVEL]

function LevelData.getTotalXPForLevel(level)
	level = math.clamp(math.floor(level), 1, LevelData.MAX_LEVEL)
	return cumulativeXP[level]
end

function LevelData.getLevelFromXP(totalXP)
	totalXP = math.max(0, math.floor(tonumber(totalXP) or 0))
	if totalXP >= LevelData.MAX_TOTAL_XP then
		return LevelData.MAX_LEVEL
	end
	local level = 1
	for candidate = LevelData.MAX_LEVEL, 1, -1 do
		if totalXP >= cumulativeXP[candidate] then
			level = candidate
			break
		end
	end
	return level
end

function LevelData.getXPIntoLevel(totalXP)
	local level = LevelData.getLevelFromXP(totalXP)
	return math.max(0, math.floor(totalXP) - cumulativeXP[level])
end

function LevelData.getXPRequiredForNext(level)
	return xpToAdvanceFrom(level)
end

function LevelData.getProgress(totalXP)
	local level = LevelData.getLevelFromXP(totalXP)
	if level >= LevelData.MAX_LEVEL then
		return 1
	end
	local need = xpToAdvanceFrom(level)
	if need <= 0 then
		return 1
	end
	return math.clamp(LevelData.getXPIntoLevel(totalXP) / need, 0, 1)
end

function LevelData.getLevelUpReward(newLevel)
	newLevel = math.floor(tonumber(newLevel) or 0)
	local coins = 20 + newLevel * 5
	if newLevel % 5 == 0 then
		coins += 50
	end
	if newLevel % 10 == 0 then
		coins += 100
	end

	return {
		coins = coins,
		cosmetic = LevelData.MILESTONE_COSMETICS[newLevel],
	}
end

function LevelData.getCosmeticAttributeKey(cosmeticId)
	return "OwnCosmetic_" .. tostring(cosmeticId)
end

function LevelData.buildSnapshot(totalXP)
	totalXP = math.clamp(math.floor(tonumber(totalXP) or 0), 0, LevelData.MAX_TOTAL_XP)
	local level = LevelData.getLevelFromXP(totalXP)
	local into = LevelData.getXPIntoLevel(totalXP)
	local need = LevelData.getXPRequiredForNext(level)
	return {
		totalXP = totalXP,
		level = level,
		xpIntoLevel = into,
		xpForNext = need,
		progress = LevelData.getProgress(totalXP),
		isMax = level >= LevelData.MAX_LEVEL,
	}
end

return LevelData
