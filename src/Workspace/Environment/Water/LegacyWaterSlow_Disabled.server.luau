function onTouched(part)
	local Character = part.Parent
	local Humanoid = Character:FindFirstChild("Humanoid")
	local childs = Character:GetChildren()
	local colors = {}
	if Humanoid then
		if Humanoid.WalkSpeed~=10 then
			Humanoid.WalkSpeed = Humanoid.WalkSpeed - 6
		end
		for i=1,#childs do
			if (childs[i].className == "Part") then
				colors[i] = childs[i].BrickColor
			end
		end
		wait(0.1)
		for i=1,#childs do
			if (childs[i].className == "Part") then
				childs[i].BrickColor = BrickColor.new("Cyan")
			end
		end
		wait(6)
		if Humanoid.WalkSpeed~=16 and not Humanoid.WalkSpeed > 16 then
			Humanoid.WalkSpeed = Humanoid.WalkSpeed + 6
		end
		wait(1)
		for i=1,#childs do
			if (childs[i].className == "Part") then
				childs[i].BrickColor = colors[i]
			end
		end
	else
		part.BrickColor = BrickColor.new("Reddish brown")
	end
end
script.Parent.Touched:Connect(onTouched)
