local module = {
}

module.Abilities = {
	Dash = {
		Name = "Dash",
		Price = 100,
		Level = 1,
		Ability = "Dash",
		AbilityType = "Dash",
	}
}

function module:init(message: string)
	print(message)
	print(self.Abilities)
end

return module
