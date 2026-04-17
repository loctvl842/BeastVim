--- Inline input prompts for the explorer tree.
---
--- Two styles:
---   - `overlay`: floats on an existing node line (rename, cut-paste conflict)
---   - `inline`:  inserts a new line below a directory (create, copy-paste conflict)
---
--- `on_confirm` returns:
---   - `false`      → keep prompt open (validation failed)
---   - `function`   → close prompt, then execute the function
---   - `nil`        → close prompt, no further action
---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")

local M = {}

-- ================================
-- Shared helpers
-- ================================

--- Build the tree-line prefix for a *new child* of `dir`.
---@param dir Beast.Explorer.Node
---@param is_last boolean
---@return string
local function build_child_prefix(dir, is_last)
  -- stylua: ignore
  if dir.depth == -1 then return " " end

	local styles = {
		compact = { indent = "  ", vertical = "│ ", connector = "├╴" },
		classic = { indent = "  ", vertical = "│ ", connector = "│ " },
	}
	local st = styles[config.style]
	local connector = is_last and "└╴" or st.connector

	local levels = {} ---@type boolean[]
	local n = dir
	while n.depth >= 0 do
		table.insert(levels, 1, n.last)
		n = state.tree.nodes[n.parent]
	end

	local prefix = " "
	for i = 2, #levels do
		prefix = prefix .. (levels[i] and st.indent or st.vertical)
	end
	return prefix .. connector
end

--- Open a float over the explorer, wire up keymaps and cleanup.
---@param row integer     0-indexed row relative to explorer window
---@param col integer     display-width column offset
---@param width integer   float width
---@param initial string? pre-fill text (empty if nil)
---@param on_confirm fun(input: string): false|fun()?  return false to keep open, or a function to run after close
---@param on_cancel fun()?               called on escape / leave
---@param cleanup fun()?                 extra cleanup before restoring focus
local function open_float(row, col, width, initial, on_confirm, on_cancel, cleanup)
	on_cancel = on_cancel or function() end
	local exp_win = state.view.win

	local input_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[input_buf].buftype = "nofile"
	vim.bo[input_buf].bufhidden = "wipe"

	if initial and initial ~= "" then
		vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { initial })
	end

	local input_win = vim.api.nvim_open_win(input_buf, true, {
		relative = "win",
		win = exp_win,
		row = row,
		col = col,
		width = width,
		height = 1,
		style = "minimal",
		border = "none",
		zindex = 50,
	})

	vim.wo[input_win].cursorline = false
	vim.wo[input_win].number = false
	vim.wo[input_win].relativenumber = false
	vim.wo[input_win].signcolumn = "no"

	if initial and initial ~= "" then
		vim.cmd("startinsert!")
	else
		vim.cmd("startinsert")
	end

	local closed = false

	local function close_input()
    -- stylua: ignore
		if closed then return end
		closed = true
		vim.cmd("stopinsert")

		if vim.api.nvim_win_is_valid(input_win) then
			vim.api.nvim_win_close(input_win, true)
		end
		if cleanup then
			cleanup()
		end
		if state.view and state.view:is_valid() then
			pcall(vim.api.nvim_set_current_win, state.view.win)
		end
	end

	local function confirm()
		local lines = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)
		local input = (lines[1] or ""):match("^%s*(.-)%s*$") -- trim
		if not input or input == "" then
			close_input()
			on_cancel()
			return
		end
		if input:match("[%z\1-\31]") then
			vim.notify("Invalid name", vim.log.levels.ERROR)
			return
		end
		-- Caller validates and optionally returns an action to run after close
		local result = on_confirm(input)
		if result == false then
			return
		end
		close_input()
		if type(result) == "function" then
			result()
		end
	end

	local function cancel()
    -- stylua: ignore
		if closed then return end
		close_input()
		on_cancel()
	end

	local map_opts = { buffer = input_buf, nowait = true, silent = true }
	vim.keymap.set("i", "<CR>", confirm, map_opts)
	vim.keymap.set("i", "<Esc>", cancel, map_opts)
	vim.keymap.set("n", "<Esc>", cancel, map_opts)
	vim.keymap.set("n", "q", cancel, map_opts)

	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = input_buf,
		once = true,
		callback = function()
			vim.schedule(cancel)
		end,
	})
end

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

-- ================================
-- Methods
-- ================================

--- Open a float overlaid on an existing node's name (rename-style).
---@param node Beast.Explorer.Node
---@param node_line integer  1-based buffer line
---@param on_confirm fun(input: string): false|fun()?  return false to keep open, or a function to run after close
---@param on_cancel fun()?
function M.overlay(node, node_line, on_confirm, on_cancel)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end

	local exp_width = vim.api.nvim_win_get_width(state.view.win)
	local indent = name_col(node, node_line)
	local input_width = exp_width - indent - 1
	if input_width < 10 then
		input_width = exp_width - 2
		indent = 1
	end

	open_float(node_line - 1, indent, input_width, node.name, on_confirm, on_cancel)
end

--- Open a float on a newly inserted blank line below a directory (create-style).
---@param target_dir Beast.Explorer.Node
---@param dir_line integer  1-based buffer line of the directory
---@param is_last boolean
---@param on_confirm fun(input: string): false|fun()?  return false to keep open, or a function to run after close
---@param on_cancel fun()?
---@param initial string?  pre-fill text
function M.inline(target_dir, dir_line, is_last, on_confirm, on_cancel, initial)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end

	local exp_buf = state.view.buf
	local exp_width = vim.api.nvim_win_get_width(state.view.win)

	local child_prefix = build_child_prefix(target_dir, is_last)
	local prefix_cols = vim.fn.strdisplaywidth(child_prefix)

	-- Insert a line with the prefix to push content down visually
	vim.bo[exp_buf].modifiable = true
	vim.api.nvim_buf_set_lines(exp_buf, dir_line, dir_line, false, { child_prefix })
	vim.bo[exp_buf].modifiable = false

	-- Highlight the prefix with NonText so it matches the rest of the tree
	pcall(vim.api.nvim_buf_set_extmark, exp_buf, state.view.ns, dir_line, 0, {
		end_col = #child_prefix,
		hl_group = "NonText",
	})

	local indent = prefix_cols
	local input_width = exp_width - indent - 1
	if input_width < 10 then
		input_width = exp_width - 2
		indent = 1
	end

	local blank_removed = false
	local function remove_blank()
    -- stylua: ignore
		if blank_removed then return end
		if state.view and state.view:is_valid() then
			pcall(function()
				vim.bo[exp_buf].modifiable = true
				vim.api.nvim_buf_set_lines(exp_buf, dir_line, dir_line + 1, false, {})
				vim.bo[exp_buf].modifiable = false
			end)
		end
	end

	open_float(dir_line, indent, input_width, initial, on_confirm, on_cancel, remove_blank)
end

return M
