local action = require("beast.libs.finder.action")
local match_hl = require("beast.libs.finder.match_hl")
local render = require("beast.libs.finder.render")
local ui = require("beast.libs.finder.ui")

local M = {}

---@param session Beast.Finder.Session
---@param delta integer positive = down, negative = up
local function move_cursor(session, delta)
	local old_offset = session.view.list._offset
	ui.list.move(session.view.list, delta)
	-- Re-apply match highlights when viewport scrolled to new rows
	if session.view.list._offset ~= old_offset and not session.level.query.source.live and session.view.list:is_valid() then
		local format_fn = render.formatters(session)
		local from, to = ui.list.visible_range(session.view.list)
		match_hl.apply_list(session.view.list.buf, session.level.query.matched, format_fn, from, to, session.view.list._separators and 2 or 1)
	end
	vim.cmd("redraw")
	render.schedule_preview(session)
end

-- -----------------------------------------------------------------------
-- List window keymaps
-- -----------------------------------------------------------------------
---@param session Beast.Finder.Session
local function mount_list_keymaps(session)
  -- stylua: ignore
  if not session.view.list:is_valid() then return end

	local lbuf = session.view.list.buf
	local lopts = { buffer = lbuf, nowait = true }

  -- stylua: ignore
  local function lmap(mode, lhs, fn) vim.keymap.set(mode, lhs, fn, lopts) end

	-- Focus navigation between finder panes
	lmap("n", "<C-h>", function()
		vim.api.nvim_set_current_win(session.view.input.win)
		vim.cmd("startinsert!")
	end)
	lmap("n", "<C-j>", function()
		move_cursor(session, 1)
	end)
	lmap("n", "<C-k>", function()
		move_cursor(session, -1)
	end)
	lmap("n", "<C-l>", function()
		if session.view.preview and session.view.preview:is_valid() then
			vim.api.nvim_set_current_win(session.view.preview.win)
		end
	end)

	-- Special keys (non-printable)
  -- stylua: ignore start
	lmap("n", "<C-n>", function() move_cursor(session, 1) end)
	lmap("n", "<C-p>", function() move_cursor(session, -1) end)
	lmap("n", "<Down>", function() move_cursor(session, 1) end)
	lmap("n", "<Up>", function() move_cursor(session, -1) end)
  lmap("n", "<Tab>", function() move_cursor(session, 1) end)
  lmap("n", "<S-Tab>", function() move_cursor(session, -1) end)
	-- Mouse wheel: drive selection (the buffer only holds the visible slice, so
	-- native scrolling reveals nothing — move the cursor to re-render instead).
	lmap("n", "<ScrollWheelDown>", function() move_cursor(session, 3) end)
	lmap("n", "<ScrollWheelUp>", function() move_cursor(session, -3) end)
	-- Close
	lmap({ "n" }, "<Esc>", function() session:close() end)
	lmap({ "i", "n" }, "<C-c>", function() session:close() end)
	-- stylua: ignore end

	lmap("n", "<CR>", function()
		local item = ui.list.selected(session.view.list)
		if item and not item.message then
			session.confirmed = true
			session:close()
			vim.schedule(function()
				action.open(session, item)
			end)
		end
	end)

	-- Open in split / vsplit
	lmap({ "i", "n" }, "<C-s>", function()
		local item = ui.list.selected(session.view.list)
		if item and item.file then
			session:close()
			vim.schedule(function()
				action.open_split(session.main_win, item)
			end)
		end
	end)
	lmap({ "i", "n" }, "<C-v>", function()
		local item = ui.list.selected(session.view.list)
		if item and item.file then
			session:close()
			vim.schedule(function()
				action.open_split(session.main_win, item)
			end)
		end
	end)

	-- Every printable char redirects to input and feeds the char
	local ASCII_PRINTABLE_START = string.byte(" ")
	local ASCII_PRINTABLE_END = string.byte("~")
	for byte = ASCII_PRINTABLE_START, ASCII_PRINTABLE_END do
		local char = string.char(byte)
		lmap("n", char, function()
			vim.api.nvim_set_current_win(session.view.input.win)
			vim.cmd("startinsert!")
			vim.api.nvim_feedkeys(char, "n", false)
		end)
	end
	-- Disable visual mode
	lmap("n", "v", function() end)
	lmap("n", "V", function() end)
end

---@param session Beast.Finder.Session
local function mount_preview_keymaps(session)
  -- stylua: ignore
  if not session.view.preview or not session.view.preview:is_valid() then return end
	local pbuf = session.view.preview.buf
	local popts = { buffer = pbuf, nowait = true }
	-- stylua: ignore
	local function pmap(mode, lhs, fn)
		vim.keymap.set(mode, lhs, fn, popts)
	end

	pmap("n", "<Esc>", function()
		session:close()
	end)

	-- Focus navigation between finder panes
	pmap("n", "<C-h>", function()
		vim.api.nvim_set_current_win(session.view.input.win)
		vim.cmd("startinsert!")
	end)
	pmap("n", "<C-j>", function()
		move_cursor(session, 1)
	end)
	pmap("n", "<C-k>", function()
		move_cursor(session, -1)
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
			vim.api.nvim_set_current_win(session.view.input.win)
			vim.cmd("startinsert!")
			if key ~= "/" then
				vim.api.nvim_feedkeys(key, "n", false)
			end
		end)
	end

	-- Block <leader> from triggering global mappings — redirect to input
	pmap("n", "<leader>", function()
		vim.api.nvim_set_current_win(session.view.input.win)
		vim.cmd("startinsert!")
	end)
end

---@param session Beast.Finder.Session
function M.mount(session)
	local buf = session.view.input.buf

	local opts = { buffer = buf, nowait = true }

  -- stylua: ignore
	local function map(mode, lhs, fn) vim.keymap.set(mode, lhs, fn, opts) end

	-- Navigation
  -- stylua: ignore start
	map({ "i", "n" }, "<C-j>", function() move_cursor(session, 1) end)
	map({ "i", "n" }, "<C-k>", function() move_cursor(session, -1) end)
	map({ "i", "n" }, "<C-n>", function() move_cursor(session, 1) end)
	map({ "i", "n" }, "<C-p>", function() move_cursor(session, -1) end)
	map({ "i", "n" }, "<Down>", function() move_cursor(session, 1) end)
	map({ "i", "n" }, "<Up>", function() move_cursor(session, -1) end)
	map({ "i", "n" }, "<Tab>", function() move_cursor(session, 1) end)
	map({ "i", "n" }, "<S-Tab>", function() move_cursor(session, -1) end)
	-- Mouse wheel: drive selection (virtual rendering — native scroll can't
	-- reveal off-screen items, so move the cursor to re-render).
	map({ "i", "n" }, "<ScrollWheelDown>", function() move_cursor(session, 3) end)
	map({ "i", "n" }, "<ScrollWheelUp>", function() move_cursor(session, -3) end)
	-- Close
	map({ "n" }, "<Esc>", function() session:close() end)
	map({ "i", "n" }, "<C-c>", function() session:close() end)
	-- stylua: ignore end

	-- Confirm
	map({ "i", "n" }, "<CR>", function()
		local item = ui.list.selected(session.view.list)
		if item and not item.message then
			session.confirmed = true
			session:close()
			vim.schedule(function()
				action.open(session, item)
			end)
		end
	end)

	-- Open in split / vsplit
	map({ "i", "n" }, "<C-s>", function()
		local item = ui.list.selected(session.view.list)
		if item and item.file then
			session:close()
			vim.schedule(function()
				action.open_split(session.main_win, item)
			end)
		end
	end)
	map({ "i", "n" }, "<C-v>", function()
		local item = ui.list.selected(session.view.list)
		if item and item.file then
			session:close()
			vim.schedule(function()
				action.open_vsplit(session.main_win, item)
			end)
		end
	end)
	-- Copy path
	map({ "i", "n" }, "<C-y>", function()
		local item = ui.list.selected(session.view.list)
		if item then
			action.copy_path(item)
		end
	end)

	-- Focus navigation between finder panes (traps C-h/j/k/l inside finder)
	map({ "i", "n" }, "<C-h>", function() end) -- no-op: nothing to the left of input
	map({ "i", "n" }, "<C-l>", function()
		if session.view.preview and session.view.preview:is_valid() then
			vim.api.nvim_set_current_win(session.view.preview.win)
		end
	end)

	mount_list_keymaps(session)
	mount_preview_keymaps(session)
end

return M
