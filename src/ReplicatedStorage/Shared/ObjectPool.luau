--[[
	ObjectPool  (ReplicatedStorage/Shared)
	------------------------------------------------------------------
	A tiny, general-purpose pool to cut down on Instance.new churn (which
	costs memory + GC pressure, especially for short-lived projectile and
	VFX parts created every shot). Instead of creating and destroying, we
	reuse: Get() hands back a free object (or makes one via `factory`),
	Return(obj) parks it for reuse.

	Usage:
		local pool = ObjectPool.new(function()
			local p = Instance.new("Part")
			-- one-time setup that never changes
			return p
		end, {
			reset = function(p) p.Transparency = 0 end,   -- before reuse (optional)
			park  = function(p) p.Parent = nil end,        -- on Return (optional)
			max   = 64,                                     -- cap parked objects (optional)
		})

		local part = pool:Get()
		...
		pool:Return(part)   -- instead of part:Destroy()

	Notes:
		* Parked objects beyond `max` are destroyed rather than stored, so
		  the pool never grows without bound.
		* Keep pooled objects parented to nil (or a hidden folder) while idle.
		* This pool is not thread-safe across actors; use it on one thread.
------------------------------------------------------------------ ]]

local ObjectPool = {}
ObjectPool.__index = ObjectPool

function ObjectPool.new(factory, options)
	assert(type(factory) == "function", "ObjectPool.new requires a factory function")
	options = options or {}
	return setmetatable({
		_factory = factory,
		_reset = options.reset,
		_park = options.park,
		_max = options.max or 128,
		_free = {},
		_count = 0,
	}, ObjectPool)
end

function ObjectPool:Prewarm(n)
	for _ = 1, n do
		if self._count >= self._max then break end
		local obj = self._factory()
		if self._park then self._park(obj) end
		self._count += 1
		self._free[self._count] = obj
	end
end

function ObjectPool:Get()
	local obj
	if self._count > 0 then
		obj = self._free[self._count]
		self._free[self._count] = nil
		self._count -= 1
	else
		obj = self._factory()
	end
	if self._reset then self._reset(obj) end
	return obj
end

function ObjectPool:Return(obj)
	if not obj then return end
	if self._park then self._park(obj) end
	if self._count >= self._max then

		if typeof(obj) == "Instance" then obj:Destroy() end
		return
	end
	self._count += 1
	self._free[self._count] = obj
end

function ObjectPool:Clear()
	for i = self._count, 1, -1 do
		local obj = self._free[i]
		self._free[i] = nil
		if typeof(obj) == "Instance" then obj:Destroy() end
	end
	self._count = 0
end

return ObjectPool
