local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.confirm")

	-- Check Neovim version
	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for confirm floating windows")
		return
	end

	-- Check config loads
	local ok_cfg, config = pcall(require, "beast.libs.confirm.config")
	if not ok_cfg then
		health.error("Failed to load confirm config: " .. tostring(config))
		return
	end

	-- Check module loaded
	local confirm_mod = package.loaded["beast.libs.confirm"]
	if confirm_mod then
		health.ok("Confirm module loaded")
	else
		health.warn("Confirm module not loaded (require('beast.libs.confirm').setup() not called)")
	end

	-- Check disabled state
	if config.disabled then
		health.info("Module is disabled — vim.fn.confirm is used as fallback")
	else
		health.ok("Module enabled (custom UI active)")
	end

	-- =========================================================================
	-- API contract: confirm(msg, choices, default, type) → integer
	-- Must match vim.fn.confirm signature
	-- =========================================================================
	health.start("beast.libs.confirm — API contract")

	if not confirm_mod then
		health.error("Module not loaded — cannot run API tests")
	else
		-- Test 1: module is callable via __call
		local mt = getmetatable(confirm_mod)
		if mt and mt.__call then
			health.ok("Module has __call metamethod (drop-in for vim.fn.confirm)")
		else
			health.error("Module missing __call metamethod — cannot replace vim.fn.confirm")
		end

		-- Test 2: set_opts is available
		if type(confirm_mod.set_opts) == "function" then
			health.ok("set_opts() available")
		else
			health.warn("set_opts() missing")
		end

		-- Test 3: setup is available
		if type(confirm_mod.setup) == "function" then
			health.ok("setup() available")
		else
			health.error("setup() missing")
		end

		-- Test 4: verify UI module loads and has expected functions
		local ok_ui, ui_mod = pcall(require, "beast.libs.confirm.ui")
		if ok_ui then
			local ui_fns = { "create", "render", "run_modal_loop", "close" }
			local missing = {}
			for _, fn_name in ipairs(ui_fns) do
				if type(ui_mod[fn_name]) ~= "function" then
					missing[#missing + 1] = fn_name
				end
			end
			if #missing == 0 then
				health.ok("UI module has all required functions (create, render, run_modal_loop, close)")
			else
				health.error("UI module missing functions: " .. table.concat(missing, ", "))
			end
		else
			health.error("Failed to load UI module: " .. tostring(ui_mod))
		end

		-- Test 5: headless fallback — when no UI is attached, should delegate to vim.fn.confirm
		-- (We can't test this in a GUI session, just report the logic exists)
		health.info("Headless fallback: delegates to vim.fn.confirm when no UI attached")
	end

	-- =========================================================================
	-- Highlights
	-- =========================================================================
	health.start("beast.libs.confirm — highlights")

	local required_hls = {
		"BeastConfirmNormal",
		"BeastConfirmBorder",
		"BeastConfirmBackdrop",
		"BeastConfirmButton",
		"BeastConfirmButtonActive",
	}
	local missing_hls = {}
	for _, hl_name in ipairs(required_hls) do
		local hl = vim.api.nvim_get_hl(0, { name = hl_name })
		if vim.tbl_isempty(hl) then
			missing_hls[#missing_hls + 1] = hl_name
		end
	end
	if #missing_hls == 0 then
		health.ok("All highlight groups defined")
	else
		health.warn("Missing highlight groups: " .. table.concat(missing_hls, ", "))
	end

	-- =========================================================================
	-- Configuration
	-- =========================================================================
	health.start("beast.libs.confirm — configuration")

	health.info(string.format("disabled = %s", tostring(config.disabled)))
	health.info(string.format("ui.backdrop = %d", config.ui and config.ui.backdrop or 0))

	-- Check terminal size is sufficient for dialog
	if vim.o.columns < 40 or vim.o.lines < 8 then
		health.warn(string.format("Terminal size (%dx%d) may be too small for confirm dialogs", vim.o.columns, vim.o.lines))
	else
		health.ok(string.format("Terminal size (%dx%d) sufficient for confirm dialogs", vim.o.columns, vim.o.lines))
	end
end

return M
