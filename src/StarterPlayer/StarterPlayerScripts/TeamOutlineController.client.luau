local Players = game:GetService("Players")

local TEAM_COLORS = {
	Blue = Color3.fromRGB(50, 140, 255),
	Red = Color3.fromRGB(255, 60, 60),
	Juggernaut = Color3.fromRGB(255, 200, 60),
	Hunter = Color3.fromRGB(180, 180, 180),
}

local highlights = {} -- [character] = Highlight

local function destroyHighlight(character)
	local h = highlights[character]
	if h then
		h:Destroy()
		highlights[character] = nil
	end
	if character then
		local existing = character:FindFirstChild("TeamOutline")
		if existing then existing:Destroy() end
	end
end

local function applyOutline(player)
	local character = player.Character
	if not character then
		return
	end

	local color = nil
	if player:GetAttribute("IsJuggernaut") == true then
		color = TEAM_COLORS.Juggernaut
	else
		local teamId = player:GetAttribute("TeamId")
		color = teamId and TEAM_COLORS[teamId]
	end
	if not color then
		destroyHighlight(character)
		return
	end

	local highlight = highlights[character] or character:FindFirstChild("TeamOutline")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "TeamOutline"
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillTransparency = 1
		highlight.OutlineTransparency = 0
		highlight.Parent = character
	end
	highlight.OutlineColor = color
	highlight.FillColor = color
	-- Soft gold fill on juggernaut for presence
	if player:GetAttribute("IsJuggernaut") == true then
		highlight.FillTransparency = 0.85
	else
		highlight.FillTransparency = 1
	end
	highlights[character] = highlight
end

local function hookPlayer(player)
	player:GetAttributeChangedSignal("TeamId"):Connect(function()
		applyOutline(player)
	end)
	player:GetAttributeChangedSignal("IsJuggernaut"):Connect(function()
		applyOutline(player)
	end)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			applyOutline(player)
		end)
	end)
	if player.Character then
		applyOutline(player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end
Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		destroyHighlight(player.Character)
	end
end)
