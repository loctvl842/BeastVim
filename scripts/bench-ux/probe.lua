-- scripts/bench-ux/probe.lua — shared instrumentation for bench-ux.sh.
--
-- Loaded by every scenario's init.lua. Writes one event per line to
-- $BENCH_LOG. Line shapes:
--
--   paint <ms>
--       Time from the most recent key entering Neovim to the end of the
--       next redraw cycle. This is the closest proxy for "input → screen
--       updated" we can measure inside Neovim (see docs/neovim/latency-
--       research.md §3 — on_end runs after the redraw pass).
--
--   snap tag=<t> bufs=<n> autocmds=<n> extmarks=<n> lua_kb=<f> \
--        redraw=<n> lua_refcount=<n> ts_q=<n> arena=<n> rss_kb=<n> uptime_s=<n>
--       Growth indicators for long-session bench (see research §10).
--
--   evt <name> <hrtime_ms>
--       Free-form marker the scenario can drop with :BenchMark <name>.
--
-- User commands exposed:
--   :BenchSnap [tag]   — write a snap line
--   :BenchMark <name>  — write an evt line
--   :BenchQuit         — flush log and quit Neovim

local logpath = assert(os.getenv("BENCH_LOG"), "BENCH_LOG not set")
local log = assert(io.open(logpath, "a"))
local function w(line)
	log:write(line)
	log:flush()
end
_G.bench_log = w

local start_hrtime = vim.uv.hrtime()
w(string.format("# pid=%d nvim=%s started=%d\n", vim.fn.getpid(), tostring(vim.version()):gsub("[\r\n]+", " "), os.time()))

-- ── key-to-paint latency ────────────────────────────────────────────────
-- vim.on_key fires for every key entering Neovim, BEFORE mappings expand,
-- which is exactly the moment a user "perceives" their key was sent. We
-- timestamp it, then close the loop when the next redraw finishes via the
-- decoration provider's on_end hook (the last thing called per redraw
-- cycle — see src/nvim/decoration_provider.c).
local last_key_t = nil

vim.on_key(function(key)
	if key and #key > 0 then
		last_key_t = vim.uv.hrtime()
	end
end)

local probe_ns = vim.api.nvim_create_namespace("bench_paint_probe")
vim.api.nvim_set_decoration_provider(probe_ns, {
	on_end = function()
		if last_key_t then
			local dt = (vim.uv.hrtime() - last_key_t) / 1e6
			-- Discard absurd values (e.g. provider fired without a real redraw).
			if dt >= 0 and dt < 5000 then
				w(string.format("paint %.3f\n", dt))
			end
			last_key_t = nil
		end
	end,
})

-- ── growth snapshot ─────────────────────────────────────────────────────
local function read_rss_kb()
	-- Read RSS via /proc on Linux, ps on macOS. Best effort.
	local pid = vim.fn.getpid()
	local f = io.open("/proc/" .. pid .. "/status")
	if f then
		for line in f:lines() do
			local kb = line:match("^VmRSS:%s+(%d+)")
			if kb then
				f:close()
				return tonumber(kb)
			end
		end
		f:close()
	end
	local p = io.popen("ps -o rss= -p " .. pid .. " 2>/dev/null")
	if p then
		local s = p:read("*a")
		p:close()
		local kb = tonumber((s or ""):match("(%d+)"))
		if kb then
			return kb
		end
	end
	return 0
end

function _G.bench_snapshot(tag)
	collectgarbage("collect")
	local stats = vim.api.nvim__stats() or {}
	local total_extmarks = 0
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, buf, -1, 0, -1, {})
			if ok then
				total_extmarks = total_extmarks + #marks
			end
		end
	end
	local uptime_s = (vim.uv.hrtime() - start_hrtime) / 1e9
	w(
		string.format(
			"snap tag=%s t=%d bufs=%d autocmds=%d extmarks=%d lua_kb=%.1f " .. "redraw=%d lua_refcount=%d ts_q=%d arena=%d rss_kb=%d uptime_s=%.1f\n",
			tag or "anon",
			os.time(),
			#vim.api.nvim_list_bufs(),
			#vim.api.nvim_get_autocmds({}),
			total_extmarks,
			collectgarbage("count"),
			stats.redraw or 0,
			stats.lua_refcount or 0,
			stats.ts_query_parse_count or 0,
			stats.arena_alloc_count or 0,
			read_rss_kb(),
			uptime_s
		)
	)
end

function _G.bench_mark(name)
	w(string.format("evt %s %.3f\n", name, (vim.uv.hrtime() - start_hrtime) / 1e6))
end

vim.api.nvim_create_user_command("BenchSnap", function(o)
	_G.bench_snapshot(o.args ~= "" and o.args or "manual")
end, { nargs = "?" })

vim.api.nvim_create_user_command("BenchMark", function(o)
	_G.bench_mark(o.args)
end, { nargs = 1 })

vim.api.nvim_create_user_command("BenchQuit", function()
	_G.bench_snapshot("final")
	log:close()
	vim.cmd("qa!")
end, {})

-- Initial snapshot so summarise.py has a baseline.
vim.defer_fn(function()
	_G.bench_snapshot("start")
end, 100)
