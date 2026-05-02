local util = require("beast.libs.statusline.util")

local get_shiftwidth = util.file_bound(function(ctx)
	return "Spaces: " .. vim.bo[ctx.bufnr].shiftwidth
end)

---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	update = { "BufEnter" },
	scope = "buffer",
	priority = 20,
	provider = function(ctx)
		local result = get_shiftwidth(ctx)
		-- stylua: ignore
		if not result then return {} end
		return { { text = result, hl = { fg = "accent3" } } }
	end,
}
