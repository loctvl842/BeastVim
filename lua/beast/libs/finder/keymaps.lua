local action = require("beast.libs.finder.action")
local config = require("beast.libs.finder.config")
local match_hl = require("beast.libs.finder.match_hl")
local ui = require("beast.libs.finder.ui")

local M = {}

---@param query Beast.Finder.Query
---@param delta integer positive = down, negative = up
local function move_cursor(query, delta)
	local old_offset = query.list_view._offset
	ui.list.move(query.list_view, delta)
	-- Re-apply match highlights when viewport scrolled to new rows
	if query.list_view._offset ~= old_offset and not query._live and query.list_view:is_valid() then
		local format_fn = require("beast.libs.finder.format")[query.source] or require("beast.libs.finder.format").filename
		local from, to = ui.list.visible_range(query.list_view)
		match_hl.apply_list(query.list_view.buf, query.matched, format_fn, from, to)
	end
	vim.cmd("redraw")
	query:schedule_preview()
end

-- -----------------------------------------------------------------------
-- List window keymaps
-- -----------------------------------------------------------------------
---@param query Beast.Finder.Query
local function mount_list_keymaps(query)
  -- stylua: ignore
  if not query.list_view:is_valid() then return end

	local lbuf = query.list_view.buf
	local lopts = { buffer = lbuf, nowait = true }

  -- stylua: ignore
  local function lmap(mode, lhs, fn) vim.keymap.set(mode, lhs, fn, lopts) end

	-- Focus navigation between finder panes
	lmap("n", "<C-h>", function()
		vim.api.nvim_set_current_win(query.input_view.win)
		vim.cmd("startinsert!")
	end)
	lmap("n", "<C-j>", function()
		move_cursor(query, 1)
	end)
	lmap("n", "<C-k>", function()
		move_cursor(query, -1)
	end)
	lmap("n", "<C-l>", function()
		if query.preview_view and query.preview_view:is_valid() then
			vim.api.nvim_set_current_win(query.preview_view.win)
		end
	end)

	-- Special keys (non-printable)
  -- stylua: ignore start
	lmap("n", "<C-n>", function() move_cursor(query, 1) end)
	lmap("n", "<C-p>", function() move_cursor(query, -1) end)
	lmap("n", "<Down>", function() move_cursor(query, 1) end)
	lmap("n", "<Up>", function() move_cursor(query, -1) end)
  lmap("n", "<Tab>", function() move_cursor(query, 1) end)
  lmap("n", "<S-Tab>", function() move_cursor(query, -1) end)
	-- Close
	lmap({ "i", "n" }, "<Esc>", function() query:close() end)
	lmap({ "i", "n" }, "<C-c>", function() query:close() end)
	-- stylua: ignore end

	lmap("n", "<CR>", function()
		local item = ui.list.selected(query.list_view)
		if item then
			query:close()
			action.open(query, item)
		end
	end)

	-- Open in split / vsplit
	lmap({ "i", "n" }, "<C-s>", function()
		local item = ui.list.selected(query.list_view)
		if item then
			query:close()
			action.open_split(query, item)
		end
	end)
	lmap({ "i", "n" }, "<C-v>", function()
		local item = ui.list.selected(query.list_view)
		if item then
			query:close()
			action.open_vsplit(query, item)
		end
	end)

	-- Every printable char redirects to input and feeds the char
	local ASCII_PRINTABLE_START = string.byte(" ")
	local ASCII_PRINTABLE_END = string.byte("~")
	for byte = ASCII_PRINTABLE_START, ASCII_PRINTABLE_END do
		local char = string.char(byte)
		lmap("n", char, function()
			vim.api.nvim_set_current_win(query.input_view.win)
			vim.cmd("startinsert!")
			vim.api.nvim_feedkeys(char, "n", false)
		end)
	end
	-- Disable visual mode
	lmap("n", "v", function() end)
	lmap("n", "V", function() end)
end

---@param query Beast.Finder.Query
local function mount_preview_keymaps(query)
  -- stylua: ignore
  if not query.preview_view or not query.preview_view:is_valid() then return end
	local pbuf = query.preview_view.buf
	local popts = { buffer = pbuf, nowait = true }
	-- stylua: ignore
	local function pmap(mode, lhs, fn)
		vim.keymap.set(mode, lhs, fn, popts)
	end

	pmap("n", "<Esc>", function()
		query:close()
	end)

	-- Focus navigation between finder panes
	pmap("n", "<C-h>", function()
		vim.api.nvim_set_current_win(query.input_view.win)
		vim.cmd("startinsert!")
	end)
	pmap("n", "<C-j>", function()
		move_cursor(query, 1)
	end)
	pmap("n", "<C-k>", function()
		move_cursor(query, -1)
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
			vim.api.nvim_set_current_win(query.input_view.win)
			vim.cmd("startinsert!")
			if key ~= "/" then
				vim.api.nvim_feedkeys(key, "n", false)
			end
		end)
	end

	-- Block <leader> from triggering global mappings — redirect to input
	pmap("n", "<leader>", function()
		vim.api.nvim_set_current_win(query.input_view.win)
		vim.cmd("startinsert!")
	end)
end

---@param query Beast.Finder.Query
function M.mount(query)
	local buf = query.input_view.buf

	local opts = { buffer = buf, nowait = true }

  -- stylua: ignore
	local function map(mode, lhs, fn) vim.keymap.set(mode, lhs, fn, opts) end

	-- Navigation
  -- stylua: ignore start
	map({ "i", "n" }, "<C-j>", function() move_cursor(query, 1) end)
	map({ "i", "n" }, "<C-k>", function() move_cursor(query, -1) end)
	map({ "i", "n" }, "<C-n>", function() move_cursor(query, 1) end)
	map({ "i", "n" }, "<C-p>", function() move_cursor(query, -1) end)
	map({ "i", "n" }, "<Down>", function() move_cursor(query, 1) end)
	map({ "i", "n" }, "<Up>", function() move_cursor(query, -1) end)
	map({ "i", "n" }, "<Tab>", function() move_cursor(query, 1) end)
	map({ "i", "n" }, "<S-Tab>", function() move_cursor(query, -1) end)
	-- Close
	map({ "i", "n" }, "<Esc>", function() query:close() end)
	map({ "i", "n" }, "<C-c>", function() query:close() end)
	-- stylua: ignore end

	-- Confirm
	map({ "i", "n" }, "<CR>", function()
		local item = ui.list.selected(query.list_view)
		if item then
			query:close()
			action.open(query, item)
		end
	end)

	-- Open in split / vsplit
	map({ "i", "n" }, "<C-s>", function()
		local item = ui.list.selected(query.list_view)
		if item then
			query:close()
			action.open_split(query, item)
		end
	end)
	map({ "i", "n" }, "<C-v>", function()
		local item = ui.list.selected(query.list_view)
		if item then
			query:close()
			action.open_vsplit(query, item)
		end
	end)
	-- Copy path
	map({ "i", "n" }, "<C-y>", function()
		local item = ui.list.selected(query.list_view)
		if item then
			action.copy_path(item)
		end
	end)

	-- Focus navigation between finder panes (traps C-h/j/k/l inside finder)
	map({ "i", "n" }, "<C-h>", function() end) -- no-op: nothing to the left of input
	map({ "i", "n" }, "<C-l>", function()
		if query.preview_view and query.preview_view:is_valid() then
			vim.api.nvim_set_current_win(query.preview_view.win)
		end
	end)

	mount_list_keymaps(query)
	mount_preview_keymaps(query)
end

return M
