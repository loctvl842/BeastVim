---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	priority = 80,
	provider = function(ctx)
		local result = require("beast.libs.searchcount").get(ctx.winid)
		-- stylua: ignore
		if not result then return {} end
		return { { text = " " .. result.text .. " ", hl = { fg = "dark1", bg = "yellow", bold = true } } }
	end,
}
