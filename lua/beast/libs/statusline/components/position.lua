local util = require("beast.libs.statusline.util")

local get_position = util.file_bound(function(ctx)
	-- Only compute for named files (skip unnamed startup buffer)
	-- stylua: ignore
	if vim.api.nvim_buf_get_name(ctx.bufnr) == "" then return nil end
	local line = vim.fn.line(".", ctx.winid)
	local col = vim.fn.charcol(".", ctx.winid)
	return string.format("Ln %d, Col %d", line, col)
end)

---@type Beast.Statusline.ComponentSpec
return {
	scope = "window",
	priority = 70,
	provider = function(ctx)
		local result = get_position(ctx)
		-- stylua: ignore
		if not result then return {} end
		return { { text = result, hl = { fg = "accent6" } } }
	end,
}
