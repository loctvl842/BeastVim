local Filter = require("beast.libs.finder.filter")
local config = require("beast.libs.finder.config")
local layout = require("beast.libs.finder.layout")
local match_pipeline = require("beast.libs.finder.pipeline.match")
local render = require("beast.libs.finder.render")
local source_registry = require("beast.libs.finder.source")
local stream_pipeline = require("beast.libs.finder.pipeline.stream")
local ui = require("beast.libs.finder.ui")

---@class Beast.Finder.Item
---@field idx number
---@field score number
---@field text string
---@field cwd? string
---@field file? string
---@field buf? number
---@field positions? number[]
---@field pos? {[1]: number, [2]: number}
---@field end_pos? {[1]: number, [2]: number}
---@field grep_text? string
---@field match_text? string  literal text grep actually matched (for preview highlight)
---@field help_tag? string
---@field is_readme? boolean
---@field _lower? string cached lowercased text for matcher

---@class Beast.Finder.Query
---@field items Beast.Finder.Item[]
---@field matched Beast.Finder.Item[]
---@field filter Beast.Finder.Filter
---@field main_win integer
---@field input_view Beast.Finder.InputView
---@field list_view Beast.Finder.ListView
---@field preview_view Beast.Finder.PreviewView|nil
---@field _backdrop_win integer
---@field source Beast.Finder.Source
---@field _preview boolean -- whether to show preview window
---@field highlight_preview boolean -- true for stream sources (grep) — highlights pattern in preview
---@field pipeline table -- active pipeline module (match or stream)
---@field _augroup integer
---@field _on_preview? fun(item: Beast.Finder.Item)
---@field _on_close? fun()
---@field _closed? boolean -- guards against double-close (stale picker re-closed on next open)
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

-- ---------------------------------------------------------------------------
-- Constructor / public methods
-- ---------------------------------------------------------------------------
---@class Beast.Finder.QueryOpts
---@field cwd? string
---@field preview? boolean preview window enabled
---@field on_preview? fun(item: Beast.Finder.Item)
---@field on_close? fun()
---@field lsp? {results: Beast.Finder.Item[], symbol?: string} pre-fetched LSP results

---@param source_name Beast.Finder.Source
---@param opts? Beast.Finder.QueryOpts
---@return Beast.Finder.Query
function M:new(source_name, opts)
	opts = opts or {}

	local source = source_registry[source_name]
	local is_live = source and source.live or false

	local has_preview = opts.preview ~= false
	local geo = layout.calc(has_preview)

	local query = setmetatable({
		items = {},
		matched = {},
		filter = Filter({ cwd = opts.cwd, lsp = opts.lsp }),
		main_win = View.win.find_normal(),
		source = source_name,
		_preview = has_preview,
		highlight_preview = is_live,
		pipeline = is_live and stream_pipeline or match_pipeline,
		_on_preview = opts.on_preview,
		_on_close = opts.on_close,
	}, self)

	-- Backdrop must open before picker windows (lower zindex)
	query._backdrop_win = ui.backdrop.create(config.backdrop)

	local title_name = source_name:gsub("_", " ")
	local title = title_name:sub(1, 1):upper() .. title_name:sub(2)
	local input_debounce = is_live and config.debounce.live_ms or nil
	query.input_view = ui.input.create(function(text)
		query.filter:update(text)
		if is_live then
			stream_pipeline.reload(query)
		else
			match_pipeline.rescore(query)
		end
	end, geo.input.w, geo.input.h, geo.input.row, geo.input.col, title, input_debounce, geo.input.border)

	query.list_view = ui.list.create(geo.list.row, geo.list.col, geo.list.w, geo.list.h, geo.list.border)

	if has_preview then
		query.preview_view = ui.preview.create(geo.preview.row, geo.preview.col, geo.preview.w, geo.preview.h)
	end

	require("beast.libs.finder.keymaps").mount(query)
	require("beast.libs.finder.autocmds").mount(query)

	-- Match pipeline loads items immediately; stream waits for user input
	if not is_live then
		match_pipeline.load(query)
	end

	return query
end

function M:close()
	-- Idempotent: the module-level picker may be closed once on selection
	-- (keymaps/WinEnter) and then re-closed by the next M.open. Re-running the
	-- focus restore would steal the cursor from the user's current window
	-- before find_normal() captures it.
	if self._closed then
		return
	end
	self._closed = true

	if self._on_close then
		self._on_close()
	end
	self.pipeline.abort(self)
	if self._augroup then
		vim.api.nvim_del_augroup_by_id(self._augroup)
		self._augroup = nil
	end
	render.cleanup(self)
	ui.input.stop_spinner(self.input_view)
	if self.input_view._timer then
		self.input_view._timer:stop()
		self.input_view._timer:close()
		self.input_view._timer = nil
	end
	if self.preview_view then
		self.preview_view:close()
	end
	self.list_view:close()
	self.input_view:close()
	ui.backdrop.close(self._backdrop_win)
	self._backdrop_win = nil
	if self.main_win and vim.api.nvim_win_is_valid(self.main_win) then
		vim.api.nvim_set_current_win(self.main_win)
	end
end

function M:relayout()
	local geo = layout.calc(self._preview)

	-- Reposition backdrop
	if self._backdrop_win and vim.api.nvim_win_is_valid(self._backdrop_win) then
		pcall(vim.api.nvim_win_set_config, self._backdrop_win, {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines,
			row = 0,
			col = 0,
		})
	end

	-- Reposition input
	if self.input_view:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.input_view.win, {
			relative = "editor",
			width = geo.input.w,
			height = geo.input.h,
			row = geo.input.row,
			col = geo.input.col,
		})
	end

	-- Reposition list
	if self.list_view:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.list_view.win, {
			relative = "editor",
			width = geo.list.w,
			height = geo.list.h,
			row = geo.list.row,
			col = geo.list.col,
		})
	end

	-- Reposition preview
	if self.preview_view and self.preview_view:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.preview_view.win, {
			relative = "editor",
			width = geo.preview.w,
			height = geo.preview.h,
			row = geo.preview.row,
			col = geo.preview.col,
		})
	end
end

return M
