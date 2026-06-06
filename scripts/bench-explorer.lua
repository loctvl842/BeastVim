-- =========================================================================
-- Bench: Beast explorer render time
-- =========================================================================
-- Headless benchmark for `lua/beast/libs/explorer`.
--
-- Conforms to the bench contract documented in
-- `docs/tec-config/health-config.md` § "Run-time Render Performance":
--   * Run as: nvim --clean --headless -l scripts/bench-explorer.lua
--   * Final stdout line begins with `BENCH ` and includes name=explorer,
--     primary metric, and threshold.
--   * Exit code: 0 PASS, 1 FAIL (threshold), 2 setup error.
-- =========================================================================

local FAIL_THRESHOLD_US = 2000 -- 2 ms full render (mixed scenario)
local WARN_THRESHOLD_US = 500 -- soft target
local ITERS_PER_RUN = 200
local RUNS = 3

-- =========================================================================
-- Setup
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Stub globals that the explorer modules expect
_G.Palette = {
	get = function()
		return setmetatable({}, {
			__index = function()
				return "#ffffff"
			end,
		})
	end,
	refresh = function() end,
}

_G.Util = require("beast.util")

_G.Toast = function() end

-- Stub nvim-web-devicons — in real BeastVim this is always loaded by packer.
-- Without it, config.file_icon would fall back to cfg.icon.file (fast path),
-- but providing a stub exercises the get_icon code path that runs in production.
package.loaded["nvim-web-devicons"] = {
	get_icon = function(_, _, _)
		return "󰈙", "DevIconDefault"
	end,
}

-- View.buf.new — scratch buffer factory
_G.View = {
	buf = {
		new = function(filetype)
			local buf = vim.api.nvim_create_buf(false, true)
			vim.bo[buf].buftype = "nofile"
			vim.bo[buf].bufhidden = "wipe"
			vim.bo[buf].swapfile = false
			vim.bo[buf].filetype = filetype
			return buf
		end,
	},
	win = {
		wo = function(win, k, v)
			vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
		end,
		find_normal = function()
			return vim.api.nvim_get_current_win()
		end,
	},
}

-- =========================================================================
-- Scenario: tmp folder generation
-- =========================================================================

local tmpdirs = {} -- track for cleanup

---@param base string  Parent directory
---@param name string  File or dir name
local function touch_file(base, name)
	vim.fn.writefile({}, base .. "/" .. name)
end

--- Create a scenario tmp directory and return its path.
---@param name string  Scenario name (for error messages)
---@param builder fun(root: string)  Populates the directory
---@return string root  Absolute path to the scenario root
local function make_scenario(name, builder)
	local root = vim.fn.tempname() .. "_bench_explorer_" .. name
	local ok = vim.fn.mkdir(root, "p")
	if ok ~= 1 then
		io.stderr:write("BENCH ERROR: could not create tmp dir for scenario '" .. name .. "'\n")
		os.exit(2)
	end
	tmpdirs[#tmpdirs + 1] = root
	builder(root)
	return root
end

--- Cleanup all tmp dirs at exit.
local function cleanup()
	for _, d in ipairs(tmpdirs) do
		vim.fn.delete(d, "rf")
	end
end

-- Scenario builders

local function build_wide(root)
	for i = 1, 10 do
		vim.fn.mkdir(root .. "/dir_" .. string.format("%02d", i), "p")
	end
	for i = 1, 100 do
		touch_file(root, "file_" .. string.format("%03d", i) .. ".lua")
	end
end

local function build_deep(root)
	local path = root
	for level = 1, 8 do
		for j = 1, 3 do
			if j == 1 then
				-- first child is a directory for next level
				path = path .. "/level_" .. level
				vim.fn.mkdir(path, "p")
			else
				touch_file(path, "sibling_" .. j .. ".lua")
			end
		end
	end
end

local function build_hidden(root)
	for i = 1, 50 do
		touch_file(root, ".hidden_" .. string.format("%03d", i))
	end
	for i = 1, 50 do
		touch_file(root, "visible_" .. string.format("%03d", i) .. ".lua")
	end
end

local function build_mixed(root)
	-- 4 levels, variable breadth, ~200 nodes total
	local count = 0
	local function populate(dir, depth)
		if depth > 4 or count > 220 then
			return
		end
		local breadth = 5 + (depth * 3) -- 8, 11, 14, 17 entries per level
		local dirs_to_make = math.floor(breadth * 0.3)
		for i = 1, dirs_to_make do
			if count > 220 then
				break
			end
			local subdir = dir .. "/pkg_" .. string.format("%02d", i)
			vim.fn.mkdir(subdir, "p")
			count = count + 1
			populate(subdir, depth + 1)
		end
		for i = 1, breadth - dirs_to_make do
			if count > 220 then
				break
			end
			local prefix = (i % 5 == 0) and "." or ""
			touch_file(dir, prefix .. "module_" .. string.format("%02d", i) .. ".lua")
			count = count + 1
		end
	end
	populate(root, 1)
end

-- =========================================================================
-- Explorer wiring
-- =========================================================================

local Tree = require("beast.libs.explorer.tree")
local View = require("beast.libs.view")
local config = require("beast.libs.explorer.config")
local render = require("beast.libs.explorer.render")
local state = require("beast.libs.explorer.state")
local sticky_mod = require("beast.libs.explorer.sticky")

---@class Beast.Explorer.BenchView : Beast.View
---@field ns integer
local BenchView = View:extend(function(obj, ns)
	obj.ns = ns
end)

--- Set up the explorer state for a given scenario root.
---@param root string
---@return integer node_count
local function setup_explorer(root)
	local ns = vim.api.nvim_create_namespace("bench_explorer")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "beast-explorer"

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	state.tree = Tree:new(root)
	state.view = BenchView(buf, win, ns)

	-- Expand the full tree (pre-warm)
	local function expand_all(node)
		if node.dir then
			state.tree:expand(node)
			for _, child_path in pairs(node.children) do
				local child = state.tree.nodes[child_path]
				if child and child.dir then
					child.open = true
					expand_all(child)
				end
			end
		end
	end
	expand_all(state.tree.root)

	local nodes = state.tree:flat({ show_hidden = config.show_hidden })
	return #nodes
end

-- =========================================================================
-- Bench helpers
-- =========================================================================

local function mean(xs)
	local s = 0
	for _, v in ipairs(xs) do
		s = s + v
	end
	return s / #xs
end

---@param fn fun()
---@return number  µs per call (mean across RUNS)
local function bench(fn)
	local samples = {}
	for _ = 1, RUNS do
		collectgarbage("collect")
		local t0 = vim.uv.hrtime()
		for _ = 1, ITERS_PER_RUN do
			fn()
		end
		local elapsed_ns = vim.uv.hrtime() - t0
		samples[#samples + 1] = elapsed_ns / 1e3 / ITERS_PER_RUN
	end
	return mean(samples)
end

-- =========================================================================
-- Run scenarios
-- =========================================================================

local results = {} -- scenario_name -> full_render_us

local scenarios = {
	{ name = "wide", builder = build_wide },
	{ name = "deep", builder = build_deep },
	{ name = "hidden", builder = build_hidden },
	{ name = "mixed", builder = build_mixed },
}

local mixed_details = {} -- sub-metric breakdown for mixed

for _, scenario in ipairs(scenarios) do
	local root = make_scenario(scenario.name, scenario.builder)

	local ok, err = pcall(function()
		local node_count = setup_explorer(root)

		-- Position cursor in middle for realistic sticky computation
		local mid = math.max(2, math.floor(node_count / 2))
		pcall(vim.api.nvim_win_set_cursor, state.view.win, { mid, 0 })

		-- Full render bench
		local full_us = bench(function()
			-- Invalidate flat cache to simulate tree mutation on each render
			state.tree:_touch()
			local nodes = state.tree:flat({ show_hidden = config.show_hidden })
			local lines, hls = render.build(nodes)
			render.write(lines, hls)
			-- sticky.refresh() requires window scroll state; include it
			pcall(sticky_mod.refresh)
		end)

		results[scenario.name] = full_us
		print(string.format("%-8s %7.2f µs/render  (%d nodes, %d×%d)", scenario.name, full_us, node_count, RUNS, ITERS_PER_RUN))

		-- Sub-metrics only for mixed
		if scenario.name == "mixed" then
			mixed_details.nodes = node_count

			-- flat cache-miss
			mixed_details.flat_miss = bench(function()
				state.tree:_touch()
				state.tree:flat({ show_hidden = config.show_hidden })
			end)

			-- flat cache-hit
			state.tree:_touch()
			state.tree:flat({ show_hidden = config.show_hidden }) -- warm the cache
			mixed_details.flat_hit = bench(function()
				state.tree:flat({ show_hidden = config.show_hidden })
			end)

			-- build
			local nodes = state.tree:flat({ show_hidden = config.show_hidden })
			mixed_details.build = bench(function()
				render.build(nodes)
			end)

			-- write
			local lines, hls = render.build(nodes)
			mixed_details.write = bench(function()
				render.write(lines, hls)
			end)

			print(
				string.format(
					"  breakdown: flat_miss=%.2fus flat_hit=%.2fus build=%.2fus write=%.2fus",
					mixed_details.flat_miss,
					mixed_details.flat_hit,
					mixed_details.build,
					mixed_details.write
				)
			)
		end
	end)

	if not ok then
		io.stderr:write("BENCH ERROR in scenario '" .. scenario.name .. "': " .. tostring(err) .. "\n")
		cleanup()
		os.exit(2)
	end
end

-- =========================================================================
-- Summary + exit code
-- =========================================================================

local primary_us = results["mixed"]
if not primary_us then
	io.stderr:write("BENCH ERROR: mixed scenario did not produce a result\n")
	cleanup()
	os.exit(2)
end

print(
	string.format(
		"BENCH name=explorer full_render=%.2fus nodes=%d scenario=mixed threshold=%dus",
		primary_us,
		mixed_details.nodes or 0,
		FAIL_THRESHOLD_US
	)
)

cleanup()

if primary_us > FAIL_THRESHOLD_US then
	io.stderr:write(string.format("FAIL: %.2f µs > %d µs threshold\n", primary_us, FAIL_THRESHOLD_US))
	os.exit(1)
end

if primary_us > WARN_THRESHOLD_US then
	io.stderr:write(string.format("WARN: %.2f µs > %d µs soft target (investigate)\n", primary_us, WARN_THRESHOLD_US))
end

os.exit(0)
