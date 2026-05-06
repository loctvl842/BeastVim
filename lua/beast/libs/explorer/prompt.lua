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
local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")

local M = {}

local styles = {
	compact = { indent = "  ", vertical = "│ ", branch = "├╴", last_branch = "└╴" },
	classic = { indent = "  ", vertical = "│ ", branch = "│ ", last_branch = "└╴" },
}

-- ================================
-- Shared helpers
-- ================================

--- Build the tree-line prefix for a *new child* of `dir`.
---@param dir Beast.Explorer.Node
---@param is_last boolean
---@return string
local function build_child_prefix(dir, is_last)
  -- stylua: ignore
  if dir.depth == -1 then return string.rep(" ", config.padding) end

	local st = styles[config.style]
	local branch = is_last and st.last_branch or st.branch

	local levels = {} ---@type boolean[]
	local n = dir
	while n.depth >= 0 do
		table.insert(levels, 1, n.last)
		n = state.tree.nodes[n.parent]
	end

	local prefix = string.rep(" ", config.padding)
	for i = 2, #levels do
		prefix = prefix .. (levels[i] and st.indent or st.vertical)
	end
	return prefix .. branch
end

--- Open a float over the explorer, wire up keymaps and cleanup.
---@param row integer     0-indexed row relative to explorer window
---@param col integer     display-width column offset
---@param width integer   float width
---@param initial string? pre-fill text (empty if nil)
---@param on_confirm fun(input: string): false|fun()?  return false to keep open, or a function to run after close
---@param on_cancel fun()                called on escape / leave
---@param cleanup fun()?                 extra cleanup before restoring focus
local function open_float(row, col, width, initial, on_confirm, on_cancel, cleanup)
	Util.wo(state.view.win, "cursorline", false)
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
	vim.wo[input_win].winhighlight = "Normal:BeastExplorerPrompt"

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
		Util.wo(state.view.win, "cursorline", true)

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
---@return integer           -- display-width columns before the name
local function name_col(node)
	local depth_padding = node.depth * 2 -- 2 spaces "├╴", "└╴"
	local prefix_icon
	if node.dir then
		prefix_icon = vim.fn.strdisplaywidth(config.icon.dir_open)
	else
		local icon = config.file_icon(node.name)
		prefix_icon = vim.fn.strdisplaywidth(icon)
	end
	return config.padding + depth_padding + prefix_icon + 1
end

--- Replace one connector string with another on a buffer line and add a highlight extmark.
--- Reads the line from the buffer to avoid stale captures.
---@param buf integer
---@param ns integer
---@param row integer   0-indexed buffer row
---@param from_str string  connector to find
---@param to_str string    connector to replace with
local function swap_connector(buf, ns, row, from_str, to_str)
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""

	-- Find the last occurrence: branch connectors sit rightmost in the prefix,
	-- and in classic style branch == vertical so we must skip earlier matches.
	local start_col = nil
	local search_from = 1
	while true do
		local s = line:find(from_str, search_from, true)
		if not s then
			break
		end
		start_col = s
		search_from = s + 1
	end
  -- stylua: ignore
	if not start_col then return end

	start_col = start_col - 1 -- Lua 1-based → 0-based byte col
	local end_col = start_col + #from_str

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_text(buf, row, start_col, row, end_col, { to_str })
	vim.bo[buf].modifiable = false

	vim.api.nvim_buf_set_extmark(buf, ns, row, start_col, {
		end_col = start_col + #to_str,
		hl_group = "BeastExplorerIndent",
		hl_mode = "combine",
		priority = 200,
	})
end

-- ================================
-- Methods
-- ================================

--- Open a float overlaid on an existing node's name (rename-style).
---@param current_node Beast.Explorer.Node
---@param on_confirm fun(input: string): false|fun()?  return false to keep open, or a function to run after close
---@param on_cancel fun()?
function M.overlay(current_node, on_confirm, on_cancel)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end

	local exp_width = vim.api.nvim_win_get_width(state.view.win)
	local indent = name_col(current_node)
	local input_width = exp_width - indent - 1
	if input_width < 10 then
		input_width = exp_width - 2
		indent = 1
	end

	on_cancel = on_cancel or function() end
	local current_pos = vim.api.nvim_win_get_cursor(state.view.win)[1]
	local float_row = math.max(0, current_pos - vim.fn.line("w0"))
	open_float(float_row, indent, input_width, current_node.name, on_confirm, on_cancel)
end

--- Open a float on a newly inserted blank line below a directory (create-style).
---@param target_dir Beast.Explorer.Node
---@param current_node Beast.Explorer.Node
---@param on_confirm fun(input: string): false|fun()?  return false to keep open, or a function to run after close
---@param on_cancel fun()?
---@param initial string?  pre-fill text
function M.inline(target_dir, current_node, on_confirm, on_cancel, initial)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end

	local exp_buf = state.view.buf
	local exp_width = vim.api.nvim_win_get_width(state.view.win)
	local current_pos = vim.api.nvim_win_get_cursor(state.view.win)[1]
	local st = styles[config.style]

	if not current_node.dir and not current_node.expanded then
		state.tree:expand(current_node)
	end

	local is_last = (current_node.dir == false and current_node.last) or (current_node.dir and next(current_node.children) == nil)
	local child_prefix = build_child_prefix(target_dir, is_last)
	local prefix_cols = vim.fn.strdisplaywidth(child_prefix)

	-- Insert a blank line with tree prefix to push content down
	vim.bo[exp_buf].modifiable = true
	vim.api.nvim_buf_set_lines(exp_buf, current_pos, current_pos, false, { child_prefix })
	vim.bo[exp_buf].modifiable = false

	-- The current node was "last" → swap └╴ to ├╴ since a new sibling is being added
	local needs_connector_restore = current_node.dir == false and current_node.last
	if needs_connector_restore then
		swap_connector(exp_buf, state.view.ns, current_pos - 1, st.last_branch, st.branch)
	end

	-- Highlight the inserted prefix line
	pcall(vim.api.nvim_buf_set_extmark, exp_buf, state.view.ns, current_pos, 0, {
		end_col = #child_prefix,
		hl_group = "BeastExplorerIndent",
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
		blank_removed = true
		if state.view and state.view:is_valid() then
			pcall(function()
				vim.bo[exp_buf].modifiable = true
				vim.api.nvim_buf_set_lines(exp_buf, current_pos, current_pos + 1, false, {})
				vim.bo[exp_buf].modifiable = false
			end)
		end
	end

	local function override_on_cancel()
    -- stylua: ignore
    if on_cancel then on_cancel() end
		if needs_connector_restore then
			swap_connector(exp_buf, state.view.ns, current_pos - 1, st.branch, st.last_branch)
		end
	end

	local float_row = math.max(0, current_pos - vim.fn.line("w0") + 1)
	open_float(float_row, indent, input_width, initial, on_confirm, override_on_cancel, remove_blank)
end

return M
