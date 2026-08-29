--!strict

-- Full-screen NPC dialogue. This module owns only the existing PlayerGui.HUD.Main.NpcChat template.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local systems = ReplicatedStorage:WaitForChild("Systems")
local shared = ReplicatedStorage:WaitForChild("Shared")
local DialogueConfig = require(systems:WaitForChild("NPCCommunication"):WaitForChild("DialogueConfig"))
local ImageConfig = require(shared:WaitForChild("ImageConfig"))
local SoundConfig = require(shared:WaitForChild("SoundConfig"))
local SoundController = require(systems:WaitForChild("SoundController"))

export type Response = DialogueConfig.Response
export type Line = DialogueConfig.Line
export type Conversation = DialogueConfig.Conversation

export type UIOptions = {
	Typewriter: boolean?,
	LetterDelay: number?,
	PlayLetterSound: boolean?,
	LetterSound: string?,
	PlayTransitionSound: boolean?,
	TransitionSound: string?,
	Prompt: ProximityPrompt?,
	SlideOffset: number?,
	OnLine: ((line: Line, index: number) -> ())?,
	OnResponse: ((response: Response, responseIndex: number, lineIndex: number) -> ())?,
	OnComplete: (() -> ())?,
}

export type UIDialogueHandle = {
	Stop: (self: UIDialogueHandle) -> (),
	SkipTyping: (self: UIDialogueHandle) -> (),
	IsPlaying: (self: UIDialogueHandle) -> boolean,
	GetFrame: (self: UIDialogueHandle) -> Frame,
}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local frameObject = playerGui:WaitForChild("HUD"):WaitForChild("Main"):WaitForChild("NpcChat")
assert(frameObject:IsA("Frame"), frameObject:GetFullName() .. " must be a Frame")
local frame = frameObject :: Frame
local chat = frame:WaitForChild("Chat") :: TextLabel
local charName = frame:WaitForChild("CharName") :: TextLabel
local charImage = frame:WaitForChild("CharImage") :: ImageLabel
local nextButton = frame:WaitForChild("Next") :: ImageButton
local responsesFrame = frame:WaitForChild("Responses") :: Frame
local firstButton = responsesFrame:WaitForChild("1") :: TextButton
local secondButton = responsesFrame:WaitForChild("2") :: TextButton
local imageScaleObject = charImage:WaitForChild("DialogueImageScale")
assert(imageScaleObject:IsA("UIScale"), imageScaleObject:GetFullName() .. " must be a UIScale")
local imageScale = imageScaleObject :: UIScale
local homePosition = frame.Position
local extraButtons: { TextButton } = {}
local imageTween: Tween? = nil

local UIDialogue = {}
local Handle = {}
Handle.__index = Handle
local activeHandle: any = nil

local function safeCall(callback: any, ...: any)
	if type(callback) ~= "function" then
		return
	end
	local arguments = table.pack(...)
	task.spawn(function()
		local ok, message = xpcall(function()
			callback(table.unpack(arguments, 1, arguments.n))
		end, debug.traceback)
		if not ok then
			warn("[UIDialogue] Callback failed:\n" .. message)
		end
	end)
end

local function playNamed2D(name: string?): any?
	if not name or name == "" then
		return nil
	end
	local sound = SoundConfig.Get(name)
	return if sound then SoundController.Play2D(sound) else nil
end

local function offsetPosition(position: UDim2, yScale: number): UDim2
	return UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale + yScale, position.Y.Offset)
end

local function setButtonText(button: TextButton, text: string)
	local title = button:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		title.Text = text
	else
		button.Text = text
	end
end

local function clearResponses(handle: any)
	for _, connection in handle._responseConnections do
		connection:Disconnect()
	end
	table.clear(handle._responseConnections)
	for _, button in extraButtons do
		button.Visible = false
	end
	firstButton.Visible = false
	secondButton.Visible = false
	responsesFrame.Visible = false
end

local function resumeWaiting(handle: any, value: any)
	if not handle._waiting or not handle._waitingThread then
		return
	end
	local thread = handle._waitingThread
	handle._waiting = false
	handle._waitingThread = nil
	task.spawn(thread, value)
end

local function waitForAdvance(handle: any): any
	handle._waiting = true
	handle._waitingThread = coroutine.running()
	return coroutine.yield()
end

local function showResponses(handle: any, responses: { Response })
	clearResponses(handle)
	nextButton.Visible = false
	responsesFrame.Visible = true

	for index, response in responses do
		local button: TextButton
		if index == 1 then
			button = firstButton
		elseif index == 2 then
			button = secondButton
		else
			local poolIndex = index - 2
			button = extraButtons[poolIndex]
			if not button then
				button = firstButton:Clone()
				button.Name = "PooledResponse" .. index
				button.Parent = responsesFrame
				extraButtons[poolIndex] = button
			end
		end
		button.LayoutOrder = index
		button.Visible = true
		setButtonText(button, response.Text)
		table.insert(handle._responseConnections, button.Activated:Connect(function()
			if activeHandle == handle and not handle._typing then
				resumeWaiting(handle, {
					Response = response,
					Index = index,
				})
			end
		end))
	end
end

local function setCharacterImage(imageName: string): boolean
	local resolved = ImageConfig.Resolve(imageName)
	local changed = charImage.Image ~= resolved or not charImage.Visible
	charImage.Image = resolved
	charImage.Visible = true
	return changed
end

local function applyCharacterImage(conversation: Conversation, line: Line): boolean
	if line.HideCharacterImage == true or conversation.HideCharacterImage == true then
		local changed = charImage.Visible
		charImage.Visible = false
		return changed
	end
	if line.CharacterImage then
		return setCharacterImage(line.CharacterImage)
	end
	if conversation.CharacterImage then
		return setCharacterImage(conversation.CharacterImage)
	end
	local changed = charImage.Visible
	charImage.Visible = false
	return changed
end

local function popCharacterImage()
	if imageTween then
		imageTween:Cancel()
	end
	imageScale.Scale = 0.7
	imageTween = TweenService:Create(
		imageScale,
		TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	imageTween:Play()
end

local function typeLine(handle: any, text: string)
	chat.Text = ""
	handle._typing = true
	handle._skipTyping = false

	if handle._options.Typewriter == false then
		chat.Text = text
		handle._typing = false
		return
	end

	local delay = math.max(0.005, handle._options.LetterDelay or 0.025)
	for first, last in utf8.graphemes(text) do
		if handle._cancelled or handle._skipTyping then
			break
		end
		chat.Text = string.sub(text, 1, last)
		local grapheme = string.sub(text, first, last)
		if handle._options.PlayLetterSound ~= false and not string.match(grapheme, "%s") then
			playNamed2D(handle._options.LetterSound or "NPCType")
		end
		task.wait(delay)
	end

	if handle._skipTyping and handle._voiceHandle then
		handle._voiceHandle:Stop(0.04)
		handle._voiceHandle = nil
	end
	if not handle._cancelled then
		chat.Text = text
	end
	handle._typing = false
end

local function closeFrame(handle: any)
	clearResponses(handle)
	nextButton.Visible = false
	local tween = TweenService:Create(
		frame,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = offsetPosition(homePosition, handle._options.SlideOffset or 0.18) }
	)
	tween.Completed:Once(function()
		if activeHandle == nil or activeHandle == handle then
			frame.Visible = false
			frame.Position = homePosition
			if handle._prompt and handle._prompt.Parent then
				handle._prompt.Enabled = handle._promptWasEnabled
			end
		end
	end)
	tween:Play()
end

function UIDialogue.Play(conversation: Conversation, options: UIOptions?): UIDialogueHandle
	assert(type(conversation) == "table" and type(conversation.Lines) == "table", "conversation is invalid")
	if activeHandle then
		activeHandle:Stop()
	end

	local settings = options or {}
	local handle = setmetatable({
		_options = settings,
		_cancelled = false,
		_playing = true,
		_typing = false,
		_skipTyping = false,
		_waiting = false,
		_waitingThread = nil,
		_voiceHandle = nil,
		_responseConnections = {},
		_prompt = settings.Prompt,
		_promptWasEnabled = if settings.Prompt then settings.Prompt.Enabled else false,
	}, Handle)
	activeHandle = handle

	clearResponses(handle)
	nextButton.Visible = false
	charName.Text = conversation.Speaker
	chat.Text = ""
	chat.Visible = true
	local firstLine = conversation.Lines[1]
	local firstImageChanged = false
	if firstLine then
		local firstText = firstLine.Text
		local firstIsText = firstText ~= nil and firstText ~= ""
		if not firstIsText and firstLine.Emotion and firstLine.Emotion ~= "" then
			firstImageChanged = setCharacterImage(firstLine.Emotion)
			chat.Visible = false
		else
			firstImageChanged = applyCharacterImage(conversation, firstLine)
			chat.Visible = true
			if settings.Typewriter == false and firstText then
				chat.Text = firstText
			end
		end
	end
	if handle._prompt then
		handle._prompt.Enabled = false
	end
	frame.Position = offsetPosition(homePosition, settings.SlideOffset or 0.18)
	frame.Visible = true
	if firstImageChanged and charImage.Visible then
		popCharacterImage()
	end
	TweenService:Create(
		frame,
		TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = homePosition }
	):Play()
	if settings.PlayTransitionSound ~= false then
		playNamed2D(settings.TransitionSound or "NPCOpen")
	end

	task.spawn(function()
		local lineIndex = 1
		while lineIndex >= 1 and lineIndex <= #conversation.Lines and not handle._cancelled do
			local line = conversation.Lines[lineIndex]
			task.wait(math.max(0, line.WaitBefore or 0))
			if handle._cancelled then
				break
			end

			clearResponses(handle)
			nextButton.Visible = false
			local text = line.Text
			local isTextBeat = text ~= nil and text ~= ""
			local isEmotionBeat = not isTextBeat and line.Emotion ~= nil and line.Emotion ~= ""
			assert(isTextBeat or isEmotionBeat, "Each UI dialogue line needs Text or Emotion")

			local imageChanged: boolean
			if isEmotionBeat then
				imageChanged = setCharacterImage(line.Emotion :: string)
				chat.Visible = false
			else
				imageChanged = applyCharacterImage(conversation, line)
				chat.Visible = true
			end
			if imageChanged and charImage.Visible then
				popCharacterImage()
			end
			if handle._voiceHandle then
				handle._voiceHandle:Stop(0.05)
				handle._voiceHandle = nil
			end
			if isTextBeat then
				handle._voiceHandle = playNamed2D(line.Voice)
			elseif line.EmotionSound then
				playNamed2D(line.EmotionSound)
			end
			safeCall(settings.OnLine, line, lineIndex)
			if isTextBeat then
				typeLine(handle, text :: string)
			else
				handle._typing = false
				chat.Text = ""
			end
			if handle._cancelled then
				break
			end

			local choices = line.Responses
			if choices and #choices > 0 then
				showResponses(handle, choices)
			else
				nextButton.Visible = true
			end

			local result = waitForAdvance(handle)
			if handle._cancelled then
				break
			end

			if type(result) == "table" and result.Response then
				local response: Response = result.Response
				local responseIndex: number = result.Index
				safeCall(settings.OnResponse, response, responseIndex, lineIndex)
				local closesByDefault = responseIndex == 2
					and response.Close == nil
					and response.NextLine == nil
				if response.Close == true or closesByDefault then
					break
				end
				lineIndex = response.NextLine or line.NextLine or (lineIndex + 1)
			else
				lineIndex = line.NextLine or (lineIndex + 1)
			end
		end

		if handle._voiceHandle then
			handle._voiceHandle:Stop(0.05)
			handle._voiceHandle = nil
		end
		handle._playing = false
		if activeHandle == handle then
			activeHandle = nil
		end
		if not handle._cancelled then
			closeFrame(handle)
			safeCall(settings.OnComplete)
		end
	end)

	return handle :: any
end

function Handle:SkipTyping()
	if self._typing then
		self._skipTyping = true
	end
end

function Handle:Stop()
	if self._cancelled then
		return
	end
	self._cancelled = true
	self._playing = false
	if self._voiceHandle then
		self._voiceHandle:Stop(0.04)
		self._voiceHandle = nil
	end
	if self._prompt and self._prompt.Parent then
		self._prompt.Enabled = self._promptWasEnabled
	end
	resumeWaiting(self, { Stopped = true })
	clearResponses(self)
	nextButton.Visible = false
	frame.Visible = false
	frame.Position = homePosition
	if activeHandle == self then
		activeHandle = nil
	end
end

function Handle:IsPlaying(): boolean
	return self._playing and not self._cancelled
end

function Handle:GetFrame(): Frame
	return frame
end

function UIDialogue.Stop()
	if activeHandle then
		activeHandle:Stop()
	end
end

function UIDialogue.IsPlaying(): boolean
	return activeHandle ~= nil and activeHandle:IsPlaying()
end

nextButton.Activated:Connect(function()
	local handle = activeHandle
	if not handle then
		return
	end
	if handle._typing then
		handle:SkipTyping()
	elseif handle._waiting then
		resumeWaiting(handle, "Next")
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	local handle = activeHandle
	if not handle or not handle._typing then
		return
	end
	local inputType = input.UserInputType
	local isPointer = inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.Touch
	local isButton = inputType == Enum.UserInputType.Keyboard
		or string.find(inputType.Name, "Gamepad") ~= nil
	if isPointer or (isButton and not gameProcessed) then
		handle:SkipTyping()
	end
end)

frame.Visible = false

return UIDialogue
