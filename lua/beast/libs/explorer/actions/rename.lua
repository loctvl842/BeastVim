---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")

local uv = vim.uv or vim.loop
local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

--- Compute the display column where the node name begins on its explorer line.
--- Uses the last occurrence of node.name in the rendered line, so it still works
--- when the line contains extra suffixes like " (copy)" earlier in the text.
---@param node Beast.Explorer.Node
---@param node_line integer  -- 1-based buffer line
---@return integer           -- display-width columns before the name
local function name_col(node, node_line)
	local buf_lines = vim.api.nvim_buf_get_lines(state.view.buf, node_line - 1, node_line, false)
	local line = buf_lines[1] or ""
	local name = node.name or ""

	if name == "" then
		return vim.fn.strdisplaywidth(line)
	end

	-- Find the last plain occurrence of the node name.
	local last_start = nil
	local search_from = 1

	while true do
		local s = line:find(name, search_from, true)
		if not s then
			break
		end
		last_start = s
		search_from = s + 1
	end

	-- Fallback: if not found, return full line width.
	if not last_start then
		return vim.fn.strdisplaywidth(line)
	end

	-- Display width before the first character of the matched name.
	return vim.fn.strdisplaywidth(line:sub(1, last_start - 1))
end

--- Open an inline input float on top of the current node line, pre-filled
--- with the existing name, so the user can edit it in-place.
---@param node Beast.Explorer.Node
---@param node_line integer  1-based buffer line of the node
---@param on_done fun(old_path: string, new_path: string)
local function open_rename_popup(node, node_line, on_done)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end

	local exp_win = state.view.win
	local exp_width = vim.api.nvim_win_get_width(exp_win)

	local indent = name_col(node, node_line)
	local input_width = exp_width - indent - 1
	if input_width < 10 then
		input_width = exp_width - 2
		indent = 1
	end

	local input_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[input_buf].buftype = "nofile"
	vim.bo[input_buf].bufhidden = "wipe"

	-- Pre-fill with current name
	vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { node.name })

	local input_win = vim.api.nvim_open_win(input_buf, true, {
		relative = "win",
		win = exp_win,
		row = node_line - 1, -- 0-indexed
		col = indent,
		width = input_width,
		height = 1,
		style = "minimal",
		border = "none",
		zindex = 50,
	})

	vim.wo[input_win].cursorline = false
	vim.wo[input_win].number = false
	vim.wo[input_win].relativenumber = false
	vim.wo[input_win].signcolumn = "no"

	vim.cmd("startinsert!")

	local closed = false

	local function close_input()
    -- stylua: ignore
		if closed then return end
		closed = true
		vim.cmd("stopinsert")

		if vim.api.nvim_win_is_valid(input_win) then
			vim.api.nvim_win_close(input_win, true)
		end
		if state.view and state.view:is_valid() then
			pcall(vim.api.nvim_set_current_win, state.view.win)
		end
	end

	local function confirm()
		local lines = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)
		local input = (lines[1] or ""):match("^%s*(.-)%s*$") -- trim
		close_input()
		if not input or input == "" or input == node.name then
			return
		end
		if input:match("[%z\1-\31]") then
			vim.notify("Invalid name", vim.log.levels.ERROR)
			return
		end

		local parent_path = node.parent or vim.fs.dirname(node.path)
		local new_path = parent_path .. "/" .. input

		if uv.fs_stat(new_path) then
			vim.notify("Already exists: " .. input, vim.log.levels.WARN)
			return
		end

		local ok, err = uv.fs_rename(node.path, new_path)
		if not ok then
			vim.notify("Rename failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
			return
		end

		on_done(node.path, new_path)
	end

	local map_opts = { buffer = input_buf, nowait = true, silent = true }
	vim.keymap.set("i", "<CR>", confirm, map_opts)
	vim.keymap.set("i", "<Esc>", close_input, map_opts)
	vim.keymap.set("n", "<Esc>", close_input, map_opts)
	vim.keymap.set("n", "q", close_input, map_opts)

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = input_buf,
		once = true,
		callback = function()
			vim.schedule(close_input)
		end,
	})
end

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end
  -- stylua: ignore
  if node.depth == -1 then return end -- cannot rename root

	local flat = state.tree:flat({ show_hidden = config.show_hidden })
	local node_line = 1
	for i, n in ipairs(flat) do
		if n.path == node.path then
			node_line = i + 1 -- +1 for header
			break
		end
	end

	open_rename_popup(node, node_line, function(old_path, new_path)
		-- Update any open buffers pointing to the old path
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				local buf_name = vim.api.nvim_buf_get_name(buf)
				if buf_name == old_path or buf_name:find(old_path .. "/", 1, true) == 1 then
					local new_name = new_path .. buf_name:sub(#old_path + 1)
					vim.api.nvim_buf_set_name(buf, new_name)
				end
			end
		end

		local parent_path = node.parent or vim.fs.dirname(old_path)
    state.clipboard = nil -- avoid side-effect from clipboard
		state.tree:refresh(parent_path)
		ui.render(function()
			ui.focus_path(new_path)
		end)
	end)
end

return M
