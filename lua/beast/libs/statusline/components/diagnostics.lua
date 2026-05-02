---@type Beast.Statusline.ComponentSpec
return {
	update = { "DiagnosticChanged", "BufEnter" },
	scope = "buffer",
	priority = 50,
	provider = function(ctx)
		local counts = { 0, 0, 0, 0 }
		for _, d in ipairs(vim.diagnostic.get(ctx.bufnr)) do
			counts[d.severity] = (counts[d.severity] or 0) + 1
		end
		local sev = vim.diagnostic.severity
		local icons = (Icon and Icon.diagnostics) or { error = "E", warn = "W", info = "I", hint = "H" }
		return {
			{ text = icons.error .. " " .. counts[sev.ERROR] .. " ", hl = { fg = "accent1" } },
			{ text = icons.warn .. " " .. counts[sev.WARN] .. " ", hl = { fg = "accent3" } },
			{ text = icons.info .. " " .. counts[sev.INFO] .. " ", hl = { fg = "accent5" } },
			{ text = icons.hint .. " " .. counts[sev.HINT], hl = { fg = "accent4" } },
		}
	end,
}
