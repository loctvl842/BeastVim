local util = require("beast.libs.statusline.util")

local get_filetype = util.file_bound(function(ctx)
	local ft = vim.bo[ctx.bufnr].filetype
	if ft ~= "" then
		local formatted = ft:gsub("^%l", string.upper)
		return formatted
	end
	return false
end)

---@type Beast.Statusline.ComponentSpec
return {
	update = { "BufEnter" }, -- FileType
	scope = "buffer",
	priority = 40,
	provider = function(ctx)
		local result = get_filetype(ctx)
    -- stylua: ignore
		if not result then return {} end
    return { { text = result, hl = { fg = "accent5" } } }
	end,
}
