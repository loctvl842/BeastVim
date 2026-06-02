local buffers_mod = require("beast.libs.tabline.buffers")
local name_mod = require("beast.libs.tabline.name")

local ok_devicons, devicons = pcall(require, "nvim-web-devicons")

--- Custom icons for buffers that nvim-web-devicons doesn't know about
--- (URI-style names like `health://`). Registered once on module load so
--- the side-effect stays scoped to the tabline lib.
---@type table<string, { icon: string, color: string, cterm_color: string, name: string }>
local custom_icons = {
	checkhealth = {
		icon = "󰓙",
		color = "#a3be8c",
		cterm_color = "108",
		name = "Checkhealth",
	},
}

if ok_devicons then
	if devicons.set_icon_by_filetype then
		local ft_map = {}
		for ft in pairs(custom_icons) do
			ft_map[ft] = ft
		end
		devicons.set_icon_by_filetype(ft_map)
	end
	if devicons.set_icon then
		devicons.set_icon(custom_icons)
	end
end

local M = {}

---@class Beast.Tabline.DiagSummary
---@field severity integer Highest severity present (1=ERROR … 4=HINT)
---@field count integer Total diagnostics on this buffer
---@field errors table<integer, integer> Per-severity counts

--- Build a diag_by_buf table from a single global vim.diagnostic.get() walk.
---@return table<integer, Beast.Tabline.DiagSummary>
local function build_diag_by_buf()
	local by_buf = {}
	for _, d in ipairs(vim.diagnostic.get()) do
		local entry = by_buf[d.bufnr]
		if not entry then
			entry = { severity = d.severity, count = 0, errors = {} }
			by_buf[d.bufnr] = entry
		end
		entry.count = entry.count + 1
		entry.errors[d.severity] = (entry.errors[d.severity] or 0) + 1
		if d.severity < entry.severity then
			entry.severity = d.severity
		end
	end
	return by_buf
end

---@class Beast.Tabline.IconInfo
---@field icon string
---@field color? string

---@class Beast.Tabline.Context
---@field columns integer
---@field current_buf integer
---@field effective_active integer Active buffer for highlighting (-1 when sidebar focused)
---@field anchor_bufnr? integer Best buffer for truncation anchor (last active, even during sidebar focus)
---@field visible_bufs table<integer, boolean> Buffers currently visible in any window
---@field sidebar_winid? integer
---@field sidebar_width? integer
---@field sidebar_title? string
---@field listed_buffers integer[]
---@field names_by_buf table<integer, string>
---@field icons_by_buf table<integer, Beast.Tabline.IconInfo>
---@field modified_by_buf table<integer, boolean>
---@field diag_by_buf table<integer, Beast.Tabline.DiagSummary>
---@field tabpages integer[]
---@field current_tabnr integer
---@field tabpages_width integer
---@field toggle_button_width integer
---@field edge_trim_bufs? table<integer, boolean> Buffers rendered with edge trimming (skip min_cell_width)
---@field edge_trim_compact? table<integer, string> Map of buffer → pull side ("left"|"right") for compact edge trim

--- Build the render context. Called once per render.
---@param state table Module-level state from init.lua
---@return Beast.Tabline.Context
function M.build(state)
	local listed = buffers_mod.list()

	-- Fetch all buffer names once (shared by name disambiguation + icon lookup)
	local raw_names = {}
	for _, bufnr in ipairs(listed) do
		raw_names[bufnr] = vim.api.nvim_buf_get_name(bufnr)
	end

	local names = name_mod.build_names(listed, raw_names)

	-- Pre-compute icon data for all buffers
	local icons_by_buf = {}
	if ok_devicons then
		for _, bufnr in ipairs(listed) do
			local fullname = raw_names[bufnr]
			local filename = fullname:match("[^/]+$") or ""
			local ext = filename:match("%.([^%.]+)$") or ""
			local icon, color
			if filename ~= "" then
				icon, color = devicons.get_icon_color(filename, ext, { default = false })
			end
			if not icon then
				local ok_ft, ft = pcall(function()
					return vim.bo[bufnr].filetype
				end)
				if ok_ft and ft and ft ~= "" and devicons.get_icon_color_by_filetype then
					icon, color = devicons.get_icon_color_by_filetype(ft, { default = false })
				end
			end
			if not icon then
				icon, color = devicons.get_icon_color(filename, ext, { default = true })
			end
			icons_by_buf[bufnr] = { icon = icon or "", color = color }
		end
	end

	-- Pre-compute modified state for all buffers
	local modified_by_buf = {}
	for _, bufnr in ipairs(listed) do
		modified_by_buf[bufnr] = vim.bo[bufnr].modified
	end

	-- Resolve effective active buffer
	-- When focus is on a sidebar, no buffer is "selected" — all show as visible/normal
	-- When focus is on a non-listed buffer (finder, floating UI), preserve last active as selected
	local current_buf = vim.api.nvim_get_current_buf()
	local effective = current_buf
	local anchor_bufnr = current_buf
	if buffers_mod.is_sidebar_buf(current_buf) then
		effective = -1
		anchor_bufnr = state.last_active_bufnr
	elseif not vim.bo[current_buf].buflisted then
		effective = state.last_active_bufnr or current_buf
		anchor_bufnr = state.last_active_bufnr or current_buf
	end

	-- Sidebar detection: check first window of tabpage
	local sidebar_winid, sidebar_width, sidebar_title
	local wins = vim.api.nvim_tabpage_list_wins(0)
	if wins[1] then
		local first_buf = vim.api.nvim_win_get_buf(wins[1])
		local title = buffers_mod.sidebar_title(first_buf)
		if title ~= nil then
			sidebar_winid = wins[1]
			sidebar_width = vim.api.nvim_win_get_width(wins[1])
			sidebar_title = title
		end
	end

	-- Build set of buffers visible in any window of this tabpage
	local visible_bufs = {}
	for _, w in ipairs(wins) do
		visible_bufs[vim.api.nvim_win_get_buf(w)] = true
	end

	-- Diagnostics: single global walk with insert-mode skip
	local diag_by_buf
	local mode = vim.api.nvim_get_mode().mode
	local in_insert = mode:find("^[iR]") ~= nil
	local diag_config = vim.diagnostic.config() or {}
	if in_insert and diag_config.update_in_insert == false and state.last_diag_by_buf then
		diag_by_buf = state.last_diag_by_buf
	else
		diag_by_buf = build_diag_by_buf()
		state.last_diag_by_buf = diag_by_buf
	end

	-- Tabpages
	local tabpages = vim.api.nvim_list_tabpages()
	local current_tabnr = vim.api.nvim_get_current_tabpage()

	-- Exact tabpages width (computed in context so buffer_list can use it)
	local tabpages_width = 0
	if #tabpages >= 2 then
		for _, tp in ipairs(tabpages) do
			local tabnr = vim.api.nvim_tabpage_get_number(tp)
			-- Each tab renders as " <n> " = len(n) + 2 spaces
			tabpages_width = tabpages_width + #tostring(tabnr) + 2
		end
	end

	-- Toggle button width (always visible on the right)
	local toggle_button = require("beast.libs.tabline.sections.toggle_button")
	local toggle_button_width = toggle_button.width()

	return {
		columns = vim.o.columns,
		current_buf = current_buf,
		effective_active = effective,
		anchor_bufnr = anchor_bufnr,
		visible_bufs = visible_bufs,
		sidebar_winid = sidebar_winid,
		sidebar_width = sidebar_width,
		sidebar_title = sidebar_title,
		listed_buffers = listed,
		names_by_buf = names,
		icons_by_buf = icons_by_buf,
		modified_by_buf = modified_by_buf,
		diag_by_buf = diag_by_buf,
		tabpages = tabpages,
		current_tabnr = current_tabnr,
		tabpages_width = tabpages_width,
		toggle_button_width = toggle_button_width,
	}
end

return M
