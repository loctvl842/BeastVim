local M = {}

--- Render the tabpages section.
--- Returns "" if fewer than 2 tabpages exist.
--- Uses native %<n>T…%T click regions (no Lua callback needed).
---@param ctx Beast.Tabline.Context
---@return string
function M.render(ctx)
	-- stylua: ignore
	if #ctx.tabpages < 2 then return "" end

	local parts = {}
	for _, tp in ipairs(ctx.tabpages) do
		local tabnr = vim.api.nvim_tabpage_get_number(tp)
		local is_active = tp == ctx.current_tabnr
		local hl = is_active and "BeastTlTabSelected" or "BeastTlTabVisible"
		table.insert(parts, "%" .. tabnr .. "T%#" .. hl .. "# " .. tabnr .. " %T")
	end

	return table.concat(parts)
end

return M
