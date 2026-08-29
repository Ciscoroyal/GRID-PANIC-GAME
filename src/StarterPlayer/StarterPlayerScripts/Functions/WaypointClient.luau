--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Waypoint = require(ReplicatedStorage:WaitForChild("Systems"):WaitForChild("Waypoint"))
local localPlayer = Players.LocalPlayer

export type WaypointOptions = Waypoint.WaypointOptions
export type WaypointHandle = {
	Start: (self: WaypointHandle) -> (),
	Cancel: (self: WaypointHandle) -> (),
	Destroy: (self: WaypointHandle) -> (),
	IsActive: (self: WaypointHandle) -> boolean,
}

local WaypointClient = {}
local PLAYER_ATTACHMENT_NAME = "WaypointAttachment"
local activeWaypoints: { [string]: WaypointHandle } = {}

local function getPlayerAttachment(): Attachment
	local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	local existing = rootPart:FindFirstChild(PLAYER_ATTACHMENT_NAME)
	if existing then
		assert(existing:IsA("Attachment"), "HumanoidRootPart.WaypointAttachment must be an Attachment")
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = PLAYER_ATTACHMENT_NAME
	attachment.Parent = rootPart
	return attachment
end

function WaypointClient.Get(waypointId: string): WaypointHandle?
	return activeWaypoints[waypointId]
end

function WaypointClient.Cancel(waypointId: string): boolean
	local controller = activeWaypoints[waypointId]
	if not controller then
		return false
	end
	activeWaypoints[waypointId] = nil
	controller:Destroy()
	return true
end

function WaypointClient.CancelAll()
	for waypointId, controller in activeWaypoints do
		activeWaypoints[waypointId] = nil
		controller:Destroy()
	end
end

function WaypointClient.Create(
	waypointId: string,
	endAttachment: Attachment,
	options: WaypointOptions?
): WaypointHandle
	assert(waypointId ~= "", "waypointId cannot be empty")
	assert(endAttachment:IsA("Attachment"), "endAttachment must be an Attachment")
	WaypointClient.Cancel(waypointId)

	local managedOptions: WaypointOptions = if options then table.clone(options) else {}
	local suppliedOnReached = managedOptions.OnReached
	local controller: WaypointHandle

	managedOptions.OnReached = function(distance: number)
		task.defer(function()
			if activeWaypoints[waypointId] == controller and not controller:IsActive() then
				activeWaypoints[waypointId] = nil
				controller:Destroy()
			end
		end)
		if suppliedOnReached then
			suppliedOnReached(distance)
		end
	end

	controller = Waypoint.new(getPlayerAttachment(), endAttachment, managedOptions) :: WaypointHandle
	activeWaypoints[waypointId] = controller
	controller:Start()
	return controller
end

function WaypointClient.Init()
	-- Reusable initialization belongs here. Test bindings stay in ClientManager.
end

function WaypointClient.Destroy()
	WaypointClient.CancelAll()
end

return WaypointClient
