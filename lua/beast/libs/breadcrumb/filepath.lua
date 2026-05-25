-- Pure rendering function for breadcrumb filepath segments.
-- Stateless: receives context + config values, returns a statusline format string.

local M = {}

local ELLIPSIS = "…"
-- 1 char for padding + 1 for ellipsis + separator width (computed once)
local ellipsis_width = vim.fn.strdisplaywidth(ELLIPSIS)

---Get file icon and its highlight group via nvim-web-devicons.
---@param filename string
---@param ext string
---@return string icon
---@return string? icon_hl_group
local function get_icon(filename, ext)
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if not ok then
		return "", nil
	end
	local icon, hl_group = devicons.get_icon(filename, ext, { default = true })
	if not icon then
		return "", nil
	end
	return icon, hl_group
end

---@class Beast.Breadcrumb.Segment
---@field text string       Display text (plain, no hl codes)
---@field fmt string        Statusline format string with highlight codes
---@field width integer     Display width in cells

---Build the filename + icon + modified suffix as a format string and its display width.
---@param filename string
---@param ext string
---@param bufnr integer
---@param modified_icon string
---@return string fmt
---@return integer width
local function build_file_part(filename, ext, bufnr, modified_icon)
	local parts = {}
	local width = 0

	local icon, icon_hl = get_icon(filename, ext)
	if icon ~= "" then
		if icon_hl then
			parts[#parts + 1] = "%#" .. icon_hl .. "#" .. icon .. "%* "
		else
			parts[#parts + 1] = icon .. " "
		end
		width = width + vim.fn.strdisplaywidth(icon) + 1
	end

	parts[#parts + 1] = "%#BeastBcFile#" .. filename .. "%*"
	width = width + vim.fn.strdisplaywidth(filename)

	if vim.bo[bufnr].modified then
		parts[#parts + 1] = "%#BeastBcModified#" .. modified_icon .. "%*"
		width = width + vim.fn.strdisplaywidth(modified_icon)
	end

	return table.concat(parts), width
end

---Render the filepath portion of the breadcrumb bar.
---@param ctx Beast.Breadcrumb.Context
---@param separator string
---@param modified_icon string
---@return string  Statusline format string
function M.render(ctx, separator, modified_icon)
	-- stylua: ignore
	if ctx.bufname == "" then return "" end

	-- Make path relative to project root
	local root = Util.root()
	local rel
	if root and ctx.bufname:find(root, 1, true) == 1 then
		rel = ctx.bufname:sub(#root + 2)
	else
		rel = vim.fn.fnamemodify(ctx.bufname, ":t")
	end

	local segments = {}
	for part in rel:gmatch("[^/]+") do
		segments[#segments + 1] = part
	end

	-- stylua: ignore
	if #segments == 0 then return "" end

	local filename = segments[#segments]
	local ext = vim.fn.fnamemodify(filename, ":e")
	local sep_width = vim.fn.strdisplaywidth(separator)

	-- Build directory segment data (display text + width)
	---@type Beast.Breadcrumb.Segment[]
	local dir_segs = {}
	for i = 1, #segments - 1 do
		local text = segments[i]
		dir_segs[#dir_segs + 1] = {
			text = text,
			fmt = "%#BeastBcDir#" .. text .. "%*",
			width = vim.fn.strdisplaywidth(text),
		}
	end

	-- Build the file part (icon + name + modified)
	local file_fmt, file_width = build_file_part(filename, ext, ctx.bufnr, modified_icon)

	-- Calculate total width: 1 (padding) + dirs + separators + file
	local total_width = 1 -- left padding space
	for i, seg in ipairs(dir_segs) do
		total_width = total_width + seg.width
		if i < #dir_segs or #dir_segs > 0 then
			total_width = total_width + sep_width
		end
	end
	total_width = total_width + file_width

	-- Truncate directory segments from the left if too wide
	local available = ctx.width
	local start_idx = 1
	if total_width > available and #dir_segs > 0 then
		-- Reserve space for ellipsis + separator
		local budget = available - file_width - 1 - ellipsis_width - sep_width
		-- Drop dirs from the left until remaining dirs fit
		local remaining = 0
		for i, seg in ipairs(dir_segs) do
			remaining = remaining + seg.width + sep_width
		end
		while start_idx <= #dir_segs and remaining > budget do
			remaining = remaining - dir_segs[start_idx].width - sep_width
			start_idx = start_idx + 1
		end
	end

	-- Assemble output
	local parts = {}
	local sep_fmt = "%#BeastBcSep#" .. separator .. "%*"
	local truncated = start_idx > 1

	if truncated then
		parts[#parts + 1] = "%#BeastBcSep#" .. ELLIPSIS .. "%*"
	end

	for i = start_idx, #dir_segs do
		if i > start_idx or truncated then
			parts[#parts + 1] = sep_fmt
		end
		parts[#parts + 1] = dir_segs[i].fmt
	end

	if #dir_segs >= start_idx then
		parts[#parts + 1] = sep_fmt
	end

	parts[#parts + 1] = file_fmt

	return table.concat(parts)
end

return M
