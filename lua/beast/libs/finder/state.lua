local Query = require("beast.libs.finder.query")
local config = require("beast.libs.finder.config")
local pipeline_registry = require("beast.libs.finder.pipeline")
local source_registry = require("beast.libs.finder.source")
local ui = require("beast.libs.finder.ui")

---@class Beast.Finder.View
---@field input Beast.Finder.InputView
---@field list Beast.Finder.ListView
---@field preview? Beast.Finder.PreviewView
---@field backdrop? Beast.Finder.BackdropView

---@class Beast.Finder.State
---@field closed boolean -- guards against double-close (stale picker re-closed on next open)
---@field query Beast.Finder.Query
---@field pipeline Beast.Finder.Pipeline.Match|Beast.Finder.Pipeline.Stream
---@field view? Beast.Finder.View
---@field on_preview? fun(item: Beast.Finder.Item)
---@field on_close? fun()
---@field main_win? integer
---@field augroup? integer
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

---@type Beast.Finder.State?
local instance

---@class Beast.Finder.Opts: Beast.Finder.QueryOpts
---@field on_preview? fun(item: Beast.Finder.Item)
---@field on_close? fun()
---@field preview? boolean preview window enabled

---@param source_name Beast.Finder.Source
---@param opts? Beast.Finder.Opts
function M:new(source_name, opts)
	if instance then
		instance:reset()
	end
	opts = opts or {}
	local source = source_registry[source_name]
	local query = Query(source, { cwd = opts.cwd, lsp = opts.lsp })
	local is_live = source.live
	---@type Beast.Finder.Pipeline.Match|Beast.Finder.Pipeline.Stream
	local pipeline = is_live and pipeline_registry.stream or pipeline_registry.match

	instance = setmetatable({
		closed = false,
		main_win = View.win.find_normal(),
		on_preview = opts.on_preview,
		on_close = opts.on_close,
		query = query,
		pipeline = pipeline,
	}, self)

	-- View
	local has_preview = opts.preview ~= false
	local geo = require("beast.libs.finder.layout").calc(has_preview)
	local title_name = source_name:gsub("_", " ")
	local title = title_name:sub(1, 1):upper() .. title_name:sub(2)
	local input_debounce = is_live and config.debounce.live_ms or nil

	instance.view = {
		input = ui.input.create(function(text)
			query.filter:update(text)
			pipeline.run(instance)
		end, geo.input.w, geo.input.h, geo.input.row, geo.input.col, title, input_debounce, geo.input.border),
		list = ui.list.create(geo.list.row, geo.list.col, geo.list.w, geo.list.h, geo.list.border),
		backdrop = ui.backdrop.create(config.backdrop),
	}
	if has_preview then
		instance.view.preview = ui.preview.create(geo.preview.row, geo.preview.col, geo.preview.w, geo.preview.h)
	end

	-- Match pipeline loads items immediately; stream waits for user input
	-- Initial load if 'load' is defined
	if pipeline.load ~= nil then
		pipeline.load(instance)
	end

	return instance
end

function M:reset()
	if self.closed then
		return
	end
	-- Mark closed up front. Closing the windows below synchronously fires
	-- WinEnter/WinClosed autocmds that call reset() again; the guard above
	-- turns those re-entrant calls into no-ops so M.view is not nilled mid-cleanup.
	self.closed = true
	if self.on_close then
		self.on_close()
	end
	if self.view then
		require("beast.libs.finder.ui.input").stop_spinner(self.view.input)
		self.view.input:close()
		self.view.list:close()
		if self.view.preview then
			self.view.preview:close()
		end
		if self.view.backdrop then
			self.view.backdrop:close()
		end
	end
	self.pipeline.abort(self.query)
	if self.query then
		require("beast.libs.finder.render").cleanup(self.query)
	end
	if self.main_win and vim.api.nvim_win_is_valid(self.main_win) then
		vim.api.nvim_set_current_win(self.main_win)
	end
	if self.augroup then
		vim.api.nvim_del_augroup_by_id(self.augroup)
	end
	instance = nil
end

function M:relayout()
  -- stylua: ignore
  if not self.view then return end

	local geo = require("beast.libs.finder.layout").calc(self.view.preview ~= nil)

	-- Reposition backdrop
	if self.view.backdrop:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.backdrop.win, {
			relative = "editor",
			width = vim.o.columns,
			height = vim.o.lines,
			row = 0,
			col = 0,
		})
	end

	-- Reposition input
	if self.view.input:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.input.win, {
			relative = "editor",
			width = geo.input.w,
			height = geo.input.h,
			row = geo.input.row,
			col = geo.input.col,
		})
	end

	-- Reposition list
	if self.view.list:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.list.win, {
			relative = "editor",
			width = geo.list.w,
			height = geo.list.h,
			row = geo.list.row,
			col = geo.list.col,
		})
	end

	-- Reposition preview
	if self.view.preview and self.view.preview:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.view.preview.win, {
			relative = "editor",
			width = geo.preview.w,
			height = geo.preview.h,
			row = geo.preview.row,
			col = geo.preview.col,
		})
	end
end

return M
