local actions = require("beast.libs.finder.actions")
local backdrop_ui = require("beast.libs.finder.ui.backdrop")
local config = require("beast.libs.finder.config")
local filter_mod = require("beast.libs.finder.filter")
local format = require("beast.libs.finder.format")
local input_ui = require("beast.libs.finder.ui.input")
local list_ui = require("beast.libs.finder.ui.list")
local match_hl = require("beast.libs.finder.ui.match_hl")
local matcher = require("beast.libs.finder.matcher")
local preview_ui = require("beast.libs.finder.ui.preview")

---@class Beast.Finder.Item
---@field idx number
---@field score number
---@field text string
---@field file? string
---@field buf? number
---@field pos? {[1]: number, [2]: number}
---@field cwd? string

---@class Beast.Finder.Picker
---@field filter Beast.Finder.Filter
---@field items Beast.Finder.Item[]
---@field matched Beast.Finder.Item[]
---@field input_view Beast.Finder.InputView
---@field list_view Beast.Finder.ListView
---@field preview_view Beast.Finder.PreviewView|nil
---@field main_win integer
---@field _backdrop_win integer|nil
---@field _preview_timer integer|nil
---@field _source_done boolean
---@field _batch_pending Beast.Finder.Item[]

local Picker = {}
Picker.__index = Picker

-- ---------------------------------------------------------------------------
-- Source registry
-- ---------------------------------------------------------------------------

local SOURCES = {
	files = require("beast.libs.finder.sources.files"),
	buffers = require("beast.libs.finder.sources.buffers"),
	live_grep = require("beast.libs.finder.sources.grep"),
	colorschemes = require("beast.libs.finder.sources.colorschemes"),
}

-- ---------------------------------------------------------------------------
-- Cursor hiding (same pattern as explorer)
-- ---------------------------------------------------------------------------

local HIDDEN_CURSOR = "a:block-BeastFinderListCursor"
local saved_guicursor = nil
local cursor_hidden = false

local function hide_cursor()
	-- stylua: ignore
	if cursor_hidden then return end
	if saved_guicursor == nil then
		saved_guicursor = vim.o.guicursor
	end
	vim.o.guicursor = HIDDEN_CURSOR
	cursor_hidden = true
end

local function restore_cursor()
	-- stylua: ignore
	if not cursor_hidden then return end
	if saved_guicursor ~= nil then
		vim.o.guicursor = saved_guicursor
		saved_guicursor = nil
	end
	cursor_hidden = false
end

-- ---------------------------------------------------------------------------
-- Layout geometry
-- ---------------------------------------------------------------------------

---@return table layout {input, list, preview?} window configs
---@param no_preview? boolean
local function calc_layout(no_preview)
	local total_w = math.floor(vim.o.columns * config.width)
	local total_h = math.floor(vim.o.lines * config.height)
	local top = math.floor((vim.o.lines - total_h) / 2)
	local left = math.floor((vim.o.columns - total_w) / 2)

	if no_preview then
		-- Single column: no preview pane
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

local function schedule_preview(picker)
	if picker._preview_timer then
		vim.fn.timer_stop(picker._preview_timer)
	end
	picker._preview_timer = vim.fn.timer_start(config.debounce.preview_ms, function()
		picker._preview_timer = nil
		local item = list_ui.selected(picker.list_view)
		if item then
			if picker.preview_view then
				preview_ui.show(picker.preview_view, item)
				-- Apply match highlights on preview for live sources (grep)
				if picker._live and picker.preview_view:is_valid() and picker.filter.pattern ~= "" then
					match_hl.apply_preview(picker.preview_view.buf, picker.filter.pattern)
					vim.cmd("redraw")
				end
			end
			if picker._on_preview then
				picker._on_preview(item)
			end
		else
			if picker.preview_view then
				preview_ui.clear(picker.preview_view)
			end
		end
	end)
end

local function render(picker)
	local format_fn = picker._format_fn or format.filename
	list_ui.render(picker.list_view, picker.matched, format_fn)
	-- Apply fuzzy match highlights to list (only for non-live sources)
	if not picker._live and picker.list_view:is_valid() then
		match_hl.apply_list(picker.list_view.buf, picker.matched, format_fn)
	end
	schedule_preview(picker)
	vim.cmd("redraw")
end

local function rematch(picker)
	matcher.run(picker.items, picker.filter, config.matcher, function(matched)
		picker.matched = matched
		render(picker)
	end)
end

-- Flush a pending batch of items from the source
local function flush_batch(picker)
	if #picker._batch_pending == 0 then
		return
	end
	local batch = picker._batch_pending
	picker._batch_pending = {}
	for _, item in ipairs(batch) do
		picker.items[#picker.items + 1] = item
	end
	if picker._live then
		-- Live sources are pre-filtered — render directly without matcher
		picker.matched = picker.items
		render(picker)
	else
		rematch(picker)
	end
end

--- Re-run a live source (e.g. grep) with the current filter pattern
local function reload_live(picker)
	local source = SOURCES[picker._source]
	-- stylua: ignore
	if not source then return end

	-- Cancel any in-flight process
	if source.cancel then
		source.cancel()
	end

	-- Empty query → clear results
	if picker.filter.pattern == "" then
		picker.items = {}
		picker.matched = {}
		picker._source_done = true
		picker._batch_pending = {}
		render(picker)
		return
	end

	picker.items = {}
	picker.matched = {}
	picker._source_done = false
	picker._batch_pending = {}

	source.get(picker.filter, function(item)
		if item == nil then
			picker._source_done = true
			vim.schedule(function()
				flush_batch(picker)
			end)
			return
		end
		picker._batch_pending[#picker._batch_pending + 1] = item
		if #picker._batch_pending >= 100 then
			flush_batch(picker)
		end
	end)
end

local function move_cursor(picker, delta)
	local old_cursor = picker.list_view.cursor
	list_ui.move(picker.list_view, delta)
	if old_cursor ~= picker.list_view.cursor then
		vim.cmd("redraw")
	end
	schedule_preview(picker)
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

local function mount_keymaps(picker)
	local buf = picker.input_view.buf
	local opts = { buffer = buf, nowait = true }

	local function map(mode, lhs, fn)
		vim.keymap.set(mode, lhs, fn, opts)
	end

	-- Navigation
	map({ "i", "n" }, "<C-j>", function()
		move_cursor(picker, 1)
	end)
	map({ "i", "n" }, "<C-k>", function()
		move_cursor(picker, -1)
	end)
	map({ "i", "n" }, "<C-n>", function()
		move_cursor(picker, 1)
	end)
	map({ "i", "n" }, "<C-p>", function()
		move_cursor(picker, -1)
	end)
	map({ "i", "n" }, "<Down>", function()
		move_cursor(picker, 1)
	end)
	map({ "i", "n" }, "<Up>", function()
		move_cursor(picker, -1)
	end)

	-- Confirm
	map({ "i", "n" }, "<CR>", function()
		local selected = list_ui.get_selected(picker.list_view)
		if #selected > 0 then
			picker:close()
			local action = picker._action or actions.open
			action(picker, selected)
		end
	end)

	-- Multi-selection
	map({ "i", "n" }, "<Tab>", function()
		list_ui.toggle_selection(picker.list_view)
		list_ui.move(picker.list_view, 1)
	end)
	map({ "i", "n" }, "<S-Tab>", function()
		list_ui.toggle_selection(picker.list_view)
		list_ui.move(picker.list_view, -1)
	end)

	-- Close
	map({ "i", "n" }, "<Esc>", function()
		picker:close()
	end)
	map({ "i", "n" }, "<C-c>", function()
		picker:close()
	end)

	-- Open in split / vsplit
	map({ "i", "n" }, "<C-s>", function()
		local item = list_ui.selected(picker.list_view)
		if item then
			picker:close()
			actions.open_split(picker, { item })
		end
	end)
	map({ "i", "n" }, "<C-v>", function()
		local item = list_ui.selected(picker.list_view)
		if item then
			picker:close()
			actions.open_vsplit(picker, { item })
		end
	end)

	-- Copy path
	map({ "i", "n" }, "<C-y>", function()
		local item = list_ui.selected(picker.list_view)
		if item then
			actions.copy_path(picker, { item })
		end
	end)

	-- Focus navigation between finder panes (traps C-h/j/k/l inside finder)
	map({ "i", "n" }, "<C-h>", function() end) -- no-op: nothing to the left of input
	map({ "i", "n" }, "<C-l>", function()
		if picker.preview_view and picker.preview_view:is_valid() then
			vim.api.nvim_set_current_win(picker.preview_view.win)
		end
	end)

	-- -----------------------------------------------------------------------
	-- List window keymaps
	-- -----------------------------------------------------------------------
	local function mount_list_keymaps()
		-- stylua: ignore
		if not picker.list_view:is_valid() then return end
		local lbuf = picker.list_view.buf
		local lopts = { buffer = lbuf, nowait = true }
		local function lmap(mode, lhs, fn)
			vim.keymap.set(mode, lhs, fn, lopts)
		end

		-- Focus navigation between finder panes
		lmap("n", "<C-h>", function()
			vim.api.nvim_set_current_win(picker.input_view.win)
			vim.cmd("startinsert!")
		end)
		lmap("n", "<C-j>", function()
			move_cursor(picker, 1)
		end)
		lmap("n", "<C-k>", function()
			move_cursor(picker, -1)
		end)
		lmap("n", "<C-l>", function()
			if picker.preview_view and picker.preview_view:is_valid() then
				vim.api.nvim_set_current_win(picker.preview_view.win)
			end
		end)
		lmap("n", "<C-c>", function()
			picker:close()
		end)

		-- Special keys (non-printable)
		lmap("n", "<C-n>", function()
			move_cursor(picker, 1)
		end)
		lmap("n", "<C-p>", function()
			move_cursor(picker, -1)
		end)
		lmap("n", "<Down>", function()
			move_cursor(picker, 1)
		end)
		lmap("n", "<Up>", function()
			move_cursor(picker, -1)
		end)
		lmap("n", "<CR>", function()
			local selected = list_ui.get_selected(picker.list_view)
			if #selected > 0 then
				picker:close()
				local action = picker._action or actions.open
				action(picker, selected)
			end
		end)
		lmap("n", "<Tab>", function()
			list_ui.toggle_selection(picker.list_view)
			list_ui.move(picker.list_view, 1)
		end)
		lmap("n", "<S-Tab>", function()
			list_ui.toggle_selection(picker.list_view)
			list_ui.move(picker.list_view, -1)
		end)
		lmap("n", "<Esc>", function()
			picker:close()
		end)
		lmap("n", "<C-s>", function()
			local item = list_ui.selected(picker.list_view)
			if item then
				picker:close()
				actions.open_split(picker, { item })
			end
		end)
		lmap("n", "<C-v>", function()
			local item = list_ui.selected(picker.list_view)
			if item then
				picker:close()
				actions.open_vsplit(picker, { item })
			end
		end)

		-- Every printable char redirects to input and feeds the char
		for byte = 32, 126 do
			local char = string.char(byte)
			lmap("n", char, function()
				vim.api.nvim_set_current_win(picker.input_view.win)
				vim.cmd("startinsert!")
				vim.api.nvim_feedkeys(char, "n", false)
			end)
		end

		-- Disable visual mode
		lmap("n", "v", function() end)
		lmap("n", "V", function() end)
	end

	-- -----------------------------------------------------------------------
	-- Preview window keymaps
	-- -----------------------------------------------------------------------
	local function mount_preview_keymaps()
		-- stylua: ignore
		if not picker.preview_view or not picker.preview_view:is_valid() then return end
		local pbuf = picker.preview_view.buf
		local popts = { buffer = pbuf, nowait = true }
		local function pmap(mode, lhs, fn)
			vim.keymap.set(mode, lhs, fn, popts)
		end

		pmap("n", "<Esc>", function()
			picker:close()
		end)

		-- Focus navigation between finder panes
		pmap("n", "<C-h>", function()
			vim.api.nvim_set_current_win(picker.input_view.win)
			vim.cmd("startinsert!")
		end)
		pmap("n", "<C-j>", function()
			move_cursor(picker, 1)
		end)
		pmap("n", "<C-k>", function()
			move_cursor(picker, -1)
		end)
		pmap("n", "<C-l>", function() end) -- no-op: nothing to the right of preview

		-- Insert/modify keys redirect to input and feed the char
		local redirect_keys = {
			"i",
			"I",
			"a",
			"A",
			"o",
			"O",
			"s",
			"S",
			"c",
			"C",
			"r",
			"R",
			"x",
			"X",
			"d",
			"D",
			"p",
			"P",
			"/",
		}
		for _, key in ipairs(redirect_keys) do
			pmap("n", key, function()
				vim.api.nvim_set_current_win(picker.input_view.win)
				vim.cmd("startinsert!")
				if key ~= "/" then
					vim.api.nvim_feedkeys(key, "n", false)
				end
			end)
		end

		-- Block <leader> from triggering global mappings — redirect to input
		pmap("n", "<leader>", function()
			vim.api.nvim_set_current_win(picker.input_view.win)
			vim.cmd("startinsert!")
		end)
	end

	mount_list_keymaps()
	mount_preview_keymaps()
end

-- ---------------------------------------------------------------------------
-- Source loading
-- ---------------------------------------------------------------------------

local function load_items(picker)
	-- Pre-loaded items (e.g. vim.ui.select)
	if picker._preloaded_items then
		picker.items = picker._preloaded_items
		picker._source_done = true
		rematch(picker)
		return
	end

	local source = SOURCES[picker._source]
	if not source then
		vim.notify("beast.finder: unknown source '" .. picker._source .. "'", vim.log.levels.ERROR)
		return
	end

	-- Async sources have source.async = true
	-- Live sources wait for user input before loading
	if source.live then
		picker.items = {}
		picker._source_done = true
		return
	elseif source.async then
		picker.items = {}
		picker._source_done = false
		picker._batch_pending = {}

		source.get(picker.filter, function(item)
			if item == nil then
				picker._source_done = true
				vim.schedule(function()
					flush_batch(picker)
				end)
				return
			end
			picker._batch_pending[#picker._batch_pending + 1] = item
			if #picker._batch_pending >= 100 then
				flush_batch(picker)
			end
		end)
	else
		-- Synchronous sources (buffers)
		local result = source.get(picker.filter)
		picker.items = result or {}
		picker._source_done = true
		rematch(picker)
	end
end

-- ---------------------------------------------------------------------------
-- Constructor / public methods
-- ---------------------------------------------------------------------------

---@param source_name string "files"|"buffers"|"live_grep"
---@param opts? {cwd?: string, action?: fun(picker:table, items:table[])}
---@return Beast.Finder.Picker
function Picker.new(source_name, opts)
	opts = opts or {}

	local source = SOURCES[source_name]
	local is_live = source and source.live or false

	local self = setmetatable({}, Picker)
	self.main_win = vim.api.nvim_get_current_win()
	self._source = source_name
	self._action = opts.action
	self._on_preview = opts.on_preview -- called with item on cursor move
	self._on_close = opts.on_close -- called on close (cancel or confirm)
	self._source_done = false
	self._batch_pending = {}
	self._preloaded_items = opts._items or nil
	self._live = is_live

	-- Pick format function based on source type
	if opts._format_fn then
		self._format_fn = opts._format_fn
	elseif source_name == "buffers" then
		self._format_fn = format.buffer
	elseif source_name == "live_grep" then
		self._format_fn = format.grep
	elseif source_name == "colorschemes" then
		self._format_fn = format.colorscheme
	else
		self._format_fn = format.filename
	end

	self.items = {}
	self.matched = {}
	self.filter = filter_mod.new({ cwd = opts.cwd })

	-- Backdrop must open before picker windows (lower zindex)
	self._backdrop_win = backdrop_ui.create(config.zindex)

	local no_preview = opts.no_preview or false
	self._no_preview = no_preview
	local layout = calc_layout(no_preview)

	if not no_preview then
		self.preview_view = preview_ui.create(layout.preview.row, layout.preview.col, layout.preview.w, layout.preview.h)
	end

	self.list_view = list_ui.create(layout.list.row, layout.list.col, layout.list.w, layout.list.h, layout.list.border)

	local title_name = source_name:gsub("_", " ")
	local title = title_name:sub(1, 1):upper() .. title_name:sub(2)
	local input_debounce = is_live and config.debounce.live_ms or nil
	self.input_view = input_ui.create(function(text)
		filter_mod.update(self.filter, text)
		if is_live then
			reload_live(self)
		else
			rematch(self)
		end
	end, layout.input.w, layout.input.h, layout.input.row, layout.input.col, title, input_debounce, layout.input.border)

	mount_keymaps(self)
	load_items(self)

	-- Autocmds augroup for picker lifetime
	self._augroup = vim.api.nvim_create_augroup("BeastFinderPicker", { clear = true })

	-- Hide cursor when entering the list buffer
	vim.api.nvim_create_autocmd("BufEnter", {
		group = self._augroup,
		buffer = self.list_view.buf,
		callback = hide_cursor,
	})

	-- Restore cursor when leaving the list buffer
	vim.api.nvim_create_autocmd("BufLeave", {
		group = self._augroup,
		buffer = self.list_view.buf,
		callback = restore_cursor,
	})

	-- Sync view.cursor when user moves cursor natively in the list window
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = self._augroup,
		buffer = self.list_view.buf,
		callback = function()
			-- stylua: ignore
			if not self.list_view:is_valid() then return end
			local row = vim.api.nvim_win_get_cursor(self.list_view.win)[1]
			if row ~= self.list_view.cursor then
				list_ui.set_cursor(self.list_view, row)
				vim.cmd("redraw")
				schedule_preview(self)
			end
		end,
	})

	-- Relayout on terminal resize
	vim.api.nvim_create_autocmd("VimResized", {
		group = self._augroup,
		callback = function()
			self:relayout()
		end,
	})

	-- Close when focus moves to a window outside the finder
	vim.api.nvim_create_autocmd("WinEnter", {
		group = self._augroup,
		callback = function()
			local current = vim.api.nvim_get_current_win()
			local finder_wins = {
				self.input_view.win,
				self.list_view.win,
			}
			if self.preview_view then
				finder_wins[#finder_wins + 1] = self.preview_view.win
			end
			for _, w in ipairs(finder_wins) do
				if current == w then
					return
				end
			end
			self:close()
		end,
	})

	return self
end

function Picker:close()
	restore_cursor()
	if self._on_close then
		self._on_close()
	end
	if self._augroup then
		vim.api.nvim_del_augroup_by_id(self._augroup)
		self._augroup = nil
	end
	if self._preview_timer then
		vim.fn.timer_stop(self._preview_timer)
		self._preview_timer = nil
	end
	-- Cancel any running live source process
	local source = SOURCES[self._source]
	if source and source.cancel then
		source.cancel()
	end
	if self.input_view._timer then
		vim.fn.timer_stop(self.input_view._timer)
		self.input_view._timer = nil
	end
	if self.preview_view then
		self.preview_view:close()
	end
	self.list_view:close()
	self.input_view:close()
	backdrop_ui.close(self._backdrop_win)
	self._backdrop_win = nil
	if self.main_win and vim.api.nvim_win_is_valid(self.main_win) then
		vim.api.nvim_set_current_win(self.main_win)
	end
end

function Picker:relayout()
	local layout = calc_layout(self._no_preview)

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

return Picker
