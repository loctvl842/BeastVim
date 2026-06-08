--- Lightweight profiler for BeastVim libs and plugins.
---
--- Inspired by github.com/stevearc/profile.nvim, but adapted for our needs:
---   - Outputs plain text (not Chrome trace JSON) so AI agents can analyse it.
---   - Aggregates per-function stats (count/total/self/min/max) instead of
---     storing every event — keeps memory bounded for unattended runs.
---   - Tracks self-time via a nesting stack, so callers don't double-count
---     time spent in instrumented children (same idea as Vim's `--startuptime`
---     `self+sourced` vs `self` columns).
---
--- Usage:
---
---     local profile = require("beast.profile")
---     profile.start()                          -- defaults: beast.libs.*, beast.plugins.*
---     -- ... do stuff ...
---     print(profile.report())                  -- text report
---     profile.save("/tmp/beast-profile.txt")
---
--- For headless health checks, set BEAST_PROFILE=1 before launching nvim.
--- init.lua picks it up and wires `auto_dump_on_quit` so the report is
--- written automatically on VimLeavePre.

local uv = vim.uv or vim.loop
local hrtime = uv.hrtime

-- LuaJIT 2.1 (Lua 5.1 base) lacks table.pack / table.unpack — use `select`
-- + the global `unpack` so we can preserve multi-return values, including
-- intentional nils, without calling the wrapped function twice.
---@diagnostic disable-next-line: deprecated
local _unpack = table.unpack or unpack

local function pack_varargs(...)
	return select("#", ...), { ... }
end

---@return number microseconds
local function clock()
	return hrtime() / 1e3
end

---@class Beast.Profile.Stat
---@field calls integer
---@field total number   total microseconds (incl. children)
---@field self  number   self microseconds (excl. instrumented children)
---@field min   number
---@field max   number

---@class Beast.Profile.State
---@field recording boolean
---@field patterns string[]
---@field ignore   string[]
---@field stats    table<string, Beast.Profile.Stat>   function-call stats
---@field require_stats table<string, Beast.Profile.Stat>   per-module require stats
---@field stack    table[]   call stack for self-time tracking
---@field wrapped_modules   table<string, boolean>
---@field wrapped_functions table<string, function>
---@field rawrequire function?
---@field start_time number   microseconds at last start()

---@type Beast.Profile.State
local state = {
	recording = false,
	patterns = {},
	ignore = {},
	stats = {},
	require_stats = {},
	stack = {},
	wrapped_modules = {},
	wrapped_functions = {},
	rawrequire = nil,
	start_time = 0,
}

local DEFAULT_PATTERNS = { "^beast%.libs%.", "^beast%.plugins%." }
local DEFAULT_IGNORE = { "^beast%.profile" }

local M = {}

-- ============================================================
-- Pattern matching
-- ============================================================

local function should_profile(name)
	for _, pat in ipairs(state.ignore) do
		if name:match(pat) then
			return false
		end
	end
	for _, pat in ipairs(state.patterns) do
		if name:match(pat) then
			return true
		end
	end
	return false
end

-- ============================================================
-- Stat recording
-- ============================================================

local function record(target, name, total, self_t)
	local s = target[name]
	if not s then
		s = { calls = 0, total = 0, self = 0, min = math.huge, max = 0 }
		target[name] = s
	end
	s.calls = s.calls + 1
	s.total = s.total + total
	s.self = s.self + self_t
	if total < s.min then
		s.min = total
	end
	if total > s.max then
		s.max = total
	end
end

-- ============================================================
-- Function wrapping
-- ============================================================

--- Wrap `fn` so each call records timing into `target_stats[name]`.
--- Preserves multi-return values, propagates errors, keeps the call stack
--- consistent even when `fn` raises.
local function wrap_function(name, fn, target_stats)
	return function(...)
		if not state.recording then
			return fn(...)
		end

		local start = clock()
		local frame = { child_total = 0 }
		state.stack[#state.stack + 1] = frame

		local n, results = pack_varargs(pcall(fn, ...))

		local total = clock() - start
		state.stack[#state.stack] = nil
		local parent = state.stack[#state.stack]
		if parent then
			parent.child_total = parent.child_total + total
		end

		record(target_stats, name, total, total - frame.child_total)

		if not results[1] then
			error(results[2], 0)
		end
		return _unpack(results, 2, n)
	end
end

local function wrap_module(name, mod)
    -- stylua: ignore
    if type(mod) ~= "table" or state.wrapped_modules[name] then return end
	state.wrapped_modules[name] = true
	for k, v in pairs(mod) do
		if type(k) == "string" and type(v) == "function" and not k:find("^_") then
			local fn_name = name .. "." .. k
			if not state.wrapped_functions[fn_name] then
				state.wrapped_functions[fn_name] = v
				mod[k] = wrap_function(fn_name, v, state.stats)
			end
		end
	end
end

-- ============================================================
-- require() hook
-- ============================================================

local function hooked_require(name)
	-- Skip if already loaded or not in our scope; still call rawrequire.
	if package.loaded[name] or not should_profile(name) then
		return state.rawrequire(name)
	end

	local start = clock()
	local frame = { child_total = 0 }
	state.stack[#state.stack + 1] = frame

	local ok, mod = pcall(state.rawrequire, name)

	local total = clock() - start
	state.stack[#state.stack] = nil
	local parent = state.stack[#state.stack]
	if parent then
		parent.child_total = parent.child_total + total
	end

	record(state.require_stats, name, total, total - frame.child_total)

	if not ok then
		error(mod, 0)
	end
	if type(mod) == "table" then
		wrap_module(name, mod)
	end
	return mod
end

local function install_require_hook()
	if state.rawrequire then
		return
	end
	state.rawrequire = require
	_G.require = hooked_require
end

-- ============================================================
-- Public API
-- ============================================================

---@class Beast.Profile.Options
---@field patterns? string[]   Lua patterns of modules to instrument
---@field ignore?   string[]   Lua patterns to skip even if they match `patterns`

---@param opts? Beast.Profile.Options
function M.start(opts)
	opts = opts or {}
	state.patterns = opts.patterns or DEFAULT_PATTERNS
	state.ignore = opts.ignore or DEFAULT_IGNORE
	state.stats = {}
	state.require_stats = {}
	state.stack = {}
	state.start_time = clock()
	state.recording = true

	install_require_hook()

	-- Wrap any matching modules already loaded.
	for name, mod in pairs(package.loaded) do
		if should_profile(name) then
			wrap_module(name, mod)
		end
	end
end

function M.stop()
	state.recording = false
end

function M.is_recording()
	return state.recording
end

function M.reset()
	state.stats = {}
	state.require_stats = {}
	state.stack = {}
	state.start_time = clock()
end

-- ============================================================
-- Reporting
-- ============================================================

local function sorted_by_self(stats)
	local list = {}
	for name, s in pairs(stats) do
		list[#list + 1] = {
			name = name,
			calls = s.calls,
			total = s.total,
			self = s.self,
			mean = s.total / s.calls,
			min = s.min,
			max = s.max,
		}
	end
	table.sort(list, function(a, b)
		return a.self > b.self
	end)
	return list
end

local HEADER = "%-50s %6s %12s %12s %12s %12s\n"
local ROW = "%-50s %6d %12.3f %12.3f %12.1f %12.1f\n"

local function format_section(title, stats)
	local out = {}
	out[#out + 1] = "## " .. title .. "\n"
	out[#out + 1] = "# Times in milliseconds (TOTAL/SELF) and microseconds (MEAN/MAX). Sorted by self time.\n"
	out[#out + 1] = string.format(HEADER, "NAME", "CALLS", "TOTAL_MS", "SELF_MS", "MEAN_US", "MAX_US")
	local rows = sorted_by_self(stats)
	if #rows == 0 then
		out[#out + 1] = "(no entries)\n"
	end
	for _, r in ipairs(rows) do
		local name = r.name
		if #name > 50 then
			name = name:sub(1, 47) .. "..."
		end
		out[#out + 1] = string.format(ROW, name, r.calls, r.total / 1000, r.self / 1000, r.mean, r.max)
	end
	return table.concat(out)
end

---@return string text report
function M.report()
	local out = {}
	out[#out + 1] = "# BeastVim Profile Report\n"
	out[#out + 1] = string.format("# Generated:        %s\n", os.date("%Y-%m-%dT%H:%M:%S"))
	out[#out + 1] = string.format("# Neovim:           %s\n", tostring(vim.version()))
	out[#out + 1] = string.format("# Recording uptime: %.3f ms\n", (clock() - state.start_time) / 1000)
	out[#out + 1] = string.format("# Recording state:  %s\n", state.recording and "active" or "stopped")
	out[#out + 1] = string.format("# Patterns:         %s\n", table.concat(state.patterns, ", "))
	out[#out + 1] = "\n"
	out[#out + 1] = format_section("Module require times", state.require_stats)
	out[#out + 1] = "\n"
	out[#out + 1] = format_section("Function call times", state.stats)
	return table.concat(out)
end

---@param path string
---@return string path
function M.save(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	local f = assert(io.open(path, "w"))
	f:write(M.report())
	f:close()
	return path
end

--- Register a VimLeavePre autocmd that dumps the report to `path`.
--- Used by init.lua when BEAST_PROFILE=1.
---@param path string
function M.auto_dump_on_quit(path)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		group = vim.api.nvim_create_augroup("BeastProfile", { clear = true }),
		callback = function()
			pcall(M.save, path)
		end,
	})
end

return M
