local CoinRewards = {}

function CoinRewards.awardCoins(player, baseAmount)
	if not player or baseAmount <= 0 then
		return 0, 0
	end

	local multiplier = player:GetAttribute("FriendBoostMultiplier") or 1
	local finalAmount = math.floor(baseAmount * multiplier)
	local bonusAmount = finalAmount - baseAmount

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local coinsVal = leaderstats:FindFirstChild("Coins")
		if coinsVal then
			coinsVal.Value = coinsVal.Value + finalAmount
		end
	end

	return finalAmount, bonusAmount
end

return CoinRewards
