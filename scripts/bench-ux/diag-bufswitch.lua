-- Diagnostic: load user config, open N buffers, switch them, dump per-event
-- autocmd counts and the top per-buffer growth contributors.
local cfg = vim.fn.stdpath("config") .. "/init.lua"
dofile(cfg)

local n_files = tonumber(os.getenv("DIAG_N") or "20")
local dir = vim.fn.stdpath("cache") .. "/bench-diag-bufs"
vim.fn.mkdir(dir, "p")
local files = {}
for i = 1, n_files do
	local p = string.format("%s/f_%03d.txt", dir, i)
	local f = assert(io.open(p, "w"))
	for j = 1, 200 do
		f:write(string.format("line %d of file %d\n", j, i))
	end
	f:close()
	files[#files + 1] = p
end

local function snapshot(label)
	local acs = vim.api.nvim_get_autocmds({})
	local by_event = {}
	for _, ac in ipairs(acs) do
		by_event[ac.event] = (by_event[ac.event] or 0) + 1
	end
	local by_group = {}
	for _, ac in ipairs(acs) do
		local g = ac.group_name or "<no-group>"
		by_group[g] = (by_group[g] or 0) + 1
	end
	return {
		label = label,
		total = #acs,
		bufs = #vim.api.nvim_list_bufs(),
		lua_ref = (vim.api.nvim__stats() or {}).lua_refcount or 0,
		by_event = by_event,
		by_group = by_group,
	}
end

local function diff(a, b)
	local function dmap(m1, m2)
		local out, keys = {}, {}
		for k in pairs(m1) do
			keys[k] = true
		end
		for k in pairs(m2) do
			keys[k] = true
		end
		for k in pairs(keys) do
			local d = (m2[k] or 0) - (m1[k] or 0)
			if d ~= 0 then
				out[#out + 1] = { k = k, d = d }
			end
		end
		table.sort(out, function(x, y)
			return x.d > y.d
		end)
		return out
	end
	return {
		total = b.total - a.total,
		bufs = b.bufs - a.bufs,
		lua_ref = b.lua_ref - a.lua_ref,
		by_event = dmap(a.by_event, b.by_event),
		by_group = dmap(a.by_group, b.by_group),
	}
end

-- Wait for lazy-loaders to settle.
vim.wait(2000)
local s0 = snapshot("after_init")

-- Open all buffers (without entering).
for _, f in ipairs(files) do
	vim.cmd("badd " .. vim.fn.fnameescape(f))
end
vim.cmd("buffer " .. vim.fn.fnameescape(files[1]))
vim.wait(500)
local s1 = snapshot("after_badd_and_first_buffer")

-- Cycle through every buffer twice — this is where bufswitch leaks pile up.
for _ = 1, 2 do
	for _, f in ipairs(files) do
		vim.cmd("buffer " .. vim.fn.fnameescape(f))
	end
end
vim.wait(500)
local s2 = snapshot("after_cycle")

-- Print everything.
local function p(...)
	print(string.format(...))
end
p("\n=== BENCH-DIAG (n_files=%d) ===", n_files)
for _, s in ipairs({ s0, s1, s2 }) do
	p("[%s] total_autocmds=%d bufs=%d lua_refcount=%d", s.label, s.total, s.bufs, s.lua_ref)
end

p("\n--- DELTA: after_init → after_badd+first_buffer ---")
local d1 = diff(s0, s1)
p("d_total=%d  d_bufs=%d  d_lua_refcount=%d", d1.total, d1.bufs, d1.lua_ref)
p("top events grown:")
for i = 1, math.min(8, #d1.by_event) do
	p("  +%-4d  %s", d1.by_event[i].d, d1.by_event[i].k)
end
p("top groups grown:")
for i = 1, math.min(10, #d1.by_group) do
	p("  +%-4d  %s", d1.by_group[i].d, d1.by_group[i].k)
end

p("\n--- DELTA: after_first_buffer → after_cycle (2x %d buffer switches) ---", n_files)
local d2 = diff(s1, s2)
p(
	"d_total=%d  d_lua_refcount=%d  per_switch_autocmds=%.2f per_switch_lua_ref=%.2f",
	d2.total,
	d2.lua_ref,
	d2.total / (2 * n_files),
	d2.lua_ref / (2 * n_files)
)
p("top events grown:")
for i = 1, math.min(8, #d2.by_event) do
	p("  +%-4d  %s", d2.by_event[i].d, d2.by_event[i].k)
end
p("top groups grown:")
for i = 1, math.min(15, #d2.by_group) do
	p("  +%-4d  %s", d2.by_group[i].d, d2.by_group[i].k)
end

vim.cmd("qa!")
