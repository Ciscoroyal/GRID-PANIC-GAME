local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AbilityData = require(ReplicatedStorage:WaitForChild("AbilityData"))

local UIHelpers = {}

function UIHelpers.prepareImageLabel(imageLabel)
	if not imageLabel then
		return
	end
	imageLabel.BackgroundTransparency = 1
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.Visible = true
end

function UIHelpers.setAvatarImage(imageLabel, userId)
	UIHelpers.prepareImageLabel(imageLabel)
	imageLabel.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"

	if not userId then
		return
	end

	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end)
		if ok and imageLabel.Parent then
			imageLabel.Image = content
		end
	end)
end

function UIHelpers.setAbilityImage(imageLabel, abilityName)
	UIHelpers.prepareImageLabel(imageLabel)

	local abilityInfo = AbilityData[abilityName]
	if abilityInfo and abilityInfo.ImageId and abilityInfo.ImageId ~= "" then
		imageLabel.Image = abilityInfo.ImageId
		imageLabel.Visible = true
	else
		imageLabel.Image = ""
		imageLabel.Visible = false
	end
end

return UIHelpers
