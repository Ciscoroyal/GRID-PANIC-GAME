local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")
local KillFeedService = require(ServerScriptService:WaitForChild("KillFeedService"))
local QuestService = require(ServerScriptService:WaitForChild("QuestService"))
local useAbilityEvent = ReplicatedStorage:WaitForChild("UseAbilityEvent")
local abilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))
local vfxEvent = ReplicatedStorage:WaitForChild("VFXEvent")
local ownedDataStore = DataStoreService:GetDataStore("OwnedAbilities_V1")
local TILE_DISTANCE = 20

local function attributeCombatHit(attacker, targetChar)
	local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
	if targetPlayer then
		KillFeedService.attributeHit(targetPlayer, attacker)
	end
end

local function tweenKnockback(root, pushDirection, distance)
 pushDirection = Vector3.new(pushDirection.X, 0, pushDirection.Z)
 if pushDirection.Magnitude < 0.001 then return end
 pushDirection = pushDirection.Unit
 local startPos = root.Position
 local newPos = startPos + (pushDirection * distance)
 newPos = Vector3.new(newPos.X, startPos.Y, newPos.Z)
 local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
 if look.Magnitude < 0.001 then look = pushDirection else look = look.Unit end
 local targetCFrame = CFrame.new(newPos, newPos + look)
 local knockbackInfo = TweenInfo.new(0.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
 TweenService:Create(root, knockbackInfo, {CFrame = targetCFrame}):Play()
end
local function ownsAbility(player, abilityName)
	local data = abilityData[abilityName]
	if not data then return false end
	if data.Cost == 0 then return true end
	return player:GetAttribute(abilityData.getOwnedAttributeKey(abilityName)) == true
end
local function saveOwnedAbilities(player)
	local owned = {}
	for abilityName in pairs(abilityData) do
		if type(abilityData[abilityName]) ~= "table" then
			continue
		end
		if player:GetAttribute(abilityData.getOwnedAttributeKey(abilityName)) == true then
			table.insert(owned, abilityName)
		end
	end
	pcall(function()
		ownedDataStore:SetAsync(player.UserId, owned)
	end)
end
local function loadOwnedAbilities(player)
	local success, saved = pcall(function()
		return ownedDataStore:GetAsync(player.UserId)
	end)
	if success and saved then
		for _, abilityName in ipairs(saved) do
			if abilityData[abilityName] then
				player:SetAttribute(abilityData.getOwnedAttributeKey(abilityName), true)
			end
		end
	end
end
local function purchaseAbility(player, abilityName)
	local data = abilityData[abilityName]
	if not data or ownsAbility(player, abilityName) then
		return true
	end
	local leaderstats = player:FindFirstChild("leaderstats")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	if not coins or coins.Value < data.Cost then
		warn(player.Name .. " cannot afford " .. abilityName)
		return false
	end
	coins.Value = coins.Value - data.Cost
	player:SetAttribute(abilityData.getOwnedAttributeKey(abilityName), true)
	saveOwnedAbilities(player)
	return true
end
-- =========================================================
-- SYSTEM: EQUIP ABILITIES (The Server Bridge)
-- =========================================================
local equipAbilityEvent = ReplicatedStorage:WaitForChild("EquipAbilityEvent")
equipAbilityEvent.OnServerEvent:Connect(function(player, abilityName)
	if not abilityData[abilityName] then return end
	if not purchaseAbility(player, abilityName) then return end
	player:SetAttribute("EquippedAbility", abilityName)
end)

local purchaseAbilityVFXEvent = ReplicatedStorage:FindFirstChild("PurchaseAbilityVFXEvent")
if purchaseAbilityVFXEvent then
	purchaseAbilityVFXEvent.OnServerEvent:Connect(function(player, abilityName, variantName, price)
		if typeof(abilityName) ~= "string" or typeof(variantName) ~= "string" then
			return
		end
		if not abilityData[abilityName] then
			return
		end

		price = tonumber(price) or 0
		local ownedKey = "OwnVFX_" .. abilityName:gsub(" ", "_") .. "_" .. variantName:gsub(" ", "_")
		local equippedKey = "EquippedVFX_" .. abilityName:gsub(" ", "_")

		if price > 0 and player:GetAttribute(ownedKey) ~= true then
			local leaderstats = player:FindFirstChild("leaderstats")
			local coins = leaderstats and leaderstats:FindFirstChild("Coins")
			if not coins or coins.Value < price then
				return
			end
			coins.Value = coins.Value - price
			player:SetAttribute(ownedKey, true)
		end

		player:SetAttribute(equippedKey, variantName)
	end)
end

local function ensureDefaultAbility(player)
	loadOwnedAbilities(player)
	local equipped = player:GetAttribute("EquippedAbility")
	if not equipped or equipped == "" or equipped == "None" then
		player:SetAttribute("EquippedAbility", "Grid Punch")
	end
end

Players.PlayerAdded:Connect(function(player)
	ensureDefaultAbility(player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	ensureDefaultAbility(player)
end
Players.PlayerRemoving:Connect(function(player)
	saveOwnedAbilities(player)
end)
-- =========================================================
-- SYSTEM: COOLDOWN RESET (Round Start / Equip)
-- =========================================================
local function resetAbilityCooldown(player)
	if player:GetAttribute("InArena") == true then
		player:SetAttribute("AbilityCooldownEnd", nil)
	end
end
local function setupCooldownListener(player)
	player:GetAttributeChangedSignal("InArena"):Connect(function()
		resetAbilityCooldown(player)
	end)
	player:GetAttributeChangedSignal("EquippedAbility"):Connect(function()
		resetAbilityCooldown(player)
	end)
	resetAbilityCooldown(player)
end
local function isAbilityOnCooldown(player)
	local cooldownEnd = player:GetAttribute("AbilityCooldownEnd")
	if not cooldownEnd then return false end
	return workspace:GetServerTimeNow() < cooldownEnd
end
local function startAbilityCooldown(player, abilityName)
	local data = abilityData[abilityName]
	if not data or not data.Cooldown then return end
	player:SetAttribute("AbilityCooldownEnd", workspace:GetServerTimeNow() + data.Cooldown)
end
Players.PlayerAdded:Connect(setupCooldownListener)
for _, player in ipairs(Players:GetPlayers()) do
	setupCooldownListener(player)
end
-- =========================================================
-- HELPER: HIT DETECTION (The "Cone of Vision")
-- =========================================================
local function getTargetInFront(character, range)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local bestTarget = nil
	local closestDist = range
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer.Character and otherPlayer ~= Players:GetPlayerFromCharacter(character) and otherPlayer:GetAttribute("InArena") then
			local otherChar = otherPlayer.Character
			local humanoid = otherChar:FindFirstChild("Humanoid")
			local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and otherRoot then
				local vectorToTarget = otherRoot.Position - root.Position
				local distance = vectorToTarget.Magnitude
				if distance <= range then
					local directionToTarget = vectorToTarget.Unit
					local dotProduct = root.CFrame.LookVector:Dot(directionToTarget)
					if dotProduct > 0.5 and distance < closestDist then
						closestDist = distance
						bestTarget = otherChar
					end
				end
			end
		end
	end
	return bestTarget
end
-- =========================================================
-- SYSTEM: ABILITY EXECUTION
-- =========================================================
local function trackAbilityQuest(player)
	pcall(function()
		QuestService.onAbilityUsed(player)
	end)
end

local function beginAbilityUse(player, abilityName)
	startAbilityCooldown(player, abilityName)
	trackAbilityQuest(player)
end

useAbilityEvent.OnServerEvent:Connect(function(player, abilityRequested)
	if player:GetAttribute("InArena") ~= true then
		return
	end
	if not abilityData[abilityRequested] then
		return
	end
	if player:GetAttribute("EquippedAbility") ~= abilityRequested then
		return
	end
	if not ownsAbility(player, abilityRequested) then
		return
	end
	if isAbilityOnCooldown(player) then
		return
	end
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
		-- =======================================
	-- ABILITY: GRID PUNCH
	-- =======================================
	if abilityRequested == "Grid Punch" then
		local targetChar = getTargetInFront(character, 12)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer and targetPlayer:GetAttribute("HasShield") == true then
				startAbilityCooldown(player, abilityRequested)
				targetPlayer:SetAttribute("HasShield", nil)
				local shieldVis = targetChar:FindFirstChild("ShieldVisual")
				if shieldVis then shieldVis:Destroy() end
				vfxEvent:FireClient(targetPlayer, "LightShake")
				return
			end
		end
		beginAbilityUse(player, abilityRequested)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer then
				attributeCombatHit(player, targetChar)
				vfxEvent:FireClient(player, "LightShake")
				vfxEvent:FireClient(targetPlayer, "HitStop")
			end
			local targetRoot = targetChar.HumanoidRootPart
			local pushDirection = character.HumanoidRootPart.CFrame.LookVector
			tweenKnockback(targetRoot, pushDirection, TILE_DISTANCE)
		else
		end
		-- =======================================
		-- ABILITY: DASH STRIKE
		-- =======================================
	elseif abilityRequested == "Dash Strike" then
		local targetChar = getTargetInFront(character, 15)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer and targetPlayer:GetAttribute("HasShield") == true then
				startAbilityCooldown(player, abilityRequested)
				targetPlayer:SetAttribute("HasShield", nil)
				local shieldVis = targetChar:FindFirstChild("ShieldVisual")
				if shieldVis then shieldVis:Destroy() end
				vfxEvent:FireClient(targetPlayer, "LightShake")
				return
			end
		end
		startAbilityCooldown(player, abilityRequested)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer then
				attributeCombatHit(player, targetChar)
				vfxEvent:FireClient(player, "LightShake")
				vfxEvent:FireClient(targetPlayer, "HitStop")
			end
			local targetRoot = targetChar.HumanoidRootPart
			local pushDirection = character.HumanoidRootPart.CFrame.LookVector
			tweenKnockback(targetRoot, pushDirection, TILE_DISTANCE)
		else
		end
		elseif abilityRequested == "Proximity Mine" then
		startAbilityCooldown(player, abilityRequested)
		local mine = Instance.new("Part")
		mine.Name = "ProxMine"
		mine.Size = Vector3.new(6, 0.2, 6)
		mine.Color = Color3.fromRGB(255, 120, 0)
		mine.Material = Enum.Material.Neon
		mine.Anchored = true
		mine.CanCollide = false
		local dropPos = character.HumanoidRootPart.Position
		mine.Position = Vector3.new(dropPos.X, dropPos.Y - 2.5, dropPos.Z)
		mine.Parent = workspace
		task.delay(1, function()
			mine.Color = Color3.fromRGB(255, 0, 0)
			local triggered = false
			mine.Touched:Connect(function(hit)
				if triggered then return end
				local hitCharacter = hit.Parent
				local targetRoot = hitCharacter:FindFirstChild("HumanoidRootPart")
				local targetPlayer = Players:GetPlayerFromCharacter(hitCharacter)
				if targetRoot and targetPlayer and targetPlayer:GetAttribute("InArena") then
					triggered = true
					if targetPlayer:GetAttribute("HasShield") == true then
						targetPlayer:SetAttribute("HasShield", nil)
						local shieldVis = hitCharacter:FindFirstChild("ShieldVisual")
						if shieldVis then shieldVis:Destroy() end
						mine.Transparency = 0.5
						mine.Size = Vector3.new(12, 12, 12)
						task.wait(0.2)
						mine:Destroy()
						return
					end
					KillFeedService.attributeHit(targetPlayer, player)
					mine.Transparency = 0.5
					mine.Size = Vector3.new(12, 12, 12)
					local randomX, randomZ = 0, 0
					while randomX == 0 and randomZ == 0 do
						randomX = math.random(-2, 2) * TILE_DISTANCE
						randomZ = math.random(-2, 2) * TILE_DISTANCE
					end
					local minePush = Vector3.new(randomX, 0, randomZ); tweenKnockback(targetRoot, minePush, minePush.Magnitude)
					task.wait(0.2)
					mine:Destroy()
				end
			end)
		end)
		game:GetService("Debris"):AddItem(mine, 15)
		-- =======================================
		-- ABILITY: SHIELD BUBBLE
		-- =======================================
	elseif abilityRequested == "Shield Bubble" then
		if player:GetAttribute("HasShield") == true then return end
		startAbilityCooldown(player, abilityRequested)
		player:SetAttribute("HasShield", true)
		local shield = Instance.new("Part")
		shield.Name = "ShieldVisual"
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.new(5.5, 6, 5.5) 
		shield.Color = Color3.fromRGB(100, 150, 255)
		shield.Material = Enum.Material.ForceField 
		shield.CanCollide = false
		shield.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = shield
		weld.Part1 = character.HumanoidRootPart
		shield.Position = character.HumanoidRootPart.Position
		shield.Parent = character
		weld.Parent = shield
		task.delay(8, function()
			if player:GetAttribute("HasShield") == true then
				player:SetAttribute("HasShield", nil)
				if shield and shield.Parent then
					shield:Destroy()
				end
			end
		end)
		-- =======================================
		-- ABILITY: SHOCKWAVE
		-- =======================================
	elseif abilityRequested == "Shockwave" then
		startAbilityCooldown(player, abilityRequested)
		vfxEvent:FireAllClients("HeavyShake")
		local rootPos = character.HumanoidRootPart.Position
		local SHOCKWAVE_RANGE = 18 
		local wave = Instance.new("Part")
		wave.Name = "ShockwaveVisual"
		wave.Shape = Enum.PartType.Ball
		wave.Size = Vector3.new(2, 2, 2)
		wave.Position = rootPos
		wave.Color = Color3.fromRGB(200, 255, 255) 
		wave.Material = Enum.Material.Neon
		wave.Anchored = true
		wave.CanCollide = false
		wave.Parent = workspace
		local waveTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local waveTween = TweenService:Create(wave, waveTweenInfo, {
			Size = Vector3.new(SHOCKWAVE_RANGE * 2, SHOCKWAVE_RANGE * 2, SHOCKWAVE_RANGE * 2),
			Transparency = 1
		})
		waveTween:Play()
		game:GetService("Debris"):AddItem(wave, 0.4) 
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player and otherPlayer:GetAttribute("InArena") == true and otherPlayer.Character then
				local targetRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
				if targetRoot then
					local targetPos = targetRoot.Position
					local flatRoot = Vector3.new(rootPos.X, 0, rootPos.Z)
					local flatTarget = Vector3.new(targetPos.X, 0, targetPos.Z)
					local distance = (flatTarget - flatRoot).Magnitude
					if distance <= SHOCKWAVE_RANGE then
						if otherPlayer:GetAttribute("HasShield") == true then
							otherPlayer:SetAttribute("HasShield", nil)
							local shieldVis = otherPlayer.Character:FindFirstChild("ShieldVisual")
							if shieldVis then shieldVis:Destroy() end
						else
							KillFeedService.attributeHit(otherPlayer, player)
							local pushDirection = (flatTarget - flatRoot).Unit
							if distance < 0.1 then 
								pushDirection = character.HumanoidRootPart.CFrame.LookVector 
							end
							tweenKnockback(targetRoot, pushDirection, TILE_DISTANCE)
						end
					end
				end
			end
		end
	end
end)