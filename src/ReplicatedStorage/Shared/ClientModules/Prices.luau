--[[
	Prices -- one cached, deduplicated MarketplaceService price lookup.

	Every Robux price in the UI comes from Roblox rather than from a number
	typed into Config, so raising a product's price on the Creator Dashboard
	updates the game without a code change and the two can never disagree.

	GetProductInfo is a web call, so three rules:

	  CACHE      one call per id per server session, shared by every label.
	  DEDUPE     twenty rows asking for the same id while it is in flight all
	             wait on the one request instead of firing twenty.
	  NEVER YIELD THE CALLER
	             Apply() returns immediately and fills the label in when the
	             answer arrives. A shop panel that builds ten rows must not
	             block ten times before the player sees anything.

	A failed lookup is cached as failed for RetryAfter seconds -- an id that
	does not exist yet (a product nobody has created) must not re-request on
	every single panel open.
]]

local MarketplaceService = game:GetService("MarketplaceService")

local Prices = {}

Prices.RetryAfter = 30
Prices.LoadingText = "..."
Prices.FailedText = "?"

local cache = {}
local pending = {}

local function cacheKey(id: number, infoType: Enum.InfoType): string
	return string.format("%s:%d", infoType.Name, id)
end

function Prices.GetInfo(id: number, infoType: Enum.InfoType?)
	if type(id) ~= "number" or id <= 0 then
		return nil
	end

	infoType = infoType or Enum.InfoType.Product

	local key = cacheKey(id, infoType)
	local entry = cache[key]

	if entry then

		if entry.Info or os.clock() - entry.At < Prices.RetryAfter then
			return entry.Info
		end
	end

	local queue = pending[key]

	if queue then
		table.insert(queue, coroutine.running())
		return coroutine.yield()
	end

	queue = {}
	pending[key] = queue

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, infoType)
	end)

	local result = ok and info or nil
	cache[key] = { Info = result, Price = result and result.PriceInRobux or nil, At = os.clock() }
	pending[key] = nil

	for _, thread in queue do
		task.spawn(thread, result)
	end

	if not ok then
		warn(string.format("[Prices] GetProductInfo(%d, %s) failed: %s", id, infoType.Name, tostring(info)))
	end

	return result
end

function Prices.Get(id: number, infoType: Enum.InfoType?): number?
	local info = Prices.GetInfo(id, infoType)
	return info and info.PriceInRobux or nil
end

function Prices.Peek(id: number, infoType: Enum.InfoType?): number?
	local entry = cache[cacheKey(id, infoType or Enum.InfoType.Product)]
	return entry and entry.Price or nil
end

--[[
	Fills a label with a price, without blocking the caller.

	  format   string.format pattern for the price, default "%s"
	  onFailed text to show when the id is unknown (defaults to Prices.FailedText)

	The label is re-checked before it is written: a shop row can easily be
	destroyed while its price is still in the air.
]]
function Prices.Apply(label: TextLabel?, id: number, infoType: Enum.InfoType?, format: string?, onFailed: string?)
	if not label then
		return
	end

	local cached = Prices.Peek(id, infoType)

	if cached then
		label.Text = string.format(format or "%s", cached)
		return
	end

	label.Text = Prices.LoadingText

	task.spawn(function()
		local price = Prices.Get(id, infoType)

		if not label.Parent then
			return
		end

		label.Text = if price
			then string.format(format or "%s", price)
			else (onFailed or Prices.FailedText)
	end)
end

return Prices
