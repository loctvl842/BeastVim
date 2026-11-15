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
---@field on_close? fun(confirmed: boolean)
---@field confirmed? boolean the picker is closing because the user confirmed an item (Enter)
---@field layout? "cards"
---@field initial_text? string
---@field initial_done? boolean the initial selection has been applied
---@field initial_query? string prompt text the source opened with, searched already; the first change event for the same text is skipped
---@field frozen? boolean panels use frozen highlight namespaces
---@field host Beast.Finder.Host what the pipelines may ask of this picker's windows
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
---@field on_close? fun(confirmed: boolean) called as the picker closes; `confirmed` is true after Enter
---@field preview? boolean preview window enabled
---@field layout? "cards" separate prompt/list boxes
---@field separators? boolean separator rows between list items
---@field backdrop? boolean false skips the dimming overlay (default true)
---@field initial_text? string start with the item whose text matches selected (instead of the first one)
---@field freeze_colors? boolean keep the panels in the colors they had at open, ignoring `:colorscheme`

--- The pipelines' only way to reach this picker (see host.lua).
---@param state Beast.Finder.State
---@return Beast.Finder.Host
local function make_host(state)
	local render = require("beast.libs.finder.render")
	return {
		alive = function()
			return not state.closed and state.view ~= nil and state.view.list:is_valid()
		end,
		render = function()
			render.render(state)
		end,
		busy = function(on)
			if on then
				ui.input.start_spinner(state.view.input)
			else
				ui.input.stop_spinner(state.view.input)
			end
		end,
		rewind = function()
			state.view.list.cursor = 1
			state.view.list._offset = 0
		end,
		count = function(text)
			ui.input.set_count(state.view.input, text)
		end,
		title = function(text)
			-- The cards layout has no title.
			if state.layout ~= "cards" then
				ui.input.set_title(state.view.input, text)
			end
		end,
		rows = function()
			return state.view.list._win_height or 50
		end,
	}
end

---@param source_name Beast.Finder.Source
---@param opts? Beast.Finder.Opts
function M:new(source_name, opts)
	if instance then
		instance:reset()
	end
	opts = opts or {}
	local source = source_registry[source_name]
	local query = Query(source, { cwd = opts.cwd, preloaded_items = opts.preloaded_items })
	local is_live = source.live
	---@type Beast.Finder.Pipeline.Match|Beast.Finder.Pipeline.Stream
	local pipeline = is_live and pipeline_registry.stream or pipeline_registry.match

	instance = setmetatable({
		closed = false,
		main_win = View.win.find_normal(),
		on_preview = opts.on_preview,
		on_close = opts.on_close,
		layout = opts.layout,
		initial_text = opts.initial_text,
		frozen = opts.freeze_colors,
		query = query,
		pipeline = pipeline,
	}, self)

	-- View
	local has_preview = opts.preview ~= false
	local geo = require("beast.libs.finder.layout").calc(has_preview, opts.layout)
	local title_name = source_name:gsub("_", " ")
	local title = opts.layout == "cards" and "" or title_name:sub(1, 1):upper() .. title_name:sub(2)
	if source.title and opts.layout ~= "cards" then
		title = source.title()
	end
	local input_debounce = source.debounce_ms or (is_live and config.debounce.live_ms or nil)
	local initial_query = is_live and source.initial_query or nil
	local frozen = opts.freeze_colors and require("beast.libs.finder.highlights").freeze() or nil

	instance.view = {
		input = ui.input.create(function(text)
			-- Prefilling the prompt can echo back as a change event; the search for it already ran.
			if instance.initial_query and text == instance.initial_query then
				instance.initial_query = nil
				return
			end
			instance.initial_query = nil
			query.filter:update(text)
			pipeline.run(query, instance.host)
		end, geo.input.w, geo.input.h, geo.input.row, geo.input.col, title, input_debounce, geo.input.border, opts.layout == "cards", initial_query),
		list = ui.list.create(geo.list.row, geo.list.col, geo.list.w, geo.list.h, geo.list.border, opts.separators),
		backdrop = opts.backdrop ~= false and ui.backdrop.create(config.backdrop) or nil,
	}
	if frozen then
		vim.api.nvim_win_set_hl_ns(instance.view.input.win, frozen.input)
		vim.api.nvim_win_set_hl_ns(instance.view.list.win, frozen.list)
	end
	if has_preview then
		instance.view.preview = ui.preview.create(geo.preview.row, geo.preview.col, geo.preview.w, geo.preview.h)
	end

	instance.host = make_host(instance)

	-- Match pipeline loads items immediately; stream waits for user input, except a live
	-- source with a default query, which searches right away (the echo of that text in the
	-- prompt must not search again).
	instance.initial_query = initial_query
	pipeline.start(query, instance.host)

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
		self.on_close(self.confirmed == true)
	end
	if self.view then
		require("beast.libs.finder.ui.input").stop_spinner(self.view.input)
		-- Erase any inline image before closing windows: image.clear() clips its
		-- erase rect to the preview window's current bounds, so it must run while
		-- that window is still valid (Kitty placements persist past window close;
		-- no-op for the iTerm2 protocol).
		if self.view.preview and self.view.preview.loaded_image then
			require("beast.libs.image").clear()
		end
		self.view.input:close()
		self.view.list:close()
		if self.view.preview then
			self.view.preview:close()
		end
		if self.view.backdrop then
			self.view.backdrop:close()
		end
	end
	if self.frozen then
		require("beast.libs.finder.highlights").unfreeze()
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
	-- A reentrant open() from inside on_close() (or another callback run
	-- synchronously above) may have already installed a newer instance;
	-- don't clobber it.
	if instance == self then
		instance = nil
	end
end

function M:relayout()
  -- stylua: ignore
  if not self.view then return end

	local geo = require("beast.libs.finder.layout").calc(self.view.preview ~= nil, self.layout)

	-- Reposition backdrop
	if self.view.backdrop and self.view.backdrop:is_valid() then
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
		-- Re-draw the inline image (if any) at the new geometry; VimResized
		-- triggers a full repaint that would otherwise erase it.
		require("beast.libs.finder.ui.preview").refresh(self.view.preview)
	end

	-- Separator rows are as wide as the list window, so redraw them at the new width
	if self.view.list._separators then
		require("beast.libs.finder.render").render(self)
	end
end

return M
