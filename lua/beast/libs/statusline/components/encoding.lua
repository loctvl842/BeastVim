local util = require("beast.libs.statusline.util")

local get_encoding = util.file_bound(function(ctx)
	local enc = vim.bo[ctx.bufnr].fileencoding
	if enc == "" then
		enc = vim.o.encoding
	end
	-- stylua: ignore
	if enc == "" then return nil end
	return enc:upper()
end)

---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	update = { "BufEnter", "OptionSet fileencoding", "OptionSet encoding" },
	scope = "buffer",
	priority = 15,
	provider = function(ctx)
		local result = get_encoding(ctx)
		-- stylua: ignore
		if not result then return {} end
		return { { text = result, hl = { fg = "accent4" } } }
	end,
}
