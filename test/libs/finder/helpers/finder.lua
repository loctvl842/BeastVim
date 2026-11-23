-- =========================================================================
-- Spec-side finder helpers (see docs/development/testing.md). The real work happens in the child
-- Nvim: `helpers/child/finder.lua` is loaded there as the global `FH`, and every function below is
-- a thin `n.exec_lua` call into it. Specs never touch windows or buffers themselves.
--
--   local t = require("test.testutil")
--   local h = require("test.helper")
--   local n = h.n
--   local F = require("test.libs.finder.helpers.finder")
--
--   t.describe("my finder spec", function()
--     t.before_each(F.setup)                       -- h.clear() + boot the child (wide screen, Toast recorder)
--     t.it("filters", function()
--       n.exec_lua(function() FH.list_source("zz", { "alpha.lua", "beta.lua" }) end)
--       F.open("zz")                               -- opens the real picker, waits until it settles
--       F.type("alp")                              -- writes the prompt, fires the debounce
--       t.eq(true, F.has_row("alpha.lua"))
--       F.press("<C-g>")                           -- runs the prompt's mapping callback
--       F.close()
--     end)
--   end)
--
-- API (all values are plain data, `nil`-free):
--   F.setup(opts?)              start a fresh child (`opts` as h.clear), install `FH`, return nothing
--   F.open(name, opts?)         `finder.open(name, opts)` then settle; `opts` must be serialisable
--   F.close()
--   F.press(lhs, opts?)         opts = { pane = "input"|"list"|"preview", mode = "i"|"n" }; returns
--                               true when a mapping callback was found and run
--   F.type(text, wait_ms?)      set the prompt to `text`, fire TextChangedI, wait (default 300ms)
--   F.settle(ms?)               let timers run in the child (default 150ms)
--   F.prompt() F.count() F.hint() F.title()   strings read from the picker ("" when absent)
--   F.rows()                    string[] of the list rows (trimmed, headers included)
--   F.has_row(needle)           plain-substring search over F.rows()
--   F.preview_text()            the preview pane's text
--   F.window_count()            how many picker windows are open (0 once closed)
--   F.toasts() / F.last_toast() what `Toast(...)` received since setup ("" when none)
--   F.tmpdir(files)             create a temp dir with `{ ["rel/path"] = "line" | { lines } }`, `cd` the
--                               child into it, return the (resolved) path
--   F.rmdir(dir)                delete such a dir
--
-- Inside `n.exec_lua(function() ... end)` bodies the child-side module is the global `FH` and offers the
-- same functions plus the ones that need functions as arguments:
--   FH.fake_source(name, spec)          register a source for `finder.open(name)`
--   FH.list_source(name, texts, extra?) a sync match source over `texts`
--   FH.panes()                          { input = {win, buf}, list = ..., preview = ..., backdrop = ... }
--   FH.wait(cond, ms?) / FH.settle(ms?) vim.wait helpers
-- Pass values into exec_lua as extra arguments; function bodies cannot capture upvalues, and a `nil`
-- in the middle of the argument list fails (pass one table instead). To wait for something in the child:
--   n.exec_lua(function() FH.wait(function() return FH.has_row("x") end, 2000) end)
-- Child state shared between exec_lua calls of one spec lives in globals (`_G.got = 0`).
--
-- Fixtures: `F.setup` makes the child's package.path absolute, so `require` still works after
-- `F.tmpdir` has `cd`-ed the child. Specs that need `gh`/`glab` use helpers/gh.lua and helpers/gl.lua,
-- called after `F.setup`. The helpers live in test/libs/finder/helpers/child/ for the child side.
-- =========================================================================
local h = require("test.helper")
local n = h.n

local CHILD = "test.libs.finder.helpers.child.finder"

local M = {}

---Start a fresh child Nvim and install the child-side finder helpers as `FH`.
---@param opts? { globals?: boolean }
function M.setup(opts)
	h.clear(opts)
	-- Absolute, so `require` keeps working after a spec `cd`s the child into a temp dir.
	n.exec_lua(function(mod, root)
		package.path = root .. "/?.lua;" .. package.path
		_G.FH = require(mod)
		_G.FH.boot()
	end, CHILD, vim.uv.cwd())
end

---Call `FH[name](...)` in the child.
---@param name string
---@param ... any
---@return any
local function call(name, ...)
	return n.exec_lua(function(fn, ...)
		return _G.FH[fn](...)
	end, name, ...)
end

---@param name string
---@param opts? table
function M.open(name, opts)
	call("open", name, opts)
end

function M.close()
	call("close")
end

---@param lhs string
---@param opts? { pane?: "input"|"list"|"preview", mode?: string }
---@return boolean found
function M.press(lhs, opts)
	return call("press", lhs, opts)
end

---@param text string
---@param wait_ms? integer
function M.type(text, wait_ms)
	call("type", text, wait_ms)
end

---@param ms? integer
function M.settle(ms)
	call("settle", ms)
end

---@return string
function M.prompt()
	return call("prompt")
end

---@return string
function M.count()
	return call("count")
end

---@return string
function M.hint()
	return call("hint")
end

---@return string
function M.title()
	return call("title")
end

---@return string[]
function M.rows()
	return call("rows")
end

---@param needle string
---@return boolean
function M.has_row(needle)
	return call("has_row", needle)
end

---@return string
function M.preview_text()
	return call("preview_text")
end

---@return integer
function M.window_count()
	return call("window_count")
end

---@return string[]
function M.toasts()
	return call("get_toasts")
end

---@return string
function M.last_toast()
	return call("last_toast")
end

---@param files table<string, string|string[]>
---@return string dir
function M.tmpdir(files)
	return call("tmpdir", files)
end

---@param dir string
function M.rmdir(dir)
	n.exec_lua(function(d)
		vim.fn.delete(d, "rf")
	end, dir)
end

return M
