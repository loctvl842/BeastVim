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
end

return M

