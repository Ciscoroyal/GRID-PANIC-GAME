local VFXPlayer = {}

VFXPlayer.Defaults = {
	EmitCount = 1,
	Duration = 0.15,
	CleanupDelay = 3,
	WeldParts = true,
	AnchorPositionParts = true,
	EmitAttributes = {
		"EmitCount",
		"Emit",
		"BurstCount",
	},
}

local Handle = {}
Handle.__index = Handle

function Handle:Emit()
	for _, emitter in self.Emitters do
		if emitter.Parent then
			emitter:Emit(VFXPlayer.GetEmitCount(emitter, self.Options))
		end
	end
end

function Handle:Stop()
	for _, instance in self.Instances do
		if instance:IsA("ParticleEmitter") or instance:IsA("Beam") or instance:IsA("Trail") then
			instance.Enabled = false
		elseif instance:IsA("Sound") then
			instance:Stop()
		end
	end
end

function Handle:Destroy()
	self:Stop()

	for _, clone in self.Clones do
		if clone.Parent then
			clone:Destroy()
		end
	end

	if self.PositionPart and self.PositionPart.Parent then
		self.PositionPart:Destroy()
	end

	table.clear(self.Clones)
	table.clear(self.Instances)
	table.clear(self.Emitters)
end

local function readOption(options, key)
	if options and options[key] ~= nil then
		return options[key]
	end

	return VFXPlayer.Defaults[key]
end

local function getFirstBasePart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveTarget(target)
	if not target then
		return nil, nil
	end

	if target:IsA("Attachment") then
		return target.Parent, target
	end

	if target:IsA("BasePart") then
		return target, nil
	end

	if target:IsA("Model") then
		return getFirstBasePart(target), nil
	end

	return nil, nil
end

local function getTemplates(vfx)
	if vfx:IsA("Folder") then
		return vfx:GetChildren()
	end

	return { vfx }
end

local function addDescendants(handle, root)
	table.insert(handle.Instances, root)

	for _, descendant in root:GetDescendants() do
		table.insert(handle.Instances, descendant)

		if descendant:IsA("ParticleEmitter") then
			table.insert(handle.Emitters, descendant)
		end
	end
end

local function weldToTarget(part, targetPart)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "VFXWeld"
	weld.Part0 = part
	weld.Part1 = targetPart
	weld.Parent = part
end

local function placeClone(clone, targetPart, targetAttachment, options)
	if clone:IsA("Attachment") then
		if targetAttachment then
			clone.CFrame = targetPart.CFrame:ToObjectSpace(targetAttachment.WorldCFrame)
		end

		clone.Parent = targetPart
		return
	end

	if clone:IsA("BasePart") then
		clone.CFrame = targetAttachment and targetAttachment.WorldCFrame or targetPart.CFrame
		clone.Parent = targetPart

		if readOption(options, "WeldParts") then
			clone.Anchored = false
			weldToTarget(clone, targetPart)
		elseif readOption(options, "AnchorPositionParts") then
			clone.Anchored = true
		end

		return
	end

	if clone:IsA("Model") then
		clone:PivotTo(targetAttachment and targetAttachment.WorldCFrame or targetPart.CFrame)
		clone.Parent = targetPart

		if readOption(options, "WeldParts") then
			for _, descendant in clone:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = false
					weldToTarget(descendant, targetPart)
				end
			end
		end

		return
	end

	clone.Parent = targetAttachment or targetPart
end

function VFXPlayer.GetEmitCount(emitter, options)
	local attributes = readOption(options, "EmitAttributes")

	for _, attributeName in attributes do
		local value = emitter:GetAttribute(attributeName)

		if typeof(value) == "number" then
			return value
		end
	end

	return readOption(options, "EmitCount")
end

function VFXPlayer.Play(vfx: Folder?, target: Object, options: {})
	local targetPart, targetAttachment = resolveTarget(target)

	if not vfx or not vfx.Parent or not targetPart then
		return nil
	end

	local handle = setmetatable({
		Source = vfx,
		Target = target,
		Options = options,
		Clones = {},
		Instances = {},
		Emitters = {},
	}, Handle)

	for _, template in getTemplates(vfx) do
		local clone = template:Clone()

		placeClone(clone, targetPart, targetAttachment, options)
		table.insert(handle.Clones, clone)
		addDescendants(handle, clone)
	end

	local duration = readOption(options, "Duration")

	for _, instance in handle.Instances do
		if instance:IsA("ParticleEmitter") then
			if not duration then
				instance.Enabled = false
			end

			instance:Emit(VFXPlayer.GetEmitCount(instance, options))
		elseif instance:IsA("Beam") or instance:IsA("Trail") then
			instance.Enabled = true
		elseif instance:IsA("Sound") then
			instance:Play()
		end
	end

	if duration and duration > 0 then
		task.delay(duration, function()
			handle:Stop()
		end)
	end

	local cleanupDelay = readOption(options, "CleanupDelay")

	if cleanupDelay and cleanupDelay > 0 then
		task.delay(cleanupDelay, function()
			handle:Destroy()
		end)
	end

	return handle
end

function VFXPlayer.PlayAtPosition(vfx: Folder?, position: Vector3, options: {}?)
	local part = Instance.new("Part")
	part.Name = "VFXPosition"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = typeof(position) == "CFrame" and position or CFrame.new(position)
	part.Parent = workspace

	local handle = VFXPlayer.Play(vfx, part, options)

	if handle then
		handle.PositionPart = part
	else
		part:Destroy()
	end

	return handle
end

local AURA_CLASSES = {
	"ParticleEmitter",
	"Attachment",
	"Beam",
	"Trail",
	"PointLight",
	"SpotLight",
	"SurfaceLight",
	"Smoke",
	"Fire",
	"Sparkles",
	"Highlight",
}

local function isAuraVisual(instance: Instance): boolean
	for _, className in AURA_CLASSES do
		if instance:IsA(className) then
			return true
		end
	end

	return false
end

function VFXPlayer.AttachAura(source: Instance?, character: Model?, options: { [string]: any }?)
	if not source or not character then
		return nil
	end

	local marker = (options and options.Marker) or "VFXAura"

	local handle = setmetatable({
		Source = source,
		Target = character,
		Options = options,
		Clones = {},
		Instances = {},
		Emitters = {},
	}, Handle)

	for _, limbSource in source:GetChildren() do
		local limb = character:FindFirstChild(limbSource.Name)

		if not limb or not limb:IsA("BasePart") then
			continue
		end

		for _, child in limbSource:GetChildren() do
			if not isAuraVisual(child) then
				continue
			end

			local clone = child:Clone()
			clone:SetAttribute(marker, true)
			clone.Parent = limb

			table.insert(handle.Clones, clone)
			addDescendants(handle, clone)
		end
	end

	if #handle.Clones == 0 then
		return nil
	end

	return handle
end

function VFXPlayer.DetachAura(handle, fadeOut: number?)
	if not handle then
		return
	end

	handle:Stop()

	if fadeOut and fadeOut > 0 then
		task.delay(fadeOut, function()
			handle:Destroy()
		end)

		return
	end

	handle:Destroy()
end

function VFXPlayer.Stop(handle)
	if handle then
		handle:Stop()
	end
end

function VFXPlayer.Destroy(handle)
	if handle then
		handle:Destroy()
	end
end

return VFXPlayer
