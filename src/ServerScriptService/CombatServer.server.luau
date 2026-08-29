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
local combatAnimEvent = ReplicatedStorage:WaitForChild("CombatAnimEvent")
local ownedDataStore = DataStoreService:GetDataStore("OwnedAbilities_V1")
local KnockbackService = require(ServerScriptService:WaitForChild("KnockbackService"))

--[[
	Knockback distances are in TILES, converted with the arena's real tile size
	(7.6 studs). They used to be multiples of a hard-coded TILE_DISTANCE = 20,
	which meant a "one tile" punch actually moved the victim 2.6 tiles - a
	quarter of the arena - and the mine could throw someone 7.4 tiles.
]]
local PUNCH_RANGE_STUDS = 14 -- how far a Grid Punch reaches, root to root
local PUNCH_TILES = 1.5 -- Grid Punch / Dash Strike
local SHOCKWAVE_TILES = 0.5 -- half a tile
local MINE_TILES = 2 -- mine launches up to this many tiles per axis

local JUGGERNAUT_INCOMING_MULT = 0.5 -- half distance vs juggernaut
local JUGGERNAUT_OUTGOING_MULT = 1.75 -- juggernaut punches hit harder

local function getKnockbackDistance(attacker, targetPlayer, baseDistance)
	local distance = baseDistance
	if targetPlayer and targetPlayer:GetAttribute("IsJuggernaut") == true then
		distance = baseDistance * JUGGERNAUT_INCOMING_MULT
	elseif attacker and attacker:GetAttribute("IsJuggernaut") == true then
		distance = baseDistance * JUGGERNAUT_OUTGOING_MULT
	end
	return distance
end

--[[
	The impact burst that plays where a Grid Punch connects. Built from the
	HitVFX part on the rig in the workspace, copied into ServerStorage as a
	template at build time.
]]
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local hitVFXTemplate = ServerStorage:FindFirstChild("HitVFXTemplate")

local function playHitVFX(targetCharacter)
	if not hitVFXTemplate or not targetCharacter then
		return
	end
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end

	local effect = hitVFXTemplate:Clone()
	effect.CFrame = targetRoot.CFrame
	effect.Parent = workspace

	local longest = 0
	for _, emitter in ipairs(effect:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			local count = emitter:GetAttribute("BurstCount")
			if typeof(count) ~= "number" then
				count = 12
			end
			emitter:Emit(count)
			longest = math.max(longest, emitter.Lifetime.Max)
		end
	end

	Debris:AddItem(effect, math.max(1, longest + 0.5))
end

local function attributeCombatHit(attacker, targetChar)
	local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
	if targetPlayer then
		KillFeedService.attributeHit(targetPlayer, attacker)
	end
end

-- Physics launch: walls stop it, gravity arcs it, holes catch them.
local function applyKnockback(targetCharacter, pushDirection, distanceStuds)
	KnockbackService.apply(targetCharacter, pushDirection, distanceStuds)
end

local function tilesToStuds(tiles)
	return KnockbackService.tilesToStuds(tiles)
end
--[[
	Mines.

	The cooldown is 7.5s and a mine lives 15s, so two have always been the most
	anyone could have armed at once - but that was an accident of two unrelated
	numbers rather than a decision. The cap is explicit now: place a third and
	your oldest one is taken back, so tuning either number cannot quietly turn
	the arena into a minefield.
]]
local MAX_LIVE_MINES = 2
local MINE_LIFETIME = 15
--[[
	How far below the player we will accept a floor. The old raycast reached 60
	studs and excluded only the character, so a mine laid over a hole in a
	shrinking arena sailed through the gap and landed on the Arena Base slab
	underneath, where nobody could ever walk into it. The base and the kill
	floor are excluded outright, and anything further down than this is treated
	as no floor at all.
]]
local MINE_MAX_DROP = 12
local liveMines = setmetatable({}, { __mode = "k" }) -- [player] = { Part, ... }

local function forgetMine(player, mine)
	local list = liveMines[player]
	if not list then
		return
	end
	for i = #list, 1, -1 do
		if list[i] == mine then
			table.remove(list, i)
		end
	end
end

local function registerMine(player, mine)
	local list = liveMines[player]
	if not list then
		list = {}
		liveMines[player] = list
	end

	-- Drop any that have already expired before counting.
	for i = #list, 1, -1 do
		if not list[i].Parent then
			table.remove(list, i)
		end
	end

	while #list >= MAX_LIVE_MINES do
		local oldest = table.remove(list, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end

	table.insert(list, mine)
	mine.AncestryChanged:Connect(function(_, parent)
		if not parent then
			forgetMine(player, mine)
		end
	end)
end

local function ownsAbility(player, abilityName)
	local data = abilityData[abilityName]
	if not data then return false end
	if data.Cost == 0 then return true end
	return player:GetAttribute(abilityData.getOwnedAttributeKey(abilityName)) == true
end
--[[
	The save used to be a bare array of owned ability names, which meant the
	ability the player had equipped was thrown away on leave: every join ran
	ensureDefaultAbility, found no EquippedAbility attribute and reset them to
	Grid Punch even though they owned (and had equipped) something else.

	The record is now a table carrying both. Old bare-array saves still load -
	see normaliseSave below - so nobody loses what they bought.
]]
local function normaliseSave(saved)
	if type(saved) ~= "table" then
		return nil, nil
	end
	-- New format: { owned = { ... }, equipped = "..." }
	if saved.owned ~= nil or saved.equipped ~= nil then
		local owned = type(saved.owned) == "table" and saved.owned or {}
		local equipped = type(saved.equipped) == "string" and saved.equipped or nil
		return owned, equipped
	end
	-- Legacy format: a plain array of ability names.
	return saved, nil
end

--[[
	If the load failed we never learned what this player owns, so their
	attributes are all blank and a save would write an empty list over real
	purchases. Only players whose load actually came back are allowed to save.
]]
local loadedOwned = setmetatable({}, { __mode = "k" })

local function saveOwnedAbilities(player)
	if not loadedOwned[player] then
		return
	end

	local owned = {}
	for abilityName in pairs(abilityData) do
		if type(abilityData[abilityName]) ~= "table" then
			continue
		end
		if player:GetAttribute(abilityData.getOwnedAttributeKey(abilityName)) == true then
			table.insert(owned, abilityName)
		end
	end

	local equipped = player:GetAttribute("EquippedAbility")
	if type(equipped) ~= "string" or equipped == "" or equipped == "None" then
		equipped = nil
	end

	pcall(function()
		ownedDataStore:SetAsync(player.UserId, {
			owned = owned,
			equipped = equipped,
		})
	end)
end

-- Returns the saved equipped ability name, or nil if there wasn't one.
local function loadOwnedAbilities(player)
	local success, saved = pcall(function()
		return ownedDataStore:GetAsync(player.UserId)
	end)
	if not success then
		warn("[CombatServer] Could not load abilities for " .. player.Name .. "; saving is disabled for this session to protect their purchases.")
		return nil
	end
	loadedOwned[player] = true

	local owned, equipped = normaliseSave(saved)
	if owned then
		for _, abilityName in ipairs(owned) do
			if abilityData[abilityName] then
				player:SetAttribute(abilityData.getOwnedAttributeKey(abilityName), true)
			end
		end
	end
	return equipped
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
	-- Disabled abilities cannot be bought or equipped.
	if not abilityData.isEnabled(abilityName) then return end
	if not purchaseAbility(player, abilityName) then return end
	if player:GetAttribute("EquippedAbility") == abilityName then return end
	player:SetAttribute("EquippedAbility", abilityName)
	-- Persist the choice so it survives the next join.
	task.spawn(saveOwnedAbilities, player)
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

local function isUsableEquip(player, equipped)
	if type(equipped) ~= "string" or equipped == "" or equipped == "None" then
		return false
	end
	if not abilityData[equipped] then
		return false
	end
	-- Also catches players who had a now-disabled ability equipped from a
	-- previous session.
	if not abilityData.isEnabled(equipped) then
		return false
	end
	-- And anyone whose save claims an ability they no longer own.
	return ownsAbility(player, equipped)
end

local function ensureDefaultAbility(player)
	local savedEquip = loadOwnedAbilities(player)

	-- An attribute already on the player (set this session) wins over the save.
	local equipped = player:GetAttribute("EquippedAbility")
	if not isUsableEquip(player, equipped) then
		equipped = savedEquip
	end

	if isUsableEquip(player, equipped) then
		player:SetAttribute("EquippedAbility", equipped)
	else
		player:SetAttribute("EquippedAbility", abilityData.getDefaultAbility())
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
--[[
	Combat sounds are played from the server, parented to the part they belong
	to, so every nearby player hears them positioned rather than only the person
	who was hit. They carry the SFX SoundGroup, so the client's SFX setting
	still silences them.
]]
local soundAssets = ReplicatedStorage:WaitForChild("GameAssets"):WaitForChild("Sounds")
local sfxGroup = game:GetService("SoundService"):FindFirstChild("SFX")

local function playSoundAt(name, part, opts)
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local template = soundAssets:FindFirstChild(name)
	if not template or template.SoundId == "" then
		return nil
	end
	opts = opts or {}
	local sound = template:Clone()
	sound.SoundGroup = sfxGroup
	sound.RollOffMaxDistance = opts.maxDistance or 90
	if opts.pitchJitter then
		sound.PlaybackSpeed = sound.PlaybackSpeed + ((math.random() * 2 - 1) * opts.pitchJitter)
	end
	sound.Parent = part
	sound:Play()
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		game:GetService("Debris"):AddItem(sound, 8)
	end
	return sound
end

local function playSoundOnCharacter(name, character, opts)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return playSoundAt(name, root, opts)
end

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
--[[
	The old test compared the full 3D root-to-root vector. Two things made it
	miss for reasons a player could not see:

	* Height counted twice. A target mid-knockback, mid-jump, or simply on a
	  tile at a slightly different level pulled the direction vector off the
	  horizontal, dropping the dot product below the threshold - so a punch at
	  someone standing right in front of you failed because they were falling.
	* The same tight 60 degree arc applied at every distance, including
	  point-blank, where the angle between two touching characters swings wildly
	  with the smallest step.

	Now the comparison is flat, a sensible height difference is tolerated, and
	the arc opens up close: at arm's length you connect with anyone you are not
	actively turned away from.
]]
local HIT_VERTICAL_TOLERANCE = 8 -- studs of height difference still counted as a hit
local HIT_POINT_BLANK = 7 -- inside this, facing barely matters
local HIT_POINT_BLANK_DOT = -0.1 -- ...but you still cannot punch behind you
local HIT_CONE_DOT = 0.3 -- roughly 72 degrees either side further out

local function getTargetInFront(character, range)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local selfPlayer = Players:GetPlayerFromCharacter(character)
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.001 then
		return nil
	end
	flatLook = flatLook.Unit

	local bestTarget = nil
	local closestDist = math.huge

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer.Character and otherPlayer ~= selfPlayer and otherPlayer:GetAttribute("InArena") then
			local otherChar = otherPlayer.Character
			local humanoid = otherChar:FindFirstChild("Humanoid")
			local otherRoot = otherChar:FindFirstChild("HumanoidRootPart")
			if humanoid and humanoid.Health > 0 and otherRoot then
				local delta = otherRoot.Position - root.Position
				local flat = Vector3.new(delta.X, 0, delta.Z)
				local distance = flat.Magnitude
				if distance <= range and math.abs(delta.Y) <= HIT_VERTICAL_TOLERANCE then
					local dot = distance < 0.001 and 1 or flatLook:Dot(flat.Unit)
					local required = (distance <= HIT_POINT_BLANK) and HIT_POINT_BLANK_DOT or HIT_CONE_DOT
					if dot >= required and distance < closestDist then
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
	-- Authoritative pre-match lock: no abilities before the countdown hits GO.
	if player:GetAttribute("MatchLocked") == true then
		return
	end
	local modeValue = ReplicatedStorage:FindFirstChild("CurrentGameMode")
	local modeId = modeValue and modeValue.Value or ""
	-- Pure Survival: abilities disabled (dash still works — it's separate)
	if modeId == "PureSurvival" then
		return
	end
	-- Punch Out: everyone uses Grid Punch only
	if modeId == "PunchOut" then
		abilityRequested = "Grid Punch"
	--[[
		The juggernaut fights with fists only. They already hit harder and take
		less, so handing them a shield or a minefield on top of that leaves the
		hunters with nothing to work with.
	]]
	elseif modeId == "Juggernaut" and player:GetAttribute("IsJuggernaut") == true then
		abilityRequested = "Grid Punch"
	else
		if not abilityData[abilityRequested] then
			return
		end
		if not abilityData.isEnabled(abilityRequested) then
			return
		end
		if player:GetAttribute("EquippedAbility") ~= abilityRequested then
			return
		end
		if not ownsAbility(player, abilityRequested) then
			return
		end
	end
	if not abilityData[abilityRequested] then
		return
	end
	-- Authoritative gate: a disabled ability never fires, however it was requested.
	if not abilityData.isEnabled(abilityRequested) then
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
		-- 14 studs root-to-root. A tile is 7.6, so this reaches the next tile over
		-- and - importantly - the diagonal ones, which sit 10.7 studs away and used
		-- to be a coin flip at the old 12.
		local targetChar = getTargetInFront(character, PUNCH_RANGE_STUDS)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer and targetPlayer:GetAttribute("HasShield") == true then
				combatAnimEvent:FireAllClients("GridPunch", player.UserId)
				startAbilityCooldown(player, abilityRequested)
				targetPlayer:SetAttribute("HasShield", nil)
				local shieldVis = targetChar:FindFirstChild("ShieldVisual")
				if shieldVis then shieldVis:Destroy() end
				playSoundOnCharacter("ShieldBreak", targetChar)
				vfxEvent:FireClient(targetPlayer, "LightShake")
				return
			end
		end
		combatAnimEvent:FireAllClients("GridPunch", player.UserId)
		beginAbilityUse(player, abilityRequested)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer then
				attributeCombatHit(player, targetChar)
				vfxEvent:FireClient(player, "LightShake")
				vfxEvent:FireClient(targetPlayer, "HitStop")
			end
			-- On the target, so the impact comes from where the hit landed.
			playSoundOnCharacter("PunchHit", targetChar, { pitchJitter = 0.06 })
			pcall(function()
				QuestService.onPunchLanded(player)
			end)
			playHitVFX(targetChar)
			local pushDirection = character.HumanoidRootPart.CFrame.LookVector
			local targetPlayerForKb = Players:GetPlayerFromCharacter(targetChar)
			applyKnockback(targetChar, pushDirection, getKnockbackDistance(player, targetPlayerForKb, tilesToStuds(PUNCH_TILES)))
		else
			-- Swung at nothing: a lighter swing so a miss still reads as an action.
			playSoundOnCharacter("PunchWhiff", character, { pitchJitter = 0.08 })
		end
		-- =======================================
		-- ABILITY: DASH STRIKE
		-- =======================================
	elseif abilityRequested == "Dash Strike" then
		local targetChar = getTargetInFront(character, 30)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer and targetPlayer:GetAttribute("HasShield") == true then
				combatAnimEvent:FireAllClients("DashStrike", player.UserId)
				startAbilityCooldown(player, abilityRequested)
				targetPlayer:SetAttribute("HasShield", nil)
				local shieldVis = targetChar:FindFirstChild("ShieldVisual")
				if shieldVis then shieldVis:Destroy() end
				vfxEvent:FireClient(targetPlayer, "LightShake")
				return
			end
		end
		combatAnimEvent:FireAllClients("DashStrike", player.UserId)
		startAbilityCooldown(player, abilityRequested)
		if targetChar then
			local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
			if targetPlayer then
				attributeCombatHit(player, targetChar)
				vfxEvent:FireClient(player, "LightShake")
				vfxEvent:FireClient(targetPlayer, "HitStop")
			end
			local pushDirection = character.HumanoidRootPart.CFrame.LookVector
			local targetPlayerForKb = Players:GetPlayerFromCharacter(targetChar)
			applyKnockback(targetChar, pushDirection, getKnockbackDistance(player, targetPlayerForKb, tilesToStuds(PUNCH_TILES)))
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
		--[[
			Drop it on the floor, not at the player's feet. Placing it relative to
			the root meant a mine laid mid-jump hung in the air where nobody could
			ever walk into it.
		]]
		local dropPos = character.HumanoidRootPart.Position
		local ignore = { character, mine }
		local env = workspace:FindFirstChild("Environment")
		local arenaBase = env and env:FindFirstChild("Arena Base")
		if arenaBase then
			table.insert(ignore, arenaBase)
		end
		local killFloor = workspace:FindFirstChild("KillFloor")
		if killFloor then
			table.insert(ignore, killFloor)
		end

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = ignore
		local groundHit = workspace:Raycast(dropPos, Vector3.new(0, -60, 0), rayParams)

		-- A floor far below the player is not the floor they are standing on - it
		-- is whatever the ray found after passing through a hole.
		if groundHit and (dropPos.Y - groundHit.Position.Y) > MINE_MAX_DROP then
			groundHit = nil
		end

		if groundHit then
			mine.Position = groundHit.Position + Vector3.new(0, mine.Size.Y / 2, 0)
		else
			-- Nothing underneath (over a hole or off the edge): no mine to place.
			mine:Destroy()
			return
		end
		mine.Parent = workspace
		registerMine(player, mine)
		playSoundAt("MinePlace", mine, { maxDistance = 70 })
		-- Counted here rather than on the request, so a mine that found no ground
		-- and was discarded does not tick the quest.
		pcall(function()
			QuestService.onMinePlaced(player)
		end)
		task.delay(1, function()
			if not mine.Parent then
				return
			end
			mine.Color = Color3.fromRGB(255, 0, 0)
			-- Armed: a quiet pulse so players can hear one they cannot see.
			playSoundAt("MineBeep", mine, { maxDistance = 45 })
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
						playSoundOnCharacter("ShieldBreak", hitCharacter)
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
						randomX = math.random(-MINE_TILES, MINE_TILES)
						randomZ = math.random(-MINE_TILES, MINE_TILES)
					end
					local minePush = Vector3.new(randomX, 0, randomZ)
					local mineDist = getKnockbackDistance(player, targetPlayer, tilesToStuds(minePush.Magnitude))
					applyKnockback(hitCharacter, minePush, mineDist)
					task.wait(0.2)
					mine:Destroy()
				end
			end)
		end)
		game:GetService("Debris"):AddItem(mine, MINE_LIFETIME)
		-- =======================================
		-- ABILITY: SHIELD BUBBLE
		-- =======================================
	elseif abilityRequested == "Shield Bubble" then
		if player:GetAttribute("HasShield") == true then return end
		combatAnimEvent:FireAllClients("ShieldBubble", player.UserId)
		startAbilityCooldown(player, abilityRequested)
		player:SetAttribute("HasShield", true)
		local shield = Instance.new("Part")
		shield.Name = "ShieldVisual"
		shield.Shape = Enum.PartType.Ball
		shield.Size = Vector3.new(6, 6.5, 6)
		shield.Color = Color3.fromRGB(120, 190, 255)
		shield.Material = Enum.Material.ForceField
		--[[
			One flat shell: no light, no second halo, no pulse. Just the original
			bubble made more solid than the near-invisible ForceField default so it
			reads clearly without lighting up the arena.
		]]
		shield.Transparency = 0.3
		shield.CastShadow = false
		shield.CanCollide = false
		shield.CanQuery = false
		shield.CanTouch = false
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
		-- Anim is ~0.45s; ground impact lands near the end of the slam
		local SHOCKWAVE_IMPACT_DELAY = 0.3
		local SHOCKWAVE_RANGE = 18
		local SHOCKWAVE_PUSH = tilesToStuds(SHOCKWAVE_TILES)

		combatAnimEvent:FireAllClients("Shockwave", player.UserId)
		startAbilityCooldown(player, abilityRequested)

		local casterRoot = character:FindFirstChild("HumanoidRootPart")
		if not casterRoot then
			return
		end

		task.delay(SHOCKWAVE_IMPACT_DELAY, function()
			if not player.Parent or not character.Parent then
				return
			end
			local root = character:FindFirstChild("HumanoidRootPart") or casterRoot
			if not root or not root.Parent then
				return
			end

			local rootPos = root.Position
			vfxEvent:FireAllClients("HeavyShake")

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
									pushDirection = root.CFrame.LookVector
								end
								applyKnockback(otherPlayer.Character, pushDirection, getKnockbackDistance(player, otherPlayer, SHOCKWAVE_PUSH))
							end
						end
					end
				end
			end
		end)
	end
end)