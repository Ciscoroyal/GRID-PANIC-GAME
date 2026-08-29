return function()
    local Gradient = Instance.new("UIGradient");
    Gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("0073ba")),
		ColorSequenceKeypoint.new(0.5, Color3.fromHex("00e3fc")),
		ColorSequenceKeypoint.new(1, Color3.fromHex("0073ba")),
    })
    return Gradient;
end