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

--- Return the node under the cursor.
--- Subtracts 1 to skip the root header line (line 1 in the buffer).
---@return Beast.Explorer.Node?
local function current_node()
	local nodes = state.tree:flat({ show_hidden = config.show_hidden })
	local ok, pos = pcall(vim.api.nvim_win_get_cursor, state.view.win)
    -- stylua: ignore
    if not ok then return end
	return nodes[pos[1] - 1] -- row 1 = header, row 2 = nodes[1]
end

--- Build the tree-line prefix for a *new child* of `dir`.
--- Always uses real corner connectors (├╴/└╴) regardless of style,
--- because this is an input widget, not a file node.
---@param dir Beast.Explorer.Node
---@param is_last boolean  true when dir has no visible children
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
	print("vaicalon", '"', connector, '"')
	return prefix .. connector
end

--- Open an inline input popup below `target_dir` in the explorer tree.
--- Inserts a real blank line to push content down, overlays a float on it,
--- then creates a file or directory based on user input.
---@param target_dir Beast.Explorer.Node  the directory to create inside
---@param dir_line integer  1-based buffer line of the target directory
---@param is_last boolean  true when dir has no visible children
---@param on_done fun(path: string, is_dir: boolean)
local function open(target_dir, dir_line, is_last, on_done)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end

	local exp_win = state.view.win
	local exp_buf = state.view.buf
	local exp_width = vim.api.nvim_win_get_width(exp_win)

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

	local input_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[input_buf].buftype = "nofile"
	vim.bo[input_buf].bufhidden = "wipe"

	local input_win = vim.api.nvim_open_win(input_buf, true, {
		relative = "win",
		win = exp_win,
		row = dir_line, -- 0-indexed: overlays the blank line we just inserted
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

	-- WinLeave on the explorer restores the cursor; WinEnter re-hides it on return
	vim.cmd("startinsert")

	local closed = false
	local blank_removed = false

	local function remove_blank()
    -- stylua: ignore
		if blank_removed then return end
		blank_removed = true
		if state.view and state.view:is_valid() then
			pcall(function()
				vim.bo[exp_buf].modifiable = true
				vim.api.nvim_buf_set_lines(exp_buf, dir_line, dir_line + 1, false, {})
				vim.bo[exp_buf].modifiable = false
			end)
		end
	end

	local function close_input()
    -- stylua: ignore
		if closed then return end

		closed = true
		vim.cmd("stopinsert")

		if vim.api.nvim_win_is_valid(input_win) then
			vim.api.nvim_win_close(input_win, true)
		end
		remove_blank()
		if state.view and state.view:is_valid() then
			pcall(vim.api.nvim_set_current_win, state.view.win)
		end
	end

	local function confirm()
		local lines = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)
		local input = (lines[1] or ""):match("^%s*(.-)%s*$") -- trim
		close_input()
		if not input or input == "" then
			return
		end
		if input:match("[%z\1-\31]") then
			vim.notify("Invalid path", vim.log.levels.ERROR)
			return
		end

		local is_dir = input:sub(-1) == "/"
		local rel_path = is_dir and input:sub(1, -2) or input
		local full_path = target_dir.path .. "/" .. rel_path

		if uv.fs_stat(full_path) then
			vim.notify("Already exists: " .. rel_path, vim.log.levels.WARN)
			return
		end

		local parent = is_dir and full_path or vim.fs.dirname(full_path)
		vim.fn.mkdir(parent, "p")

		if not is_dir then
			local fd = uv.fs_open(full_path, "w", 420) -- 0644
			if fd then
				uv.fs_close(fd)
			else
				vim.notify("Failed to create: " .. rel_path, vim.log.levels.ERROR)
				return
			end
		end

		on_done(full_path, is_dir)
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

---@param target_dir Beast.Explorer.Node
local function show_popup(target_dir)
	local fresh = state.tree:flat({ show_hidden = config.show_hidden })

	local dir_line = 1 -- below header for root
	if target_dir.depth ~= -1 then
		for i, n in ipairs(fresh) do
			if n.path == target_dir.path then
				dir_line = i + 1 -- +1 for header line
				break
			end
		end
	end

	local has_children = false
	for _, n in ipairs(fresh) do
		if n.parent == target_dir.path then
			has_children = true
			break
		end
	end

	open(target_dir, dir_line, not has_children, function(full_path, _)
		state.tree:refresh(target_dir.path)
		state.tree:open(full_path)
		ui.render(function()
			ui.focus_path(full_path)
		end)
	end)
end

function M.run()
	local node = current_node()
  -- stylua: ignore
  if not node then return end

	local target_dir = node.dir and node or state.tree.nodes[node.parent]
  -- stylua: ignore
  if not target_dir then return end

	-- Open closed directory first so children are visible before the popup
	if target_dir.dir and not target_dir.open then
		state.tree:open(target_dir.path)
		ui.render(function()
			show_popup(target_dir)
		end)
	else
		show_popup(target_dir)
	end
end

return M
