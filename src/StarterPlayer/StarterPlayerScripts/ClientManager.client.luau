--!strict

-- Client entry point.
-- Reusable APIs live in child ModuleScripts. Everything below the TESTING section
-- is place-specific test wiring and should not be copied into production games.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local functions = script.Parent:WaitForChild("Functions")
local SoundClient = require(functions:WaitForChild("SoundClient"))
local WaypointClient = require(functions:WaitForChild("WaypointClient"))
local WorldProgressionClient = require(functions:WaitForChild("WorldProgressionClient"))
local NPCCommunicationClient = require(functions:WaitForChild("NPCCommunicationClient"))
local UIProgression = require(
	script.Parent:WaitForChild("UIManager"):WaitForChild("UIHandler"):WaitForChild("UIProgression")
)

local systemClients: { any } = {
	SoundClient,
	WaypointClient,
	WorldProgressionClient,
	NPCCommunicationClient,
}

for _, systemClient in systemClients do
	systemClient.Init()
end

-- TESTING ONLY -----------------------------------------------------------------
local localPlayer = Players.LocalPlayer
local RUN_PROGRESSION_TESTS = true
local RUN_WAYPOINT_TEST = false
local RUN_DIALOGUE_TESTS = true
local testConnections: { RBXScriptConnection } = {}
local worldBarController: WorldProgressionClient.ProgressHandle? = nil
local worldProgress = 0
local uiProgress = 0

local function waitForRequiredChild(parent: Instance, childName: string): Instance
	local child = parent:WaitForChild(childName, 30)
	assert(child, parent:GetFullName() .. "." .. childName .. " did not replicate within 30 seconds")
	return child
end

local function connectPrompt(promptObject: Instance, callback: () -> ())
	assert(promptObject:IsA("ProximityPrompt"), promptObject:GetFullName() .. " must be a ProximityPrompt")
	local prompt = promptObject :: ProximityPrompt
	prompt.Enabled = true
	table.insert(testConnections, prompt.Triggered:Connect(callback))
end

local function bindProgressionTests()
	local testFolder = waitForRequiredChild(Workspace, "ProgressionFeedbackTests")
	local sourcePart = waitForRequiredChild(testFolder, "CollectionSource") :: BasePart
	local targetPart = waitForRequiredChild(testFolder, "CollectionTarget") :: BasePart
	local uiEffectsPart = waitForRequiredChild(testFolder, "UIEffects") :: BasePart

	local playerGui = waitForRequiredChild(localPlayer, "PlayerGui")
	local hud = waitForRequiredChild(playerGui, "HUD")
	local main = waitForRequiredChild(hud, "Main")
	local moneyTarget = waitForRequiredChild(main, "Money") :: GuiObject
	local frames = waitForRequiredChild(main, "Frames")
	local standardBars = waitForRequiredChild(frames, "Bar")
	local levelRoot = waitForRequiredChild(standardBars, "Level")
	local levelBar = waitForRequiredChild(levelRoot, "Bar") :: GuiObject

	local physicalTest = waitForRequiredChild(Workspace, "Test")
	local cookingPart = waitForRequiredChild(physicalTest, "Cooking") :: BasePart

	-- The part has no ProgressGui in Studio. BindProgressBar clones the template from
	-- WorldController; if a ProgressGui already exists, it uses that one instead.
	worldBarController = WorldProgressionClient.BindProgressBar(cookingPart, {
		CurrentValue = 0,
		MaxValue = 100,
		Stage = "Normal",
		StageText = "Cooking",
		Icon = "Cooking",
		AnimateDots = true,
		ApplyInitialFolder = true,
		FillDirection = "LeftToRight",
		PlaySound = true,
		Sound = "BarFill",
		AutoCompletedStage = true,
		CompletedStage = "Ready",
		CompletedText = "Ready",
		CompletedIcon = "Completed",
	})

	connectPrompt(waitForRequiredChild(sourcePart, "CollectPrompt"), function()
		print("[ClientManager Test] World collection prompt triggered")
		WorldProgressionClient.PlayCollection(sourcePart, targetPart, 12, {
			Icon = "Cash",
			Fade = true,
			AnimateEndpoint = true,
			PlaySound = true,
			Sound = "Cash",
			Trail = true,
			TrailColor = Color3.fromRGB(255, 220, 70),
		})
	end)

	connectPrompt(waitForRequiredChild(uiEffectsPart, "TransferPrompt"), function()
		print("[ClientManager Test] UI transfer prompt triggered")
		local previous = uiProgress
		uiProgress = (uiProgress + 20) % 120
		if uiProgress < previous then
			previous = 0
		end

		-- No Text: uses UIProgression.ProgressionTemp.
		UIProgression.PlayTransfer(nil, moneyTarget, 10, {
			RandomStart = true,
			Icon = "Cash",
			Fade = false,
			AnimateEndpoint = true,
			PlaySound = true,
			Sound = "Cash",
			FillBar = levelBar,
			TextRoot = levelRoot,
			CurrentValue = previous,
			NewValue = math.min(uiProgress, 100),
			MaxValue = 100,
			ValueFormat = "{current}/{max}",
		})
	end)

	connectPrompt(waitForRequiredChild(uiEffectsPart, "BurstPrompt"), function()
		print("[ClientManager Test] UI burst prompt triggered")
		-- Text supplied: uses UIProgression.Feedbacktemp and changes Mult.Text.
		UIProgression.PlayBurst({
			Icon = "Coin",
			Text = "",
			MinCount = 4,
			MaxCount = 10,
			Fade = true,
			PlaySound = true,
			Sound = "Coin",
		})
	end)

	connectPrompt(waitForRequiredChild(cookingPart, "ProgressionProgressPrompt"), function()
		print("[ClientManager Test] Progress bar prompt triggered")
		local controller = worldBarController
		if not controller then
			return
		end
		if worldProgress >= 100 then
			-- Completed progress stays full until a reset is explicitly requested.
			return
		end
		worldProgress = math.min(100, worldProgress + 20)
		controller:SetProgress(worldProgress, 100)
	end)

	connectPrompt(waitForRequiredChild(cookingPart, "ProgressionFirePrompt"), function()
		print("[ClientManager Test] Fire state prompt triggered")
		local controller = worldBarController
		if controller then
			controller:SetStage("OnFire", {
				Text = "Burning",
				Icon = "Fire",
				ChangeIcon = true,
				AnimateDots = true,
				ApplyFolder = true,
				PlaySound = true,
				Sound = "StateChange",
			})
		end
	end)
end

local function bindDialogueTest()
	local npcObject = waitForRequiredChild(Workspace, "npc")
	assert(npcObject:IsA("Model"), "Workspace.npc must be a Model")
	local root = waitForRequiredChild(npcObject, "HumanoidRootPart")
	local dialoguePrompt = waitForRequiredChild(root, "DialoguePrompt")
	assert(dialoguePrompt:IsA("ProximityPrompt"), "DialoguePrompt must be a ProximityPrompt")
	local dialogueBusy = false

	connectPrompt(dialoguePrompt, function()
		if dialogueBusy then
			return
		end
		dialogueBusy = true
		print("[ClientManager Test] NPC dialogue prompt triggered")
		NPCCommunicationClient.PlayWorld(npcObject, "BariWorld", {
			Prompt = dialoguePrompt,
			OnComplete = function()
				NPCCommunicationClient.PlayUI("BariIntro", {
					Prompt = dialoguePrompt,
					OnResponse = function(response, responseIndex, lineIndex)
						print(
							"[ClientManager Test] Response:",
							response.Id or response.Text,
							responseIndex,
							lineIndex
						)
					end,
					OnComplete = function()
						dialogueBusy = false
						dialoguePrompt.Enabled = true
					end,
				})
			end,
		})
	end)
end

local function runWaypointTest()
	local waypointModel = Workspace:WaitForChild("Waypoint")
	local destination = waypointModel:WaitForChild("Endpoint")
	assert(destination:IsA("BasePart"), "Workspace.Waypoint.Endpoint must be a BasePart")

	local attachmentObject = destination:FindFirstChild("WaypointAttachment")
	if not attachmentObject then
		local attachment = Instance.new("Attachment")
		attachment.Name = "WaypointAttachment"
		attachment.Parent = destination
		attachmentObject = attachment
	end
	assert(attachmentObject:IsA("Attachment"), "Endpoint.WaypointAttachment must be an Attachment")

	WaypointClient.Create("Example", attachmentObject, {
		ShowBeam = true,
		ShowDistance = true,
		Icon = "Waypoint",
		EndWhenNear = true,
		PlayReachedSound = true,
		TrackRespawns = false,
		CompletionDistance = 8,
		CallbackDistance = 30,
		OnWithinDistance = function(distance: number)
			print(string.format("Waypoint is now %d studs away", math.round(distance)))
		end,
		OnReached = function(distance: number)
			print(string.format("Waypoint reached at %d studs", math.round(distance)))
		end,
	})
end

if RunService:IsStudio() then
	if RUN_PROGRESSION_TESTS then
		task.defer(bindProgressionTests)
	end
	if RUN_WAYPOINT_TEST then
		task.defer(runWaypointTest)
	end
	if RUN_DIALOGUE_TESTS then
		task.defer(bindDialogueTest)
	end
end
-- END TESTING ONLY -------------------------------------------------------------

script.Destroying:Connect(function()
	for _, connection in testConnections do
		connection:Disconnect()
	end
	table.clear(testConnections)

	if worldBarController then
		worldBarController:Destroy()
		worldBarController = nil
	end

	UIProgression.DestroyAll()
	for index = #systemClients, 1, -1 do
		systemClients[index].Destroy()
	end
end)
