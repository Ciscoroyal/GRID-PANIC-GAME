local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameModeData = require(ReplicatedStorage:WaitForChild("GameModeData"))
local UIHelpers = require(ReplicatedStorage:WaitForChild("UIHelpers"))
local Audio = require(ReplicatedStorage:WaitForChild("Audio"))
local voteStateEvent = ReplicatedStorage:WaitForChild("VoteStateEvent")
local voteModeEvent = ReplicatedStorage:WaitForChild("VoteModeEvent")

local localPlayer = Players.LocalPlayer
local voteGui = script.Parent
local voteFrame = voteGui:WaitForChild("VoteFrame")
local toggleVote = voteGui:WaitForChild("ToggleVote")
local optionsFrame = voteFrame:WaitForChild("Options")
local closeBtn = voteFrame:WaitForChild("Close")

local myVote = nil
local counts = {}
local selectedStrokeColor = Color3.fromRGB(255, 220, 60)
local normalStrokeColor = Color3.new(0, 0, 0)

local function getOptionColumns()
	local cols = {}
	for _, col in ipairs(optionsFrame:GetChildren()) do
		if col:IsA("Frame") then
			table.insert(cols, col)
		end
	end
	table.sort(cols, function(a, b)
		return a.LayoutOrder < b.LayoutOrder or (a.LayoutOrder == b.LayoutOrder and a.Name < b.Name)
	end)
	return cols
end

local function setNestedText(label, text)
	if not label then return end
	label.Text = text
	local inner = label:FindFirstChild("Title")
	if inner and inner:IsA("TextLabel") then
		inner.Text = text
	end
end

--[[
	The vote panel hangs a fixed gap below the status line.

	It used to sit at a hardcoded 0.018 of the screen, which only lined up on
	desktop. TimerGui ignores the GUI inset and measures from the physical top
	(IgnoreGuiInset = true, DeviceSafeInsets); VoteGui respects it
	(CoreUISafeInsets). On desktop that inset is a thin topbar so the two looked
	adjacent, but on a phone it is the topbar plus the notch safe area, which
	pushed the vote panel far below the timer.

	Measuring the label and subtracting the inset puts both into the same space,
	so the gap is identical on every device.
]]
local GuiService = game:GetService("GuiService")
local VOTE_GAP_SCALE = 0.034 -- matches the desktop spacing the game ships with
local FALLBACK_Y = 0.018

local statusLabel = nil
local function getStatusLabel()
	if statusLabel and statusLabel.Parent then
		return statusLabel
	end
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	local timerGui = playerGui and playerGui:FindFirstChild("TimerGui")
	statusLabel = timerGui and timerGui:FindFirstChild("StatusLabel")
	return statusLabel
end

local function getOpenPosition()
	local label = getStatusLabel()
	local viewport = voteGui.AbsoluteSize
	if not label or viewport.Y <= 0 then
		return UDim2.new(0.5, 0, FALLBACK_Y, 0)
	end

	-- Label space is physical-top based; ours starts below the inset.
	local labelBottom = label.AbsolutePosition.Y + label.AbsoluteSize.Y
	local y = labelBottom - GuiService:GetGuiInset().Y + (VOTE_GAP_SCALE * viewport.Y)
	return UDim2.new(0.5, 0, 0, math.max(y, 0))
end

local function setVoteVisible(isVisible)
	if isVisible then
		UIHelpers.animatePanelOpen(voteFrame, {
			startPos = UDim2.new(0.5, 0, -0.02, 0),
			center = getOpenPosition(),
			duration = 0.35,
		})
	else
		UIHelpers.animatePanelClose(voteFrame, {
			endPos = UDim2.new(0.5, 0, -0.02, 0),
			duration = 0.2,
		})
	end
end

-- Re-seat it if the window or safe area changes while the panel is open.
voteGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if voteFrame.Visible then
		voteFrame.Position = getOpenPosition()
	end
end)

local function refreshCounts()
	for _, col in ipairs(getOptionColumns()) do
		local modeId = col:GetAttribute("ModeId")
		local countLabel = col:FindFirstChild("VoteCount")
		setNestedText(countLabel, tostring((modeId and counts[modeId]) or 0))
		local btn = col:FindFirstChild("Button")
		if btn then
			local stroke = btn:FindFirstChildOfClass("UIStroke")
			if stroke then
				local selected = myVote ~= nil and myVote ~= "" and myVote == modeId
				stroke.Color = selected and selectedStrokeColor or normalStrokeColor
				stroke.Thickness = selected and 3 or 2
			end
		end
	end
end

local function applyOptions(options)
	if typeof(options) ~= "table" then return end
	local cols = getOptionColumns()
	for i, col in ipairs(cols) do
		local opt = options[i]
		local btn = col:FindFirstChild("Button")
		if opt then
			col.Visible = true
			col:SetAttribute("ModeId", opt.id)
			if btn then
				btn:SetAttribute("ModeId", opt.id)
				setNestedText(btn:FindFirstChild("Title"), opt.displayName or opt.id)
			end
		else
			col.Visible = false
			col:SetAttribute("ModeId", nil)
			if btn then btn:SetAttribute("ModeId", nil) end
		end
	end
end

local function applyState(state)
	if typeof(state) ~= "table" then return end
	if typeof(state.options) == "table" then applyOptions(state.options) end
	if state.visible ~= nil then setVoteVisible(state.visible == true) end
	if typeof(state.counts) == "table" then counts = state.counts end
	-- Always apply myVote from server. Remotes omit nil, so a new vote session
	-- sends "" (or omits while visible=true) to clear the yellow highlight.
	if state.myVote ~= nil then
		myVote = (state.myVote ~= "" and state.myVote) or nil
	elseif state.visible == true then
		myVote = nil
	end
	refreshCounts()
end

local function castVote(modeId)
	if typeof(modeId) ~= "string" or modeId == "" then return end
	if not GameModeData.getById(modeId) then return end
	if myVote and counts[myVote] then
		counts[myVote] = math.max((counts[myVote] or 1) - 1, 0)
	end
	myVote = modeId
	counts[modeId] = (counts[modeId] or 0) + 1
	refreshCounts()
	Audio.play("VoteCast")
	voteModeEvent:FireServer(modeId)
end

for _, col in ipairs(getOptionColumns()) do
	local btn = col:FindFirstChild("Button")
	if btn and btn:IsA("GuiButton") then
		local lastFire = 0
		local function onActivate()
			local now = os.clock()
			if now - lastFire < 0.2 then return end
			lastFire = now
			local modeId = btn:GetAttribute("ModeId") or col:GetAttribute("ModeId")
			if typeof(modeId) == "string" then castVote(modeId) end
		end
		btn.Activated:Connect(onActivate)
		btn.MouseButton1Click:Connect(onActivate)
	end
end

closeBtn.Activated:Connect(function() setVoteVisible(false) end)
closeBtn.MouseButton1Click:Connect(function() setVoteVisible(false) end)

toggleVote.Event:Connect(function(action)
	if action == "Close" then setVoteVisible(false) return end
	if action == "Open" then setVoteVisible(true) return end
	setVoteVisible(not voteFrame.Visible)
end)

for _, col in ipairs(getOptionColumns()) do
	local btn = col:FindFirstChild("Button")
	if btn then
		-- castVote plays VoteCast; suppress the generic click so a vote is not
		-- two overlapping sounds.
		btn:SetAttribute("NoClickSound", true)
		UIHelpers.bindButtonHover(btn)
	end
end
UIHelpers.bindButtonHover(closeBtn)

voteStateEvent.OnClientEvent:Connect(applyState)
voteFrame.Visible = false
refreshCounts()
