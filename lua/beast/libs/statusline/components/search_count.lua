---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	priority = 80,
	provider = function(ctx)
		-- Do not require() here: in minimal mode that would silently load the
		-- searchcount lib (and its decoration provider and autocmds) as a side
		-- effect of a statusline render. Show the pill only once the lib is
		-- loaded; `get` reads its debounced cache.
		local searchcount = package.loaded["beast.libs.searchcount"]
		if type(searchcount) ~= "table" then
			return {}
		end
		local result = searchcount.get(ctx.winid)
		-- stylua: ignore
		if not result then return {} end
		return { { text = " " .. result.text .. " ", hl = { fg = "dark1", bg = "yellow", bold = true } } }
	end,
}
