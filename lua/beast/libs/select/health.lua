local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.select")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required for select floating windows")
		return
	end

	local ok_cfg, config = pcall(require, "beast.libs.select.config")
	if not ok_cfg then
		health.error("Failed to load select config: " .. tostring(config))
		return
	end

	local select_mod = package.loaded["beast.libs.select"]
	if select_mod then
		health.ok("Select module loaded")
	else
		health.warn("Select module not loaded (require('beast.libs.select').setup() not called)")
	end

	if config.disabled then
		health.info("Module is disabled — native vim.ui.select is used as fallback")
	else
		health.ok("Module enabled (custom UI active)")
	end

	-- =========================================================================
	-- API contract: run(items, opts, on_choice) — must match vim.ui.select
	-- =========================================================================
	health.start("beast.libs.select — API contract")

	if not select_mod then
		health.error("Module not loaded — cannot run API tests")
	else
		if type(select_mod.run) == "function" then
			health.ok("run() available (assigned to vim.ui.select on setup)")
		else
			health.error("run() missing — cannot replace vim.ui.select")
		end

		if type(select_mod.setup) == "function" then
			health.ok("setup() available")
		else
			health.error("setup() missing")
		end

		local ok_ui, ui_mod = pcall(require, "beast.libs.select.ui")
		if ok_ui then
			if type(ui_mod.open) == "function" then
				health.ok("UI module has open()")
			else
				health.error("UI module missing open()")
			end
		else
			health.error("Failed to load UI module: " .. tostring(ui_mod))
		end

		local ok_filter, filter_mod = pcall(require, "beast.libs.select.filter")
		if ok_filter and type(filter_mod.matches) == "function" then
			health.ok("Filter module has matches()")
		else
			health.error("Filter module missing matches()")
		end

		health.info("Headless fallback: delegates to native vim.ui.select when no UI attached")
	end

	-- =========================================================================
	-- Highlights
	-- =========================================================================
	health.start("beast.libs.select — highlights")

	local required_hls = {
		"BeastSelectNormal",
		"BeastSelectBorder",
		"BeastSelectBackdrop",
		"BeastSelectInputNormal",
		"BeastSelectInputTitle",
		"BeastSelectListCursorLine",
		"BeastSelectListBullet",
		"BeastSelectListTag",
		"BeastSelectListEmpty",
		"BeastSelectFooter",
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
	health.start("beast.libs.select — configuration")

	health.info(string.format("disabled = %s", tostring(config.disabled)))
	health.info(string.format("ui.backdrop = %d", config.ui and config.ui.backdrop or 0))

	if vim.o.columns < 40 or vim.o.lines < 8 then
		health.warn(string.format("Terminal size (%dx%d) may be too small for the select picker", vim.o.columns, vim.o.lines))
	else
		health.ok(string.format("Terminal size (%dx%d) sufficient for the select picker", vim.o.columns, vim.o.lines))
	end
end

return M
