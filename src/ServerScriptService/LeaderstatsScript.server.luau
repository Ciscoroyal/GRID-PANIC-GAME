local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- Create a specific database for our coins.
-- If you ever want to completely wipe everyone's money and start fresh, just change this name to "CoinWallet_V2"!
local coinDataStore = DataStoreService:GetDataStore("CoinWallet_V1")
local xpDataStore = DataStoreService:GetDataStore("XPWallet_V1")

Players.PlayerAdded:Connect(function(player)
	-- 1. Create the leaderstats folder (this makes it show up on the top right leaderboard)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	-- 2. Create the Coins and XP values
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = leaderstats

	local xp = Instance.new("IntValue")
	xp.Name = "XP"
	xp.Parent = leaderstats

	-- 3. Load the saved money from the cloud!
	-- We use a 'pcall' (protected call) because if Roblox's internet hiccups, we don't want the script to crash.
	local success, savedCoins = pcall(function()
		return coinDataStore:GetAsync(player.UserId)
	end)

	if success then
		if savedCoins then
			coins.Value = savedCoins
			print("Loaded " .. savedCoins .. " coins for " .. player.Name)
		else
			-- First time playing! Give them a starting balance of 0
			coins.Value = 0
			print(player.Name .. " is a new player. Starting with 0 coins.")
		end
	else
		-- If Roblox's servers are having a bad day, default to 0 and warn us in the output
		coins.Value = 0
		warn("Failed to load coins for " .. player.Name)
	end

	local xpSuccess, savedXP = pcall(function()
		return xpDataStore:GetAsync(player.UserId)
	end)

	if xpSuccess and savedXP then
		xp.Value = savedXP
	else
		xp.Value = 0
	end
end)

-- 4. Save the money when they leave the game
Players.PlayerRemoving:Connect(function(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats and leaderstats:FindFirstChild("Coins") then
		local currentCoins = leaderstats.Coins.Value

		local success, errorMessage = pcall(function()
			coinDataStore:SetAsync(player.UserId, currentCoins)
		end)

		if success then
			print("Successfully saved " .. currentCoins .. " coins for " .. player.Name)
		else
			warn("CRITICAL: Failed to save coins for " .. player.Name .. " | Error: " .. tostring(errorMessage))
		end

		local currentXP = leaderstats:FindFirstChild("XP")
		if currentXP then
			pcall(function()
				xpDataStore:SetAsync(player.UserId, currentXP.Value)
			end)
		end
	end
end)

-- 5. Emergency Save
-- If the developer (you) shuts down the server for an update, this catches everyone before they are kicked out and saves their money.
game:BindToClose(function()
	print("Server shutting down! Running emergency coin save...")
	for _, player in ipairs(Players:GetPlayers()) do
		local leaderstats = player:FindFirstChild("leaderstats")
		if leaderstats then
			if leaderstats:FindFirstChild("Coins") then
				pcall(function()
					coinDataStore:SetAsync(player.UserId, leaderstats.Coins.Value)
				end)
			end
			if leaderstats:FindFirstChild("XP") then
				pcall(function()
					xpDataStore:SetAsync(player.UserId, leaderstats.XP.Value)
				end)
			end
		end
	end
	-- Give the server a couple seconds to finish uploading the data before officially dying
	task.wait(2)
end)