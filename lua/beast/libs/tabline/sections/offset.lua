local M = {}

--- Render the sidebar offset section.
--- If the first window is a sidebar, returns a centered title block matching
--- the sidebar width so buffer tabs start at the editor split.
---@param ctx Beast.Tabline.Context
---@return string
function M.render(ctx)
	-- stylua: ignore
	if not ctx.sidebar_winid then return "" end

	local width = ctx.sidebar_width or 0
	local title = ctx.sidebar_title or ""

	local title_len = vim.fn.strdisplaywidth(title)
	local pad_left = math.floor((width - title_len) / 2)
	local pad_right = width - pad_left - title_len

	return "%#BeastTlOffset#" .. string.rep(" ", math.max(0, pad_left)) .. title .. string.rep(" ", math.max(0, pad_right))
end

return M
