local M = {}

function M.check()
	local health = vim.health
	local config = require("beast.libs.bigfile.config")
	local bigfile = require("beast.libs.bigfile")

	health.start("beast.libs.bigfile")

	if not config.enabled then
		health.warn("disabled (`enabled = false`): no buffer is treated as big")
		return
	end

	health.ok(("big when over %.1f MB, or average line over %d characters"):format(config.size / (1024 * 1024), config.line_length))

	if _G.Toast then
		health.ok("Toast available")
	else
		health.warn("Toast not loaded: the big-file notice will fail")
	end

	local off = {}
	for feature, v in pairs(config.disable) do
		if v then
			off[#off + 1] = feature
		end
	end
	table.sort(off)
	health.info("switched off for a big buffer: " .. table.concat(off, ", "))

	local buf = vim.api.nvim_get_current_buf()
	health.info(("current buffer: %s"):format(bigfile.is(buf) and "big" or "normal"))
end

return M
