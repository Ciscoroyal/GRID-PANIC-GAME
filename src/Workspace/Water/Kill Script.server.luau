function onTouched(part)
	local Character = part.Parent
	local Humanoid = Character:FindFirstChild("Humanoid")
	if Humanoid then
		Character:BreakJoints()
	end
end
script.Parent.Touched:Connect(onTouched)