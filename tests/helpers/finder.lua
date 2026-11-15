-- =========================================================================
-- Shared harness for the finder tests: stubs, fake sources, and a black-box
-- way to open a real picker, press its keys and read what it shows.
--
-- Usage (from a test run as `nvim --clean --headless -l tests/test-x.lua`):
--   local H = dofile("tests/helpers/finder.lua")
--   local t = H.runner()          -- t.ok / t.eq / t.done()
--   H.open("fake", { ... })       -- opens the real picker, waits until it settles
--   H.press("<C-j>")              -- runs the prompt's mapping callback
--   H.rows()                      -- text of the list rows
-- Tests only use the public surface (`finder.open/close`, mappings, windows) so
-- they keep passing while the finder's internals are refactored.
-- =========================================================================
local H = {}

local booted = false

--- Make the repo requirable and stub the globals the finder expects. Safe to call twice.
function H.boot()
	-- stylua: ignore
	if booted then return end
	booted = true
	vim.opt.runtimepath:prepend(vim.fn.getcwd())
	package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
	_G.Util = require("beast.util")
	_G.View = require("beast.libs.view")
	_G.Theme = {
		get = function()
			return setmetatable({}, {
				__index = function()
					return "#222222"
				end,
			})
		end,
		refresh = function() end,
	}
	H.toasts = {}
	_G.Toast = function(msg)
		H.toasts[#H.toasts + 1] = msg
	end
	package.loaded["beast"] = { apply_highlights = function() end }
	package.loaded["beast.libs.finder.source.live_grep.engine.index"] = { setup = function() end }
end

H.boot()

---@return { ok: fun(name: string, cond: any, msg?: string), eq: fun(name: string, got: any, expected: any), done: fun() }
function H.runner()
	local passed, failed = 0, 0
	local t = {}
	function t.ok(name, cond, msg)
		if cond then
			passed = passed + 1
			io.write("  PASS: " .. name .. "\n")
		else
			failed = failed + 1
			io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
		end
	end
	function t.eq(name, got, expected)
		t.ok(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
	end
	function t.section(title)
		io.write("\n--- " .. title .. " ---\n")
	end
	function t.done()
		io.write(("\n%d passed, %d failed\n"):format(passed, failed))
		vim.cmd(failed == 0 and "qa!" or "cq!")
	end
	return t
end

--- Let timers and scheduled callbacks run.
---@param ms? integer
function H.settle(ms)
	vim.wait(ms or 150, function()
		return false
	end, 10)
end

--- Wait until `cond()` is truthy (true) or give up (false).
---@param cond fun(): any
---@param ms? integer
---@return boolean
function H.wait(cond, ms)
	return vim.wait(ms or 1000, cond, 10)
end

--- Register a source for `finder.open(name)` without touching the real registry files.
---@param name string
---@param spec table
---@return table
function H.fake_source(name, spec)
	package.loaded["beast.libs.finder.source." .. name] = spec
	return spec
end

--- A sync match-pipeline source over `texts` (each becomes `{ text = t, file = t }`).
---@param name string
---@param texts string[]
---@param extra? table
function H.list_source(name, texts, extra)
	return H.fake_source(
		name,
		vim.tbl_extend("force", {
			live = false,
			async = false,
			get = function()
				local items = {}
				for i, text in ipairs(texts) do
					items[i] = { idx = i, score = 0, text = text, file = text }
				end
				return items
			end,
		}, extra or {})
	)
end

local finder_mod ---@type table?
function H.finder()
	finder_mod = finder_mod or require("beast.libs.finder")
	return finder_mod
end

--- Open a real picker and wait for it to settle.
---@param name string
---@param opts? table
function H.open(name, opts)
	H.finder().open(name, opts)
	H.settle()
end

function H.close()
	H.finder().close()
end

---@class Beast.Test.Pane
---@field win integer
---@field buf integer

--- The picker's windows by role (`input`, `list`, `backdrop`, `preview`); missing roles are nil.
---@return table<string, Beast.Test.Pane>
function H.panes()
	local out = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local role = vim.bo[buf].filetype:match("^beast%-finder%-(%a+)$")
		if role then
			out[role] = { win = win, buf = buf }
		end
	end
	-- The preview buffer takes the filetype of what it shows, so find it as the remaining float.
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local known = false
		for _, pane in pairs(out) do
			known = known or pane.win == win
		end
		if not known and (vim.api.nvim_win_get_config(win).relative or "") ~= "" then
			local buf = vim.api.nvim_win_get_buf(win)
			if (vim.api.nvim_win_get_config(win).zindex or 50) >= 100 then
				out.preview = { win = win, buf = buf }
			end
		end
	end
	return out
end

--- How many windows of the picker are open (input, list, preview, backdrop).
---@return integer
function H.window_count()
	local n = 0
	for _ in pairs(H.panes()) do
		n = n + 1
	end
	return n
end

--- Run a pane's mapping callback (what pressing `lhs` there does).
---@param lhs string
---@param opts? { pane?: "input"|"list"|"preview", mode?: string }
---@return boolean found
function H.press(lhs, opts)
	opts = opts or {}
	local pane = H.panes()[opts.pane or "input"]
	-- stylua: ignore
	if not pane then return false end
	local mode = opts.mode or (opts.pane == "list" or opts.pane == "preview") and "n" or "i"
	-- Focus the pane (not nvim_buf_call, which would undo a focus change made by the mapping).
	vim.api.nvim_set_current_win(pane.win)
	local map = vim.fn.maparg(lhs, mode, false, true)
	if map and map.callback then
		map.callback()
	end
	H.settle(60)
	return map ~= nil and map.callback ~= nil
end

--- Write `text` into the prompt the way typing does, then wait for the debounce.
---@param text string
---@param wait_ms? integer
function H.type(text, wait_ms)
	local input = H.panes().input
	-- stylua: ignore
	if not input then return end
	local prefix = require("beast.libs.finder.config").prompt_prefix
	vim.api.nvim_buf_set_lines(input.buf, 0, 1, false, { prefix .. text })
	vim.api.nvim_buf_call(input.buf, function()
		vim.api.nvim_exec_autocmds("TextChangedI", { buffer = input.buf })
	end)
	H.settle(wait_ms or 300)
end

--- The prompt text without its prefix.
---@return string
function H.prompt()
	local input = H.panes().input
	-- stylua: ignore
	if not input then return "" end
	local line = vim.api.nvim_buf_get_lines(input.buf, 0, 1, false)[1] or ""
	local prefix = require("beast.libs.finder.config").prompt_prefix
	return line:sub(1, #prefix) == prefix and line:sub(#prefix + 1) or line
end

--- Text of the list rows as drawn (headers included), trimmed.
---@return string[]
function H.rows()
	local list = H.panes().list
	-- stylua: ignore
	if not list then return {} end
	return vim.tbl_map(function(line)
		return vim.trim(line)
	end, vim.api.nvim_buf_get_lines(list.buf, 0, -1, false))
end

--- True when some drawn row contains `needle`.
---@param needle string
---@return boolean
function H.has_row(needle)
	for _, row in ipairs(H.rows()) do
		if row:find(needle, 1, true) then
			return true
		end
	end
	return false
end

--- The window the tests run in (the picker returns focus here when it closes).
---@return integer
function H.main_win()
	return require("beast.libs.view").win.find_normal() or vim.api.nvim_get_current_win()
end

--- Replace `tbl[key]` with a spy that records its arguments; returns the call log and a restore function.
---@param tbl table
---@param key string
---@return table[] calls, fun() restore
function H.spy(tbl, key)
	local calls = {}
	local orig = tbl[key]
	tbl[key] = function(...)
		calls[#calls + 1] = { ... }
	end
	return calls, function()
		tbl[key] = orig
	end
end

return H
