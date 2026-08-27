--[[
	Gamemode definitions + weighted vote picking.
	Classic, PureSurvival, PunchOut, Team, Shrinking, and Juggernaut are implemented.
]]

local GameModeData = {
	{
		id = "Classic",
		displayName = "CLASSIC",
		description = "Standard dodge & survive",
		weight = 1,
		voteEnabled = true,
	},
	{
		id = "PureSurvival",
		displayName = "PURE SURVIVAL",
		description = "No abilities — dash only",
		weight = 1,
		voteEnabled = true,
	},
	{
		id = "PunchOut",
		displayName = "PUNCH OUT",
		description = "Grid Punch only",
		weight = 1,
		voteEnabled = true,
	},
	{
		id = "Team",
		displayName = "TEAM",
		description = "Blue vs Red — last team standing",
		weight = 1,
		voteEnabled = true,
	},
	{
		id = "Shrinking",
		displayName = "SHRINKING",
		description = "Arena tiles fall inward",
		weight = 1,
		voteEnabled = true,
	},
	{
		id = "Juggernaut",
		displayName = "JUGGERNAUT",
		description = "1 boss vs everyone — knock them off",
		weight = 1,
		voteEnabled = true,
	},
}

function GameModeData.getById(id)
	for _, mode in ipairs(GameModeData) do
		if mode.id == id then
			return mode
		end
	end
	return nil
end

function GameModeData.getVotePool()
	local pool = {}
	for _, mode in ipairs(GameModeData) do
		if mode.voteEnabled ~= false and (mode.weight or 0) > 0 then
			table.insert(pool, mode)
		end
	end
	return pool
end

-- Returns up to `count` distinct modes using weights.
function GameModeData.pickVoteOptions(count)
	count = math.max(1, count or 2)
	local pool = GameModeData.getVotePool()
	local picks = {}
	local used = {}

	for _ = 1, count do
		local total = 0
		local eligible = {}
		for _, mode in ipairs(pool) do
			if not used[mode.id] and (mode.weight or 0) > 0 then
				table.insert(eligible, mode)
				total += mode.weight or 1
			end
		end
		if #eligible == 0 or total <= 0 then
			break
		end

		local roll = math.random() * total
		local acc = 0
		local chosen = eligible[#eligible]
		for _, mode in ipairs(eligible) do
			acc += mode.weight or 1
			if roll <= acc then
				chosen = mode
				break
			end
		end

		used[chosen.id] = true
		table.insert(picks, {
			id = chosen.id,
			displayName = chosen.displayName,
			description = chosen.description or "",
		})
	end

	if #picks == 0 then
		table.insert(picks, { id = "Classic", displayName = "CLASSIC", description = "" })
	end
	return picks
end

function GameModeData.isPureSurvival(modeId)
	return modeId == "PureSurvival"
end

function GameModeData.isPunchOut(modeId)
	return modeId == "PunchOut"
end

function GameModeData.isTeam(modeId)
	return modeId == "Team"
end

function GameModeData.isShrinking(modeId)
	return modeId == "Shrinking"
end

function GameModeData.isJuggernaut(modeId)
	return modeId == "Juggernaut"
end

return GameModeData
