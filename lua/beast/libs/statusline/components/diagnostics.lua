---@type Beast.Statusline.ComponentSpec
return {
	update = { "DiagnosticChanged" },
	scope = "global",
	priority = 50,
	provider = function()
		local counts = { 0, 0, 0, 0 }
		for _, d in ipairs(vim.diagnostic.get(nil)) do
			counts[d.severity] = (counts[d.severity] or 0) + 1
		end
		local sev = vim.diagnostic.severity
		local icons = (Icon and Icon.diagnostics) or { error = "E", warn = "W", info = "I", hint = "H" }
		local levels = {
			{ count = counts[sev.ERROR], icon = icons.error, color = "accent1" },
			{ count = counts[sev.WARN], icon = icons.warn, color = "accent2" },
			{ count = counts[sev.INFO], icon = icons.info, color = "accent5" },
			{ count = counts[sev.HINT], icon = icons.hint, color = "accent4" },
		}
		local fragments = {}
		for _, lvl in ipairs(levels) do
			if lvl.count > 0 then
				fragments[#fragments + 1] = {
					text = lvl.icon .. " " .. lvl.count .. " ",
					hl = { fg = lvl.color },
				}
			end
		end
		if #fragments > 0 then
			fragments[#fragments].text = fragments[#fragments].text:gsub(" $", "")
		end
		return fragments
	end,
}
