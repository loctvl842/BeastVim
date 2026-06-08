local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.key")

	-- Check module loaded
	local key_mod = package.loaded["beast.libs.key"]
	if not key_mod then
		health.warn("Key module not loaded (require('beast.libs.key').setup() not called)")
		return
	end
	health.ok("Key module loaded")

	-- Core: safe_set works (set and immediately clean up a test keymap)
	local ok_core, core = pcall(require, "beast.libs.key.core")
	if not ok_core then
		health.error("Failed to load core: " .. tostring(core))
		return
	end

	local test_lhs = "<Plug>(beast-key-health-test)"
	local ok_set, set_err = pcall(core.safe_set, "n", test_lhs, function() end, { desc = "health check" })
	if ok_set then
		health.ok("safe_set() works")
		pcall(vim.keymap.del, "n", test_lhs)
		local test_id = vim.api.nvim_replace_termcodes(test_lhs, true, true, true) .. " (n)"
		core.managed[test_id] = nil
		core.forget_conflict(test_id)
	else
		health.error("safe_set() failed: " .. tostring(set_err))
	end

	-- API: default() returns content lines
	local ok_api, api_mod = pcall(require, "beast.libs.key.api")
	if not ok_api then
		health.error("Failed to load api: " .. tostring(api_mod))
		return
	end

	local ok_default, lines = pcall(api_mod.default)
	if ok_default and type(lines) == "table" then
		health.ok(string.format("api.default() returns %d lines", #lines))
	else
		health.error("api.default() failed: " .. tostring(lines))
	end

	-- API: cycle_mode works
	local ok_cycle, cycle_err = pcall(api_mod.cycle_mode)
	if ok_cycle then
		health.ok("api.cycle_mode() works")
	else
		health.error("api.cycle_mode() failed: " .. tostring(cycle_err))
	end

	-- API: toggle_beast_only works
	local ok_toggle, toggle_err = pcall(api_mod.toggle_beast_only)
	if ok_toggle then
		health.ok("api.toggle_beast_only() works")
	else
		health.error("api.toggle_beast_only() failed: " .. tostring(toggle_err))
	end

	-- Reset filters back to defaults
	pcall(api_mod.toggle_beast_only)
	pcall(api_mod.cycle_mode)

	-- =========================================================================
	-- Duplication: set-time history of (mode, lhs) registrations
	--
	-- `core.conflicts[id]` records every call to `set()` for global keymaps,
	-- so we can surface overwrites that `nvim_get_keymap` cannot show (the
	-- later `vim.keymap.set` silently replaces the earlier one).
	-- =========================================================================
	health.start("beast.libs.key — duplication")

	local duplicates = {}
	for id, bucket in pairs(core.conflicts or {}) do
		if #bucket.calls > 1 then
			duplicates[#duplicates + 1] = { id = id, bucket = bucket }
		end
	end

	if #duplicates == 0 then
		health.ok(string.format("No duplicate lhs across %d managed keymaps", vim.tbl_count(core.managed)))
	else
		health.warn(string.format("%d keymap(s) registered more than once (later overwrites earlier):", #duplicates))
		table.sort(duplicates, function(a, b)
			return a.bucket.lhs < b.bucket.lhs
		end)
		for _, d in ipairs(duplicates) do
			local b = d.bucket
			health.warn(string.format("  • `%s` (mode: %s)", b.lhs, b.mode))
			for i, site in ipairs(b.calls) do
				local marker = (i == #b.calls) and "active   " or "shadowed "
				health.info(string.format("      [%s] %s:%d  %s", marker, site.source, site.line, site.desc and ('"' .. site.desc .. '"') or ""))
			end
		end
	end

	-- =========================================================================
	-- Prefix conflicts: a shorter immediate-action lhs forces `timeoutlen` ms
	-- of waiting on every longer lhs sharing the prefix. With the press-and-
	-- wait hint enabled this is especially visible — pressing the short key
	-- either triggers its action or stalls the hint loop.
	--
	-- Example: `<leader>c` (Colorschemes) blocks `<leader>ca` (Code action).
	-- =========================================================================
	health.start("beast.libs.key — prefix conflicts")

	local prefix_conflicts = {}
	for _, pair in pairs(core.prefix_conflicts or {}) do
		local short_bucket = core.conflicts[pair.short_id]
		local long_bucket = core.conflicts[pair.long_id]
		if short_bucket and long_bucket then
			prefix_conflicts[#prefix_conflicts + 1] = {
				mode = pair.mode,
				short = short_bucket,
				long = long_bucket,
			}
		end
	end

	if #prefix_conflicts == 0 then
		health.ok("No prefix conflicts detected")
	else
		health.warn(
			string.format("%d prefix conflict(s) — shorter key delays the longer key by `timeoutlen` (%dms):", #prefix_conflicts, vim.o.timeoutlen)
		)
		table.sort(prefix_conflicts, function(a, b)
			if a.short.lhs == b.short.lhs then
				return a.long.lhs < b.long.lhs
			end
			return a.short.lhs < b.short.lhs
		end)
		for _, pc in ipairs(prefix_conflicts) do
			health.warn(string.format("  • `%s` blocks `%s` (mode: %s)", pc.short.lhs, pc.long.lhs, pc.mode))
			local s = pc.short.calls[#pc.short.calls]
			local l = pc.long.calls[#pc.long.calls]
			health.info(string.format("      prefix   %s:%d  %s", s.source, s.line, s.desc and ('"' .. s.desc .. '"') or ""))
			health.info(string.format("      longer   %s:%d  %s", l.source, l.line, l.desc and ('"' .. l.desc .. '"') or ""))
		end
	end
end

return M
