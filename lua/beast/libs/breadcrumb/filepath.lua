-- Pure rendering function for breadcrumb filepath segments.
-- Stateless: receives context + config values, returns a statusline format string.

local kinds = require("beast.libs.breadcrumb.symbols.kinds")

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

---Build the filename + icon as a format string and its display width.
---@param filename string
---@param ext string
---@return string fmt
---@return integer width
local function build_file_part(filename, ext)
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

	return table.concat(parts), width
end

---Build one symbol segment: kind icon (family colour) + name.
---@param symbol Beast.Breadcrumb.Symbol
---@return Beast.Breadcrumb.Segment
local function build_symbol_segment(symbol)
	local icon = vim.trim(require("beast.icon").kinds[symbol.kind] or "")
	local fmt = "%#BeastBcSym" .. kinds.family(symbol.kind) .. "#" .. icon .. "%* %#BeastBcSymbol#" .. symbol.name .. "%*"
	return {
		text = symbol.name,
		fmt = fmt,
		width = vim.fn.strdisplaywidth(icon) + 1 + vim.fn.strdisplaywidth(symbol.name),
	}
end

---Index of the first segment to keep when dropping from the left until `remaining` fits `budget`.
---Each segment costs its width plus one separator. At least `keep` trailing segments survive.
---@param segs Beast.Breadcrumb.Segment[]
---@param remaining integer  Width of all segments (each + separator)
---@param budget integer
---@param keep integer
---@param sep_width integer
---@return integer start_idx
local function drop_left(segs, remaining, budget, keep, sep_width)
	local idx = 1
	while idx <= #segs - keep and remaining > budget do
		remaining = remaining - segs[idx].width - sep_width
		idx = idx + 1
	end
	return idx
end

---@class Beast.Breadcrumb.Symbol
---@field name string  Symbol name (non-empty)
---@field kind string  `Icon.kinds` key (Function, Class, ...)

---Render the filepath portion of the breadcrumb bar.
---@param ctx Beast.Breadcrumb.Context
---@param separator string
---@param modified_icon string
---@param symbols? Beast.Breadcrumb.Symbol[]  Outermost-first chain at the cursor
---@return string  Statusline format string
function M.render(ctx, separator, modified_icon, symbols)
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

	-- Build the file part (icon + name), the symbol trail and the modified marker
	local file_fmt, file_width = build_file_part(filename, ext)

	---@type Beast.Breadcrumb.Segment[]
	local sym_segs = {}
	for _, symbol in ipairs(symbols or {}) do
		if symbol.name ~= "" then
			sym_segs[#sym_segs + 1] = build_symbol_segment(symbol)
		end
	end

	local marker_fmt, marker_width = "", 0
	if vim.bo[ctx.bufnr].modified then
		marker_fmt = "%#BeastBcModified#" .. modified_icon .. "%*"
		marker_width = vim.fn.strdisplaywidth(modified_icon)
	end

	-- Everything after the directories: file, symbols (each behind a separator), marker
	local sym_width = 0
	for _, seg in ipairs(sym_segs) do
		sym_width = sym_width + sep_width + seg.width
	end
	local tail_width = file_width + sym_width + marker_width

	-- Total width: 1 (padding) + dirs + separators + tail
	local dirs_width = 0
	for _, seg in ipairs(dir_segs) do
		dirs_width = dirs_width + seg.width + sep_width
	end

	-- Truncate from the left: directories first, then outer symbols (innermost always kept)
	local available = ctx.width
	local start_idx = 1
	local sym_start = 1
	if 1 + dirs_width + tail_width > available then
		if #dir_segs > 0 then
			-- Reserve space for ellipsis + separator
			local budget = available - tail_width - 1 - ellipsis_width - sep_width
			start_idx = drop_left(dir_segs, dirs_width, budget, 0, sep_width)
		end
		if start_idx > #dir_segs and #sym_segs > 1 then
			local lead = #dir_segs > 0 and ellipsis_width or 0
			local budget = available - 1 - lead - file_width - marker_width
			if sym_width > budget then
				-- Reserve space for the "…" that replaces the dropped symbols
				sym_start = drop_left(sym_segs, sym_width, budget - sep_width - ellipsis_width, 1, sep_width)
			end
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

	if sym_start > 1 then
		parts[#parts + 1] = sep_fmt .. "%#BeastBcSep#" .. ELLIPSIS .. "%*"
	end
	for i = sym_start, #sym_segs do
		parts[#parts + 1] = sep_fmt
		parts[#parts + 1] = sym_segs[i].fmt
	end

	parts[#parts + 1] = marker_fmt

	return table.concat(parts)
end

return M
