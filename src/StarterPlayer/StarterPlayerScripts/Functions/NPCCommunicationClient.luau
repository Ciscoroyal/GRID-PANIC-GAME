--!strict

-- Typed client-facing entry point for both physical and screen NPC conversations.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local system = ReplicatedStorage:WaitForChild("Systems"):WaitForChild("NPCCommunication")
local DialogueConfig = require(system:WaitForChild("DialogueConfig"))
local WorldDialogue = require(system:WaitForChild("WorldDialogue"))
local UIDialogue = require(
	script.Parent.Parent:WaitForChild("UIManager"):WaitForChild("UIHandler"):WaitForChild("UIDialogue")
)

export type Response = DialogueConfig.Response
export type Line = DialogueConfig.Line
export type Conversation = DialogueConfig.Conversation
export type WorldOptions = WorldDialogue.WorldOptions
export type WorldDialogueHandle = WorldDialogue.WorldDialogueHandle
export type UIOptions = UIDialogue.UIOptions
export type UIDialogueHandle = UIDialogue.UIDialogueHandle
export type ConversationInput = string | Conversation

local NPCCommunicationClient = {}

local function resolveConversation(input: ConversationInput): Conversation
	if type(input) == "string" then
		return DialogueConfig.Get(input)
	end
	return input
end

function NPCCommunicationClient.GetConversation(name: string): Conversation
	return DialogueConfig.Get(name)
end

function NPCCommunicationClient.PlayWorld(
	npc: Model,
	conversation: ConversationInput,
	options: WorldOptions?
): WorldDialogueHandle
	return WorldDialogue.Play(npc, resolveConversation(conversation), options)
end

function NPCCommunicationClient.PlayUI(
	conversation: ConversationInput,
	options: UIOptions?
): UIDialogueHandle
	return UIDialogue.Play(resolveConversation(conversation), options)
end

function NPCCommunicationClient.StopWorld(npc: Model)
	WorldDialogue.Stop(npc)
end

function NPCCommunicationClient.StopUI()
	UIDialogue.Stop()
end

function NPCCommunicationClient.Init()
end

function NPCCommunicationClient.Destroy()
	UIDialogue.Stop()
	WorldDialogue.DestroyAll()
end

return NPCCommunicationClient
