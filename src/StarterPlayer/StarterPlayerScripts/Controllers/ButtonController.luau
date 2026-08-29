local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ClientModules = Shared:WaitForChild("ClientModules")
local Prices = require(ClientModules:WaitForChild("Prices"))
local CanvasSizer = require(ClientModules:WaitForChild("CanvasSizer"))

local UI = require(script.Parent.Parent:WaitForChild("UIManager"):WaitForChild("UIHandler"))

local player = Players.LocalPlayer

local RESOLVE_TIMEOUT = 10

local PANELS = {
	{ Button = { "Main", "Buttons", "Store" },    Frame = { "Main", "Frames", "Store" } },
	{ Button = { "Main", "Buttons", "Settings" },     Frame = { "Main", "Frames", "Settings" } },
	{ Button = { "Main", "Buttons", "Rebirth" }, Frame = { "Main", "Frames", "Rebirth" } },
	{ Button = { "Main", "Buttons", "Rewards" },  Frame = { "Main", "Frames", "Rewards" } },
	--{ Button = { "Main", "Frames", "Bar", "Products", "Increase" },  Frame = { "Main", "Frames", "EXP" } },
}

local WORLD_PANELS = {
	{ "Main", "Frames", "Upgrade" },
}

local ButtonController = {}

local function resolve(root: Instance, path: { string })
	local current = root

	for _, segment in path do
		current = current:WaitForChild(segment, RESOLVE_TIMEOUT)

		if not current then
			return nil
		end
	end

	return current
end

local function sellsSomething(instance: Instance?): boolean
	local attributes = Config.Monetization.Attributes
	local current = instance

	while current and not current:IsA("ScreenGui") do
		for _, name in { attributes.ProductKey, attributes.PassKey, attributes.ProductId, attributes.PassId } do
			if current:GetAttribute(name) ~= nil then
				return true
			end
		end

		current = current.Parent
	end

	return false
end

local function bind(button: GuiButton, onClick)
	if not button or not button:IsA("GuiButton") then
		return
	end

	if button:GetAttribute("UIButtonBound") then
		return
	end

	UI.setupButton(button, onClick)
end

local function promptProduct(key: string, product)
	if product.Id == 0 then
		warn(string.format(
			"[ButtonController] Product %q has no Id yet. Set Config.Monetization.Products.%s.Id",
			key,
			key
		))
		return
	end

	MarketplaceService:PromptProductPurchase(player, product.Id)
end

local function setupPanels(hud: Instance)
	for _, entry in PANELS do
		local button = resolve(hud, entry.Button)
		local frame = resolve(hud, entry.Frame)

		if not button or not button:IsA("GuiButton") or not frame or not frame:IsA("GuiObject") then
			warn(string.format(
				"[ButtonController] Cannot wire panel HUD.%s -> HUD.%s",
				table.concat(entry.Button, "."),
				table.concat(entry.Frame, ".")
			))
			continue
		end

		if button.Parent and button.Parent:IsA("GuiObject") then
			UI.KeepAbovePanels(button.Parent)
		end

		bind(button, function()
			UI.ToggleFrame(frame, button)
		end)

		local top = frame:FindFirstChild("Top")
		local close = top and top:FindFirstChild("Close")

		if close and close:IsA("GuiButton") then
			bind(close, function()
				UI.CloseFrame(frame)
			end)
		end
	end
end

local function priceLabelOf(button: Instance): TextLabel?
	local price = button:FindFirstChild(Config.Monetization.Store.PriceName)

	if not price then
		return nil
	end

	if price:IsA("TextLabel") then
		return price
	end

	local inner = price:FindFirstChild("Title")

	return (inner and inner:IsA("TextLabel")) and inner or nil
end

local function setupProducts(hud: Instance)
	for key, product in Config.Monetization.Products do

		if not product.ButtonPath then continue end

		local button = resolve(hud, product.ButtonPath)

		if not button or not button:IsA("GuiButton") then
			warn(string.format(
				"[ButtonController] No button for product %q at HUD.%s",
				key,
				table.concat(product.ButtonPath, ".")
			))
			continue
		end

		local title = button:FindFirstChild("Title")
		if title and title:IsA("TextLabel") and product.Label then
			UI.ChangeText(title, product.Label)
		end

		local priceLabel = priceLabelOf(button)

		if priceLabel then
			if product.Id and product.Id ~= 0 then
				Prices.Apply(priceLabel, product.Id, Enum.InfoType.Product, "%s", Config.Trails.UnavailableText)
			else

				UI.ChangeText(priceLabel, Config.Trails.UnavailableText)
			end
		end

		bind(button, function()
			promptProduct(key, product)
		end)
	end
end

local function setupUpgradeMachine(hud: Instance)
	local panel = resolve(hud, Config.Upgrade.PanelPath)

	if not panel or not panel:IsA("GuiObject") then
		warn("[ButtonController] Upgrade panel not found; machine prompts will not open it")
		return
	end

	local function isMachinePrompt(prompt: ProximityPrompt): boolean
		local ancestor = prompt.Parent

		while ancestor and ancestor ~= workspace do
			if ancestor.Name == Config.Upgrade.PromptModelName then
				return true
			end

			ancestor = ancestor.Parent
		end

		return false
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
		if triggeringPlayer ~= player or not isMachinePrompt(prompt) then
			return
		end

		UI.OpenFrame(panel)
	end)

	if Config.Upgrade.PromptActionText then
		for _, descendant in workspace:GetDescendants() do
			if descendant:IsA("ProximityPrompt") and isMachinePrompt(descendant) then
				descendant.ActionText = Config.Upgrade.PromptActionText
			end
		end
	end
end

local FOREIGN_BUTTONS = {
	
}

local function setupRemaining(hud: Instance)
	local foreign = {}

	for _, path in FOREIGN_BUTTONS do
		local button = resolve(hud, path)

		if button then
			foreign[button] = true
		end
	end

	for _, descendant in hud:GetDescendants() do
		if descendant:IsA("GuiButton") and not foreign[descendant] and not sellsSomething(descendant) then
			bind(descendant, function() end)
		end
	end
end

local function setupWorldPanels(hud: Instance)
	for _, path in WORLD_PANELS do
		local frame = resolve(hud, path)
		local top = frame and frame:FindFirstChild("Top")
		local close = top and top:FindFirstChild("Close")

		if close and close:IsA("GuiButton") then
			bind(close, function()
				UI.CloseFrame(frame)
			end)
		end
	end
end

function ButtonController.Init()
	local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")

	setupPanels(hud)
	setupWorldPanels(hud)
	setupProducts(hud)
--	setupUpgradeMachine(hud)
	setupRemaining(hud)

	CanvasSizer.BindAll(hud)
end

return ButtonController
