local M = {}

function M.check()
	local health = vim.health
	health.start("beast.libs.window")

	-- Submodules
	health.start("beast.libs.window — modules")
	for _, name in ipairs({ "config", "state", "win", "frame", "layout", "resize", "animate", "autocmds" }) do
		local ok, err = pcall(require, "beast.libs.window." .. name)
		if ok then
			health.ok("loaded: " .. name)
		else
			health.error(string.format("failed to load %s: %s", name, err))
		end
	end

	-- Config
	health.start("beast.libs.window — config")
	local config = require("beast.libs.window.config")
	health.info(("autowidth.enable=%s, winwidth=%s"):format(tostring(config.autowidth.enable), tostring(config.autowidth.winwidth)))
	health.info(
		("animation.enable=%s, duration=%dms, easing=%s"):format(
			tostring(config.animation.enable),
			config.animation.duration or 0,
			tostring(config.animation.easing)
		)
	)
	local bt = vim.tbl_keys(config.ignore.buftype)
	local ft = vim.tbl_keys(config.ignore.filetype)
	table.sort(bt)
	table.sort(ft)
	health.info("ignore.buftype: " .. table.concat(bt, ", "))
	health.info("ignore.filetype: " .. table.concat(ft, ", "))

	-- Augroups
	health.start("beast.libs.window — autocmds")
	local state = require("beast.libs.window.state")
	if state.augroup_autowidth then
		health.ok("autowidth augroup registered (id=" .. state.augroup_autowidth .. ")")
	else
		health.warn("autowidth augroup not registered (autowidth disabled?)")
	end
	if state.augroup_maximize then
		health.info("maximize-guard augroup active (id=" .. state.augroup_maximize .. ")")
	else
		health.info("maximize-guard inactive (nothing is maximized)")
	end

	-- Animation
	health.start("beast.libs.window — animation")
	if state.animation and state.animation.running then
		health.info(("animation in flight (%d entries)"):format(#state.animation.entries))
	else
		health.ok("idle")
	end

	-- Frame tree summary for current tab
	health.start("beast.libs.window — current layout")
	local frame = require("beast.libs.window.frame")
	local top = frame.new()
	local leaves = top:get_all_nested_leafs()
	health.info(("root type: %s, leaves: %d, top width: %d, top height: %d"):format(top.type, #leaves, top:get_width(), top:get_height()))
end

return M
