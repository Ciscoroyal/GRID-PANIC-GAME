--!strict

-- Global image aliases used by every client system.
-- Values may be ordinary rbxassetid strings or any content string accepted by ImageLabel.Image.
local Images: { [string]: string } = {
	Default = "rbxassetid://130976566606660",
	Waypoint = "rbxassetid://130976566606660",
	Cash = "rbxassetid://87255997391411",
	Coin = "rbxassetid://87255997391411",
	Health = "",
	Cooking = "rbxassetid://90891900976706",
	Completed = "rbxassetid://115566144910529",
	Fire = "rbxassetid://106413382795910",
	Wirebrush = "rbxassetid://137516920261869",
	Squeegee = "",
	PaintBucket = "rbxassetid://102427065160611",
	ClickMouse = "rbxassetid://137959264882985",
	SpinMouse = "rbxassetid://137959264882985",
	Angry = "",
	Happy = "rbxassetid://88943852241686",
	Sad = "",
	Neutral = "",
	Thinking = "",
}

local ImageConfig = {
	Images = Images,
}

function ImageConfig.Resolve(nameOrImage: string?): string
	if nameOrImage == nil or nameOrImage == "" then
		return Images.Default or ""
	end

	local configured = Images[nameOrImage]
	if configured ~= nil then
		return if configured ~= "" then configured else (Images.Default or "")
	end

	-- Unknown strings are treated as direct image content IDs.
	return nameOrImage
end

return ImageConfig
