local actions = require("beast.libs.finder.actions")
local backdrop_ui = require("beast.libs.finder.ui.backdrop")
local config = require("beast.libs.finder.config")
local filter_mod = require("beast.libs.finder.filter")
local format = require("beast.libs.finder.format")
local input_ui = require("beast.libs.finder.ui.input")
local list_ui = require("beast.libs.finder.ui.list")
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
---@field preview_view Beast.Finder.PreviewView
---@field main_win integer
---@field _backdrop_win integer|nil
---@field _preview_timer integer|nil
---@field _source_done boolean
---@field _batch_pending Beast.Finder.Item[]

local Picker = {}
Picker.__index = Picker

-- ---------------------------------------------------------------------------
-- Layout geometry
-- ---------------------------------------------------------------------------

---@return table layout {input, list, preview} window configs
local function calc_layout()
	local total_w = math.floor(vim.o.columns * config.width)
	local total_h = math.floor(vim.o.lines * config.height)
	local top = math.floor((vim.o.lines - total_h) / 2)
	local left = math.floor((vim.o.columns - total_w) / 2)

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
		input = { row = top, col = left, w = left_content_w, h = input_h },
		list = { row = top + 3, col = left, w = left_content_w, h = list_content_h },
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
			preview_ui.show(picker.preview_view, item)
		end
	end)
end

local function render(picker)
	local format_fn = picker._format_fn or format.filename
	list_ui.render(picker.list_view, picker.matched, format_fn)
	schedule_preview(picker)
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
	rematch(picker)
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
		list_ui.move(picker.list_view, 1)
		schedule_preview(picker)
	end)
	map({ "i", "n" }, "<C-k>", function()
		list_ui.move(picker.list_view, -1)
		schedule_preview(picker)
	end)
	map({ "i", "n" }, "<Down>", function()
		list_ui.move(picker.list_view, 1)
		schedule_preview(picker)
	end)
	map({ "i", "n" }, "<Up>", function()
		list_ui.move(picker.list_view, -1)
		schedule_preview(picker)
	end)

	-- Confirm
	map({ "i", "n" }, "<CR>", function()
		local item = list_ui.selected(picker.list_view)
		if item then
			picker:close()
			local action = picker._action or actions.open
			action(picker, { item })
		end
	end)

	-- Close
	map({ "i", "n" }, "<Esc>", function()
		picker:close()
	end)
	map({ "i", "n" }, "<C-c>", function()
		picker:close()
	end)

	-- Toggle preview
	map({ "i", "n" }, "<C-p>", function()
		preview_ui.toggle(picker.preview_view)
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
end

-- ---------------------------------------------------------------------------
-- Source loading
-- ---------------------------------------------------------------------------

local SOURCES = {
	files = require("beast.libs.finder.sources.files"),
	buffers = require("beast.libs.finder.sources.buffers"),
}

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

	-- Synchronous sources (buffers)
	local result = source.get(picker.filter)
	if type(result) == "table" then
		picker.items = result
		picker._source_done = true
		rematch(picker)
		return
	end

	-- Async source (files) — calls get(filter, cb)
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
end

-- ---------------------------------------------------------------------------
-- Constructor / public methods
-- ---------------------------------------------------------------------------

---@param source_name string "files"|"buffers"
---@param opts? {cwd?: string, action?: fun(picker:table, items:table[])}
---@return Beast.Finder.Picker
function Picker.new(source_name, opts)
	opts = opts or {}

	local self = setmetatable({}, Picker)
	self.main_win = vim.api.nvim_get_current_win()
	self._source = source_name
	self._action = opts.action
	self._source_done = false
	self._batch_pending = {}
	self._preloaded_items = opts._items or nil
	self._format_fn = opts._format_fn or (source_name == "buffers" and format.buffer or format.filename)
	self.items = {}
	self.matched = {}
	self.filter = filter_mod.new({ cwd = opts.cwd })

	-- Backdrop must open before picker windows (lower zindex)
	self._backdrop_win = backdrop_ui.create(config.zindex)

	local layout = calc_layout()

	self.preview_view = preview_ui.create(layout.preview.row, layout.preview.col, layout.preview.w, layout.preview.h)

	self.list_view = list_ui.create(layout.list.row, layout.list.col, layout.list.w, layout.list.h)

	self.input_view = input_ui.create(function(text)
		filter_mod.update(self.filter, text)
		rematch(self)
	end, layout.input.w, layout.input.h, layout.input.row, layout.input.col)

	mount_keymaps(self)
	load_items(self)

	return self
end

function Picker:close()
	if self._preview_timer then
		vim.fn.timer_stop(self._preview_timer)
		self._preview_timer = nil
	end
	self.preview_view:close()
	self.list_view:close()
	self.input_view:close()
	backdrop_ui.close(self._backdrop_win)
	self._backdrop_win = nil
	if self.main_win and vim.api.nvim_win_is_valid(self.main_win) then
		vim.api.nvim_set_current_win(self.main_win)
	end
end

return Picker
