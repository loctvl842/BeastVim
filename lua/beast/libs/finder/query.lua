local Filter = require("beast.libs.finder.filter")
local config = require("beast.libs.finder.config")
local format = require("beast.libs.finder.format")
local match_hl = require("beast.libs.finder.match_hl")
local matcher = require("beast.libs.finder.matcher")
local source_registry = require("beast.libs.finder.source")
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
---@field grep_text? string
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
---@field _live boolean
---@field _preview_timer uv.uv_timer_t|nil
---@field _batch_pending Beast.Finder.Item[]
---@field _augroup integer
---@field _on_preview? fun(item: Beast.Finder.Item)
---@field _on_close? fun()
---@field _match_state? Beast.Finder.MatchState
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})
M.__index = M

-- ---------------------------------------------------------------------------
-- Layout geometry
-- ---------------------------------------------------------------------------
---@class Beast.Finder.Layout.Geometry
---@field row integer
---@field col integer
---@field w integer
---@field h integer
---@field border? string[]

---@class Beast.Finder.Layout
---@field [string] Beast.Finder.Layout.Geometry

local function calc_layout(has_preview)
	local total_w = math.floor(vim.o.columns * config.width)
	local total_h = math.floor(vim.o.lines * config.height)
	local top = math.floor((vim.o.lines - total_h) / 2)
	local left = math.floor((vim.o.columns - total_w) / 2)

	if not has_preview then
		local content_w = total_w - 2 -- left + right border
		local input_h = 1
		local list_content_h = total_h - 4

		return {
			input = {
				row = top,
				col = left,
				w = content_w,
				h = input_h,
				border = { "╭", "─", "╮", "│", "┤", "─", "├", "│" },
			},
			list = {
				row = top + 3,
				col = left,
				w = content_w,
				h = list_content_h,
				border = { "", "", "", "│", "╯", "─", "╰", "│" },
			},
		}
	end

	-- Content widths (excluding borders)
	-- Left column gets (1 - preview_ratio) of the total content width
	-- Total content width = total_w - 3 (left border + middle separator + right border)
	local content_w = total_w - 3
	local left_content_w = math.floor(content_w * (1 - config.preview_ratio))
	local preview_content_w = content_w - left_content_w

	-- Vertical: total_h = top border + input(1) + separator + list content + bottom border
	-- total_h = 1 + 1 + 1 + list_h + 1 → list_h = total_h - 4
	local input_h = 1
	local list_content_h = total_h - 4
	-- Preview content = total_h - 2 (top + bottom border only)
	local preview_content_h = total_h - 2

	return {
		input = {
			row = top,
			col = left,
			w = left_content_w,
			h = input_h,
			border = { "╭", "─", "┬", "│", "┤", "─", "├", "│" },
		},
		list = {
			row = top + 3,
			col = left,
			w = left_content_w,
			h = list_content_h,
			border = { "", "", "", "│", "┘", "─", "╰", "│" },
		},
		preview = { row = top, col = left + left_content_w + 1, w = preview_content_w, h = preview_content_h },
	}
end

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------
function M:schedule_preview()
	if not self._preview_timer or self._preview_timer:is_closing() then
		self._preview_timer = assert(vim.uv.new_timer(), "failed to create preview timer")
	end

	self._preview_timer:stop()

	self._preview_timer:start(
		config.debounce.preview_ms,
		0,
		vim.schedule_wrap(function()
			-- stylua: ignore
			if not self.list_view:is_valid() then return end

			local item = ui.list.selected(self.list_view)

			if item then
				if self.preview_view then
					ui.preview.show(self.preview_view, item)

					-- Apply match highlights on preview for live sources (grep)
					if self._live and self.preview_view:is_valid() and self.filter.pattern ~= "" then
						match_hl.apply_preview(self.preview_view.buf, self.filter.pattern)
						vim.cmd("redraw")
					end
				end

				if self._on_preview then
					self._on_preview(item)
				end
			else
				if self.preview_view then
					ui.preview.clear(self.preview_view)
				end
			end
		end)
	)
end

---@param query Beast.Finder.Query
local function render(query)
	local format_fn = format[query.source] or format.filename
	ui.list.render(query.list_view, query.matched, format_fn)
	-- Apply fuzzy match highlights to list (only for non-live sources, only visible rows)
	if not query._live and query.list_view:is_valid() then
		local from, to = ui.list.visible_range(query.list_view)
		match_hl.apply_list(query.list_view.buf, query.matched, format_fn, from, to)
	end
	query:schedule_preview()
	vim.cmd("redraw")
end

--- Re-run a live source (e.g. grep) with the current filter pattern
---@param query Beast.Finder.Query
local function reload_live(query)
	local source = source_registry[query.source]
	-- stylua: ignore
	if not source then return end

	-- Cancel any in-flight process
	if source.cancel then
		source.cancel()
	end

	-- Empty query → clear results
	if query.filter.pattern == "" then
		query.items = {}
		query.matched = {}
		query._batch_pending = {}
		render(query)
		return
	end

	query.items = {}
	query.matched = {}
	query._batch_pending = {}

	source.get(query.filter, function(item)
		if item == nil then
			vim.schedule(function()
				query:flush_batch()
			end)
			return
		end
		query._batch_pending[#query._batch_pending + 1] = item
		if #query._batch_pending >= 100 then
			query:flush_batch()
		end
	end)
end

---@param query Beast.Finder.Query
local function rematch(query)
	matcher.run(query.items, query.filter, config.matcher, function(matched, state)
		query.matched = matched
		query._match_state = state
		render(query)
	end, query._match_state)
end

-- ---------------------------------------------------------------------------
-- Source loading
-- ---------------------------------------------------------------------------
function M:flush_batch()
  -- stylua: ignore
  if #self._batch_pending == 0 then return end

	local batch = self._batch_pending
	self._batch_pending = {}
	for _, item in ipairs(batch) do
		self.items[#self.items + 1] = item
	end
	-- New items arrived — previous match state is incomplete, force full rescan
	self._match_state = nil
	if self._live then
		-- Live sources are pre-filtered — render directly without matcher
		self.matched = self.items
		render(self)
	else
		rematch(self)
	end
end

---@private
function M:load()
	local source = source_registry[self.source]
	if not source then
		vim.notify("beast.libs.finder: unknown source '" .. self.source .. "'", vim.log.levels.ERROR)
		return
	end

	-- Async sources have source.async = true
	-- Live sources wait for user input before loading
	if source.live then
		self.items = {}
	elseif source.async then
		self.items = {}
		source.get(self.filter, function(item)
			if item == nil then
				vim.schedule(function()
					self:flush_batch()
				end)
				return
			end
			self._batch_pending[#self._batch_pending + 1] = item
			if #self._batch_pending > 100 then
				self:flush_batch()
			end
		end)
	else
		-- Synchronous sources (buffers, help_tags)
		local result = source.get(self.filter)
		self.items = result or {}
		rematch(self)
	end
end

-- ---------------------------------------------------------------------------
-- Constructor / public methods
-- ---------------------------------------------------------------------------
---@class Beast.Finder.QueryOpts
---@field cwd? string
---@field preview? boolean preview window enabled
---@field on_preview? fun(item: Beast.Finder.Item)
---@field on_close? fun()

---@param source_name Beast.Finder.Source
---@param opts? Beast.Finder.QueryOpts
---@return Beast.Finder.Query
function M:new(source_name, opts)
	opts = opts or {}

	local source = source_registry[source_name]
	local is_live = source and source.live or false

	local has_preview = opts.preview ~= false
	local layout = calc_layout(has_preview)
	self._on_preview = opts.on_preview -- called with item on cursor move
	self._on_close = opts.on_close -- called on close (cancel or confirm)

	local obj = setmetatable({
		items = {},
		matched = {},
		filter = Filter({ cwd = opts.cwd }),
		main_win = Util.find_normal_win(),
		source = source_name,
		_preview = has_preview,
		_live = is_live,
		_batch_pending = {},
	}, self)

	-- Backdrop must open before picker windows (lower zindex)
	self._backdrop_win = ui.backdrop.create(config.backdrop)

	local title_name = source_name:gsub("_", " ")
	local title = title_name:sub(1, 1):upper() .. title_name:sub(2)
	local input_debounce = is_live and config.debounce.live_ms or nil
	obj.input_view = ui.input.create(function(text)
		obj.filter:update(text)
		if is_live then
			reload_live(obj)
		else
			rematch(obj)
		end
	end, layout.input.w, layout.input.h, layout.input.row, layout.input.col, title, input_debounce, layout.input.border)

	obj.list_view = ui.list.create(layout.list.row, layout.list.col, layout.list.w, layout.list.h, layout.list.border)

	if has_preview then
		obj.preview_view = ui.preview.create(layout.preview.row, layout.preview.col, layout.preview.w, layout.preview.h)
	end

	require("beast.libs.finder.keymaps").mount(obj)
	require("beast.libs.finder.autocmds").mount(obj)
	return obj
end

function M:close()
	if self._on_close then
		self._on_close()
	end
	if self._augroup then
		vim.api.nvim_del_augroup_by_id(self._augroup)
		self._augroup = nil
	end
	if self._preview_timer then
		self._preview_timer:stop()
		self._preview_timer:close()
		self._preview_timer = nil
	end
	local source = source_registry[self.source]
	if source and source.cancel then
		source.cancel()
	end
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
	local layout = calc_layout(self._preview)

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
			width = layout.input.w,
			height = layout.input.h,
			row = layout.input.row,
			col = layout.input.col,
		})
	end

	-- Reposition list
	if self.list_view:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.list_view.win, {
			relative = "editor",
			width = layout.list.w,
			height = layout.list.h,
			row = layout.list.row,
			col = layout.list.col,
		})
	end

	-- Reposition preview
	if self.preview_view and self.preview_view:is_valid() then
		pcall(vim.api.nvim_win_set_config, self.preview_view.win, {
			relative = "editor",
			width = layout.preview.w,
			height = layout.preview.h,
			row = layout.preview.row,
			col = layout.preview.col,
		})
	end
end

return M
