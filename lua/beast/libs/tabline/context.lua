local buffers_mod = require("beast.libs.tabline.buffers")
local config = require("beast.libs.tabline.config")
local name_mod = require("beast.libs.tabline.name")

local ok_devicons, devicons = pcall(require, "nvim-web-devicons")

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
---@field effective_active integer
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
			local icon, color = devicons.get_icon_color(filename, ext, { default = true })
			icons_by_buf[bufnr] = { icon = icon or "", color = color }
		end
	end

	-- Pre-compute modified state for all buffers
	local modified_by_buf = {}
	for _, bufnr in ipairs(listed) do
		modified_by_buf[bufnr] = vim.bo[bufnr].modified
	end

	-- Resolve effective active buffer (sidebar-aware)
	local current_buf = vim.api.nvim_get_current_buf()
	local effective = current_buf
	if
		buffers_mod.is_sidebar_buf(current_buf)
		and state.last_active_bufnr
		and vim.api.nvim_buf_is_valid(state.last_active_bufnr)
		and vim.bo[state.last_active_bufnr].buflisted
	then
		effective = state.last_active_bufnr
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

	return {
		columns = vim.o.columns,
		current_buf = current_buf,
		effective_active = effective,
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
	}
end

return M
