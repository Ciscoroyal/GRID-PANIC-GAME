--[[
	CanvasSizer -- drives a ScrollingFrame's CanvasSize from its layout's
	AbsoluteContentSize.

	AutomaticCanvasSize is the obvious thing to reach for and it is wrong here:
	it measures children but ignores UIPadding, so the last row sits under the
	bottom padding and cannot be scrolled to. Measuring the LAYOUT instead gives
	the real content height, and the padding is added back explicitly.

		CanvasSizer.Bind(scrollingFrame)         -- finds the layout itself
		CanvasSizer.Bind(frame, { Padding = 20 })
		CanvasSizer.BindAll(hud)                 -- every ScrollingFrame under it

	The binding is live: rows added or removed later resize the canvas without
	anyone calling anything. Binding twice is a no-op, so BindAll is safe to run
	after a panel has built its rows.

	ScrollingDirection decides which axis is measured, so a horizontal list is
	not given a height it does not need.

	--------------------------------------------------------------------------
	WHY THIS REFUSES SOME FRAMES
	--------------------------------------------------------------------------
	Inside a ScrollingFrame a child's SCALE size resolves against the CANVAS,
	not against the frame. So a list of rows sized {1, 0}, {0.32, 0} is a
	feedback loop waiting to happen:

		canvas H -> each row 0.32*H -> 10 rows measure 3.2*H -> canvas 3.2*H

	That diverges. It is not a bug that can be tuned around -- with n rows at
	scale s the loop only settles when n*s < 1, which for any real list means
	the canvas collapses to zero instead.

	So a frame whose rows are scale-sized ON THE SCROLLING AXIS is refused and
	warned about rather than bound. Content-driven canvas sizing needs rows
	whose height does not depend on the canvas -- offset heights, AutomaticSize,
	or a UIAspectRatioConstraint driving height from width (width is safe: the
	cross-axis canvas stays 0, so width still resolves against the frame).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local MARKER = "CanvasSizerBound"

local CanvasSizer = {}

local function feedsBack(frame: ScrollingFrame, layout: UIGridStyleLayout): (boolean, string?)
	local vertical = frame.ScrollingDirection ~= Enum.ScrollingDirection.X

	for _, child in frame:GetChildren() do
		if not child:IsA("GuiObject") or not child.Visible then
			continue
		end

		if child.AutomaticSize ~= Enum.AutomaticSize.None then
			continue
		end

		if child:FindFirstChildOfClass("UIAspectRatioConstraint") then
			continue
		end

		local scale = if vertical then child.Size.Y.Scale else child.Size.X.Scale

		if scale > 0 then
			return true, child.Name
		end
	end

	return false, nil
end

local function layoutOf(frame: ScrollingFrame): UIGridStyleLayout?
	for _, child in frame:GetChildren() do
		if child:IsA("UIGridStyleLayout") then
			return child
		end
	end

	return nil
end

local function paddingOf(frame: ScrollingFrame): (number, number)
	local padding = frame:FindFirstChildOfClass("UIPadding")

	if not padding then
		return 0, 0
	end

	return padding.PaddingTop.Offset + padding.PaddingBottom.Offset,
		padding.PaddingLeft.Offset + padding.PaddingRight.Offset
end

function CanvasSizer.Bind(frame: ScrollingFrame, options: { Padding: number? }?): boolean
	if not frame or not frame:IsA("ScrollingFrame") then
		return false
	end

	if frame:GetAttribute(MARKER) then
		return true
	end

	local layout = layoutOf(frame)
	if not layout then
		return false
	end

	frame:SetAttribute(MARKER, true)

	frame.AutomaticCanvasSize = Enum.AutomaticSize.Y

	local extra = (options and options.Padding) or Config.ScrollFrames.Padding or 0

	local queued = false

	local function apply()
		queued = false

		if not frame.Parent then
			return
		end

		local content = layout.AbsoluteContentSize
		local vertical, horizontal = paddingOf(frame)
		local direction = frame.ScrollingDirection

		local height = if direction == Enum.ScrollingDirection.X
			then 0
			else content.Y + vertical + extra

		local width = if direction == Enum.ScrollingDirection.Y
			then 0
			else content.X + horizontal + extra

		local target = UDim2.fromOffset(width, height)

		if frame.CanvasSize ~= target then
			frame.CanvasSize = target
		end
	end

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		if queued then
			return
		end

		queued = true
		task.defer(apply)
	end)

	apply()

	return true
end

function CanvasSizer.BindAll(root: Instance, options: { Padding: number? }?): number
	local bound = 0

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ScrollingFrame") and not descendant:GetAttribute(MARKER) then
			if CanvasSizer.Bind(descendant, options) then
				bound += 1
			end
		end
	end

	return bound
end

return CanvasSizer
