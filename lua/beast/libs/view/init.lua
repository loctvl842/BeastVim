---@class Beast.View
---@field buf integer|false   -- buffer handle; `false` once :close() has run
---@field win integer|false   -- window handle; `false` once :close() has run

---@class Beast.View.Module
---@field buf Beast.View.Buf  -- buffer submodule (View.buf.new, View.buf.delete)
---@field win Beast.View.Win  -- window submodule (View.win.wo, View.win.find_normal)
---@field meta Beast.Lib.Meta
---@overload fun(buf: integer, win: integer): Beast.View  -- View(buf, win) constructor
local M = {}
M.__index = M

-- TODO(view-types): `M` currently plays three roles — module table, instance
-- metatable (instances have `__index = M` so they inherit `:is_valid`/`:close`),
-- AND lazy submodule namespace (via the metatable below for `.buf` / `.win`).
-- LuaLS cannot express all three with one class, which forces the
-- `--[[@as table]]` / `--[[@as Beast.View]]` casts you see below and in
-- `M:extend().new`. The clean fix is to split the instance class off from the
-- module table:
--   * `Beast.View`         — instance only (`buf`, `win`, `:is_valid`, `:close`)
--   * `Beast.View.Module`  — module only (`.buf`, `.win`, `.new`, `.extend`,
--                            callable via __overload)
-- Give instances their own metatable (not `M`) so the inheritance chain is
-- typed, and re-export the class-bound methods on `Beast.View` directly.
-- Touches every `View:extend(...)` call site's inferred return type, so it's
-- worth a small dev spec rather than a drive-by edit.

-- Namespace metatable: lets callers do `Beast.View.buf` / `Beast.View.win` to
-- get the submodules lazily. Attached to M itself, NOT to its instance __index
-- chain, so `instance.buf` returns nil (not the submodule) when unset.
setmetatable(M --[[@as table]], {
	__call = function(t, ...)
		return t:new(...)
	end,
	__index = function(_, k)
		local ok, mod = pcall(require, "beast.libs.view." .. k)
		if ok then
			return mod
		end
	end,
})

---@type Beast.Lib.Meta
M.meta = { name = "view", description = "Window + buffer wrapper toolkit (`Beast.View`)" }

---@param buf integer
---@param win integer
---@return Beast.View
function M:new(buf, win)
	-- Store `false` rather than `nil` for missing buf/win so subsequent reads
	-- of `instance.buf`/`.win` do NOT cascade through the namespace metatable
	-- to the buf/win submodules (which would return tables instead of falsy).
	local obj = { buf = buf or false, win = win or false }
	return setmetatable(obj, { __index = M }) --[[@as Beast.View]]
end

---@param self Beast.View
---@return boolean
function M:is_valid()
	local buf = rawget(self, "buf")
	local win = rawget(self, "win")
	if not buf or not win then
		return false
	end
	return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)
end

---@param self Beast.View
function M:close()
	local win = rawget(self, "win")
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	-- Use `false` (not `nil`) so subsequent reads of `instance.buf`/`.win` do
	-- NOT cascade through the namespace metatable to the buf/win submodules.
	self.buf = false
	self.win = false
end

--- Create a subclass of Beast.View. `init(obj, ...)` runs after construction
--- so callers can attach extra state (namespace ids, records, etc.) to each
--- subclass instance. The returned table is itself callable (`Sub(buf, win, …)`).
---@param init? fun(obj: Beast.View, ...: any)
---@return Beast.View.Module
function M:extend(init)
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
		}, { __index = cls }) --[[@as Beast.View]]

		if init then
			init(obj, ...)
		end

		return obj
	end

	return cls
end

return M
