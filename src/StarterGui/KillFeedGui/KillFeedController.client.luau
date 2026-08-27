local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local gui = script.Parent
local template = gui:WaitForChild("KillBanner")
template.Visible = false

local feedContainer = gui:FindFirstChild("FeedContainer")
if not feedContainer then
	feedContainer = Instance.new("Frame")
	feedContainer.Name = "FeedContainer"
	feedContainer.BackgroundTransparency = 1
	feedContainer.Size = UDim2.new(0.2, 0, 0.4, 0)
	feedContainer.Position = UDim2.new(0.78, 0, 0.17, 0)
	feedContainer.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = feedContainer
end

local killFeedEvent = ReplicatedStorage:WaitForChild("KillFeedEvent")
local MAX_ENTRIES = 6

local TEAM_COLORS = {
	Blue = Color3.fromRGB(90, 170, 255),
	Red = Color3.fromRGB(255, 95, 95),
}
local DEFAULT_NAME_COLOR = Color3.new(1, 1, 1)

local function trimEntries()
	local banners = {}
	for _, child in ipairs(feedContainer:GetChildren()) do
		if child:IsA("Frame") and child.Name == "KillBanner" then
			table.insert(banners, child)
		end
	end

	while #banners > MAX_ENTRIES do
		banners[1]:Destroy()
		table.remove(banners, 1)
	end
end

local function fadeOutBanner(banner)
	if not banner.Parent then
		return
	end

	local fadeInfo = TweenInfo.new(0.5)
	TweenService:Create(banner, fadeInfo, { BackgroundTransparency = 1 }):Play()

	for _, descendant in ipairs(banner:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, fadeInfo, { TextTransparency = 1 }):Play()
		elseif descendant:IsA("ImageLabel") then
			TweenService:Create(descendant, fadeInfo, { ImageTransparency = 1 }):Play()
		end
	end

	task.delay(0.5, function()
		if banner.Parent then
			banner:Destroy()
		end
	end)
end

local function addEntry(victimName, killerName, victimTeam, killerTeam)
	local banner = template:Clone()
	banner.Visible = true
	banner.Size = UDim2.new(1, 0, 0, 40)
	banner.Position = UDim2.new(0, 0, 0, 0)
	banner.AnchorPoint = Vector2.new(0, 0)
	banner.Parent = feedContainer

	local killerText = banner:FindFirstChild("KillerText")
	local killIcon = banner:FindFirstChild("KillIcon")
	local victimText = banner:FindFirstChild("VictimText")

	local hasKiller = killerName ~= nil and killerName ~= ""

	if killerText then
		killerText.Position = UDim2.new(0, 0, 0, 0)
		if hasKiller then
			killerText.Text = killerName
			killerText.TextColor3 = TEAM_COLORS[killerTeam] or DEFAULT_NAME_COLOR
			killerText.Visible = true
			killerText.LayoutOrder = 1
		else
			killerText.Visible = false
		end
	end

	if killIcon then
		killIcon.Position = UDim2.new(0, 0, 0, 0)
		killIcon.Visible = true
		killIcon.LayoutOrder = hasKiller and 2 or 1
	end

	if victimText then
		victimText.Position = UDim2.new(0, 0, 0, 0)
		victimText.Text = victimName or "Unknown"
		victimText.TextColor3 = TEAM_COLORS[victimTeam] or DEFAULT_NAME_COLOR
		victimText.Visible = true
		victimText.LayoutOrder = hasKiller and 3 or 2
	end

	trimEntries()
	task.delay(5, function()
		fadeOutBanner(banner)
	end)
end

killFeedEvent.OnClientEvent:Connect(addEntry)