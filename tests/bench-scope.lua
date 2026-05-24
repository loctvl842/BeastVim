-- =========================================================================
-- Benchmark: BeastVim indent scope vs treesitter scope
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/bench-scope.lua
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- ── Stubs ──────────────────────────────────────────────────────────────
_G.Palette = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
}
_G.Util = {
	colors = {
		set_hl = function() end,
	},
}

-- ── Load modules ───────────────────────────────────────────────────────
local scope = require("beast.libs.indent.scope")
local find_by_indent = scope.find_by_indent
local find_by_treesitter = scope.find_by_treesitter

-- ── Test content (Lua code — treesitter parser must be available) ──────

local lua_code = {
	"local M = {}",
	"",
	"function M.setup(opts)",
	"  local config = opts or {}",
	"  if config.enabled then",
	"    for i = 1, 10 do",
	"      print(i)",
	"    end",
	"  elseif config.fallback then",
	"    print('fallback')",
	"  else",
	"    print('disabled')",
	"  end",
	"  return config",
	"end",
	"",
	"function M.run(data)",
	"  local result = {}",
	"  for k, v in pairs(data) do",
	"    if type(v) == 'table' then",
	"      for _, item in ipairs(v) do",
	"        table.insert(result, item)",
	"      end",
	"    else",
	"      table.insert(result, v)",
	"    end",
	"  end",
	"  return result",
	"end",
	"",
	"function M.resolve(spec)",
	"  if M.detectors[spec] then",
	"    return M.detectors[spec]",
	"  elseif type(spec) == 'function' then",
	"    return spec",
	"  end",
	"  return function(buf)",
	"    return M.detectors.pattern(buf, spec)",
	"  end",
	"end",
	"",
	"return M",
}

-- Larger file: repeat pattern
local large_lua = {}
for i = 1, 20 do
	table.insert(large_lua, ("function module.handler_%d(request, response)"):format(i))
	table.insert(large_lua, "  if request.method == 'GET' then")
	table.insert(large_lua, "    local data = db.query(request.params)")
	table.insert(large_lua, "    if data then")
	table.insert(large_lua, "      for _, row in ipairs(data) do")
	table.insert(large_lua, "        if row.active then")
	table.insert(large_lua, "          table.insert(response.body, row)")
	table.insert(large_lua, "        end")
	table.insert(large_lua, "      end")
	table.insert(large_lua, "    else")
	table.insert(large_lua, "      response.status = 404")
	table.insert(large_lua, "    end")
	table.insert(large_lua, "  elseif request.method == 'POST' then")
	table.insert(large_lua, "    local ok, err = validate(request.body)")
	table.insert(large_lua, "    if ok then")
	table.insert(large_lua, "      db.insert(request.body)")
	table.insert(large_lua, "    end")
	table.insert(large_lua, "  end")
	table.insert(large_lua, "end")
	table.insert(large_lua, "")
end

-- ── Helpers ────────────────────────────────────────────────────────────

local function make_buf(lines, sw)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].shiftwidth = sw or 2
	vim.bo[buf].tabstop = sw or 2
	vim.bo[buf].expandtab = true
	vim.bo[buf].filetype = "lua"
	vim.api.nvim_set_current_buf(buf)
	return buf
end

---Try to start treesitter on a buffer. Returns true if parser available.
---@param buf integer
---@return boolean
local function start_treesitter(buf)
	local ok, parser = pcall(vim.treesitter.get_parser, buf, "lua")
	if ok and parser then
		parser:parse()
		return true
	end
	return false
end

local function hrtime_ms()
	return vim.uv.hrtime() / 1e6
end

-- ── Benchmark runner ───────────────────────────────────────────────────

local ITERATIONS = 5000
local WARMUP = 500

---@param label string
---@param find_fn fun(buf: integer, pos: table): any
---@param buf integer
---@param positions integer[]
---@return number elapsed_ms
local function bench_fn(label, find_fn, buf, positions)
	-- Warmup
	for _ = 1, WARMUP do
		for _, line in ipairs(positions) do
			find_fn(buf, { line, 0 })
		end
	end

	local start = hrtime_ms()
	for _ = 1, ITERATIONS do
		for _, line in ipairs(positions) do
			find_fn(buf, { line, 0 })
		end
	end
	local elapsed = hrtime_ms() - start
	local calls = ITERATIONS * #positions
	local per_call = elapsed / calls * 1000 -- µs

	print(("  %-12s: %7.2f ms total │ %6.3f µs/call"):format(label, elapsed, per_call))
	return elapsed
end

---@param label string
---@param lines string[]
---@param positions integer[]
---@param sw? integer
local function bench(label, lines, positions, sw)
	local buf = make_buf(lines, sw)
	local has_ts = start_treesitter(buf)

	print(("─── %s (%d lines, %d positions, %d iters, TS=%s) ───"):format(
		label, #lines, #positions, ITERATIONS, has_ts and "yes" or "NO"
	))

	local indent_ms = bench_fn("indent", find_by_indent, buf, positions)

	if has_ts then
		local ts_ms = bench_fn("treesitter", find_by_treesitter, buf, positions)
		local ratio = ts_ms / indent_ms
		if ratio > 1 then
			print(("  → Indent is %.1fx faster than treesitter"):format(ratio))
		else
			print(("  → Treesitter is %.1fx faster than indent"):format(1 / ratio))
		end
	else
		print("  → Treesitter: SKIPPED (no lua parser in --clean mode)")
	end
	print("")

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- ── Correctness comparison ─────────────────────────────────────────────

---@param label string
---@param lines string[]
---@param positions integer[]
---@param sw? integer
local function compare(label, lines, positions, sw)
	local buf = make_buf(lines, sw)
	local has_ts = start_treesitter(buf)

	print(("─── %s ───"):format(label))

	if not has_ts then
		print("  (treesitter not available, skipping comparison)")
		print("")
		vim.api.nvim_buf_delete(buf, { force = true })
		return
	end

	local diffs = 0
	for _, line in ipairs(positions) do
		local indent_result = find_by_indent(buf, { line, 0 })
		local ts_result = find_by_treesitter(buf, { line, 0 })

		local function fmt(scopes)
			if not scopes then return "nil" end
			local parts = {}
			for _, s in ipairs(scopes) do
				table.insert(parts, ("{%d→%d @%d}"):format(s.from, s.to, s.indent))
			end
			return table.concat(parts, ", ")
		end

		local i_str = fmt(indent_result)
		local t_str = fmt(ts_result)

		if i_str ~= t_str then
			diffs = diffs + 1
			print(("  Line %2d: indent=%-20s  ts=%s"):format(line, i_str, t_str))
		end
	end

	if diffs == 0 then
		print("  All positions return identical results")
	else
		print(("  %d differences (expected — different strategies find different scopes)"):format(diffs))
	end
	print("")

	vim.api.nvim_buf_delete(buf, { force = true })
end

-- ── Run ────────────────────────────────────────────────────────────────

print("╔══════════════════════════════════════════════════════════════════╗")
print("║          BeastVim: indent scope vs treesitter scope            ║")
print("╠══════════════════════════════════════════════════════════════════╣")
print(("║  Iterations: %d  │  Warmup: %d                              ║"):format(ITERATIONS, WARMUP))
print("╚══════════════════════════════════════════════════════════════════╝")
print("")

-- Positions across different code structures
local small_positions = { 1, 3, 5, 7, 9, 10, 14, 17, 20, 25, 32, 34, 37, 41 }
bench("Small file (if/elseif/else)", lua_code, small_positions)

local large_positions = { 1, 3, 6, 10, 13, 50, 100, 150, 200, 300, 390 }
bench("Large file (nested handlers)", large_lua, large_positions)

-- All lines
local all_small = {}
for i = 1, #lua_code do table.insert(all_small, i) end
bench("All lines (small)", lua_code, all_small)

print("═══ Correctness Comparison ═══")
print("(Shows where treesitter and indent give different results)")
print("")

compare("Small file — all lines", lua_code, all_small)

local sample_large = {}
for i = 1, #large_lua do table.insert(sample_large, i) end
compare("Large file — all lines", large_lua, sample_large)

-- ── Design comparison table ────────────────────────────────────────────
print("═══ Design Comparison ═══")
print("")
print("┌──────────────────────┬──────────────────────────┬──────────────────────────────┐")
print("│ Aspect               │ find_by_indent           │ find_by_treesitter           │")
print("├──────────────────────┼──────────────────────────┼──────────────────────────────┤")
print("│ Parser needed        │ No                       │ Yes (treesitter parser)      │")
print("│ Multi-segment        │ Always 1 segment         │ Splits at elseif/else        │")
print("│ Edge detection       │ Heuristic (neighbors)    │ Node boundary (exact)        │")
print("│ Blank line handling  │ MIN of neighbors         │ Inherits body indent         │")
print("│ Language-aware       │ No                       │ Yes (scope_types per lang)   │")
print("│ Fallback             │ Always works             │ Falls back to indent         │")
print("│ Cost per call        │ ~1-2 vim.fn calls        │ get_node + parent walk       │")
print("└──────────────────────┴──────────────────────────┴──────────────────────────────┘")
print("")

vim.cmd("qa!")
