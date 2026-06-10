-- ============================================================================
-- Instance prototype
--
-- All View instances (and every subclass) inherit from this table. It holds
-- ONLY methods — no namespace fields — so `instance.buf` / `instance.win`
-- always resolve to the integer handles set in `:new`, with no risk of
-- cascading into the lazy submodule namespace below.
-- ============================================================================

---@class Beast.View.Instance
---@field buf integer|false   -- buffer handle; `false` after :close()
---@field win integer|false   -- window handle; `false` after :close()
local Instance = {}
Instance.__index = Instance

---@param buf integer
---@param win integer
---@return Beast.View.Instance
function Instance:new(buf, win)
	return setmetatable({ buf = buf or false, win = win or false }, self)
end

---@return boolean
function Instance:is_valid()
	if not self.buf or not self.win then
		return false
	end
	return vim.api.nvim_buf_is_valid(self.buf) and vim.api.nvim_win_is_valid(self.win)
end

function Instance:close()
	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_close(self.win, true)
	end
	-- Mark closed with `false` (not `nil`) so guards like `if v.buf then` read falsy.
	self.buf = false
	self.win = false
end

--- Create a subclass. `init(obj, ...)` runs after construction so callers can
--- attach extra state (namespace ids, records, etc.). The returned table is
--- itself a class: callable (`Sub(buf, win, …)`), with its own `:new` / `:extend`.
---
--- Pair with a class declaration so LuaLS types the result correctly:
---
---   ---@class Beast.Toast.View : Beast.View.Instance
---   ---@field ns integer
---   ---@overload fun(buf?: integer, win?: integer, ns: integer): Beast.Toast.View
---   local ToastView = View:extend(
---     ---@param obj Beast.Toast.View
---     function(obj, ns) obj.ns = ns end
---   )
---@generic T : Beast.View.Instance
---@param init? fun(obj: T, ...: any)
---@return T
function Instance:extend(init)
	local parent = self

	local cls = setmetatable({}, {
		__index = parent,
		__call = function(t, ...)
			return t:new(...)
		end,
	})
	cls.__index = cls

	function cls:new(buf, win, ...)
		local obj = setmetatable({
			buf = buf or false,
			win = win or false,
		}, cls)

		if init then
			init(obj, ...)
		end

		return obj
	end

	return cls
end

-- ============================================================================
-- Module / namespace
--
-- `Beast.View` exposes the submodules (`.buf` / `.win`), the `meta` block, and
-- forwards `:new` / `:extend` to the Instance prototype so existing call sites
-- keep working unchanged. Lazy `__index` is safe here because instances do NOT
-- inherit from `M` — they inherit from `Instance`.
-- ============================================================================

---@class Beast.View
---@field buf Beast.View.Buf    -- buffer submodule (View.buf.new, View.buf.delete)
---@field win Beast.View.Win    -- window submodule (View.win.wo, View.win.find_normal)
---@field Instance Beast.View.Instance
---@field meta Beast.Lib.Meta
---@overload fun(buf: integer, win: integer): Beast.View.Instance
local M = {
	Instance = Instance,
}

---@type Beast.Lib.Meta
M.meta = { name = "view", description = "Window + buffer wrapper toolkit (`Beast.View`)" }

setmetatable(M --[[@as table]], {
	__call = function(_, ...)
		return Instance:new(...)
	end,
	__index = function(_, k)
		local ok, mod = pcall(require, "beast.libs.view." .. k)
		if ok then
			return mod
		end
	end,
})

-- Pass-throughs: keep `View:new(...)` and `View:extend(...)` working without
-- callers having to learn about `View.Instance`.

---@param buf integer
---@param win integer
---@return Beast.View.Instance
function M:new(buf, win)
	return Instance:new(buf, win)
end

---@generic T : Beast.View.Instance
---@param init? fun(obj: T, ...: any)
---@return T
function M:extend(init)
	return Instance:extend(init)
end

return M
