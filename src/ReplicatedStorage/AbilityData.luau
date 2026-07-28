local AbilityData = {
	["Grid Punch"] = {
		ImageId = "rbxassetid://86703704591003", -- <== Add your uploaded Image IDs here!
		Description = "Strikes an adjacent opponent and knocks them back one tile.",
		Cooldown = 5,
		Cost = 0,
		Color = Color3.fromRGB(255, 100, 100)
	},
	["Dash Strike"] = {
		ImageId = "rbxassetid://95876138451179",
		Description = "Dashing into an occupied tile punches the opponent out.",
		Cooldown = 5,
		Cost = 100,
		Color = Color3.fromRGB(100, 255, 100)
	},
	["Shield Bubble"] = {
		ImageId = "rbxassetid://126356124209577",
		Description = "Absorbs one enemy punch or environmental hazard.",
		Cooldown = 7.5,
		Cost = 150,
		Color = Color3.fromRGB(100, 100, 255)
	},
	["Proximity Mine"] = {
		ImageId = "rbxassetid://81388360158621",
		Description = "Drops a trap that launches a player into a random tile.",
		Cooldown = 7.5,
		Cost = 200,
		Color = Color3.fromRGB(255, 165, 0)
	},
	["Shockwave"] = {
		ImageId = "rbxassetid://127893012565209",
		Description = "Ground slam that knocks all surrounding players away.",
		Cooldown = 7.5,
		Cost = 300,
		Color = Color3.fromRGB(255, 255, 0)
	}
}

function AbilityData.getOwnedAttributeKey(abilityName)
	return "Own_" .. abilityName:gsub(" ", "_")
end

return AbilityData