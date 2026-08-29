local Controllers = script.Parent:WaitForChild("Controllers")

for _, module in Controllers:GetChildren() do
	if not module:IsA("ModuleScript") then
		continue
	end

	local ok, controller = pcall(require, module)
	if not ok then
		warn(string.format("[Client] Failed to require %s: %s", module.Name, tostring(controller)))
		continue
	end

	if type(controller) == "table" and type(controller.Init) == "function" then
		task.spawn(function()
			local started, err = pcall(controller.Init)
			if not started then
				warn(string.format("[Client] %s.Init errored: %s", module.Name, tostring(err)))
			end
		end)
	end
end

