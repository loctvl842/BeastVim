--- All operations on the single explorer panel window.
--- Win functions are stateless — they receive a view (or config) and return results.
--- No module-level state lives here; the caller (init.lua) owns everything.

local config = require("beast.libs.explorer.config")
local View = require("beast.libs.explorer.view")

local Win = {}

local NS_NAME = "BeastExplorer"

-- ---------------------------------------------------------------------------
-- Create
-- ---------------------------------------------------------------------------

--- Open a vertical split and return a new Beast.Explorer.View.
--- The split is placed on the side specified by config.cfg.side.
---@param cwd string  absolute path to root directory
---@return Beast.Explorer.View
function Win.create(cwd)
	local ns = vim.api.nvim_create_namespace(NS_NAME)
	local buf = vim.api.nvim_create_buf(false, true)

	-- Scratch buffer setup (canonical BeastVim style)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "beastvim-explorer"

	-- Open the vertical split without disturbing the current window stack
	local side = config.cfg.side == "right" and "botright" or "topleft"
	vim.cmd(side .. " " .. config.cfg.width .. "vsplit")

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Window-local options (non-text decorations would be distracting)
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].winfixwidth = true
	vim.wo[win].statusline = " Explorer" -- minimal statusline label

	return View(buf, win, ns, cwd)
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

--- Build the tree-line prefix for a node by walking its ancestor chain.
--- Each level contributes either "│ " (ancestor has more siblings) or "  ".
--- The final level contributes "└ " or "│ " depending on whether the node is last.
---@param node Beast.Explorer.Node
---@return string
local function build_prefix(node)
	-- Root-level nodes (depth 0) only get the leading padding space.
	if node.depth == 0 then
		return " "
	end

	-- Collect the `last` flag for each level from root → node (inclusive).
	local levels = {} ---@type boolean[]
	local n = node
	while n.depth >= 0 do
		table.insert(levels, 1, n.last)
		n = n.parent
	end

	local prefix = " " -- leading padding (matches neo-tree's padding = 1)
	for i, is_last in ipairs(levels) do
		if i == #levels then
			prefix = prefix .. (is_last and "└ " or "│ ")
		else
			prefix = prefix .. (is_last and "  " or "│ ")
		end
	end
	return prefix
end

function Win.render(view, nodes)
    -- stylua: ignore
    if not view:is_valid() then return end

	local cfg = config.cfg
	local win_width = vim.api.nvim_win_get_width(view.win)

	local lines = {} ---@type string[]
	local hls = {} ---@type {line:integer, col_s:integer, col_e:integer, group:string}[]

	-- Root header — uppercase basename, no icon
	local root_name = " " .. string.upper(vim.fn.fnamemodify(view.cwd, ":t"))
	lines[1] = root_name
	hls[#hls + 1] = { line = 0, col_s = 0, col_e = -1, group = "NeoTreeRootName" }

	local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

	for _, node in ipairs(nodes) do
		local line_idx = #lines -- 0-indexed (lines[1] already used by header)
		local prefix = build_prefix(node)

		-- Expander / icon
		local icon_str = ""
		local icon_hl = nil ---@type string?

		if node.dir then
			icon_str = node.open and cfg.icon_dir_open or cfg.icon_dir_closed
			icon_hl = "Directory"
		else
			local icon, hl
			if devicons_ok then
				icon, hl = devicons.get_icon(node.name, nil, { default = true })
			end
			icon_str = icon or cfg.icon_file:gsub("%s+$", "")
			icon_hl = hl
		end
		icon_str = icon_str .. " " -- one space after every glyph

		-- Git status glyph (right-aligned)
		local git_str = ""
		local git_hl = nil ---@type string?
		if cfg.git and node.git_status then
			local entry = cfg.icon_git[node.git_status]
			if entry then
				git_str = entry[1]
				git_hl = entry[2]
			end
		end

		-- Build line: right-align git glyph using display-column widths
		-- (vim.fn.strdisplaywidth handles multi-byte / wide glyphs correctly)
		local main = prefix .. icon_str .. node.name
		local main_w = vim.fn.strdisplaywidth(main)
		local git_w = vim.fn.strdisplaywidth(git_str)
		local line

		if git_str ~= "" then
			local pad = math.max(1, win_width - main_w - git_w - 1)
			line = main .. string.rep(" ", pad) .. git_str
		else
			line = main
		end
		lines[#lines + 1] = line

		-- Highlights
		if icon_hl then
			local col_s = #prefix
			hls[#hls + 1] = {
				line = line_idx,
				col_s = col_s,
				col_e = col_s + #icon_str,
				group = icon_hl,
			}
		end
		if git_hl then
			hls[#hls + 1] = { line = line_idx, col_s = #line - #git_str, col_e = -1, group = git_hl }
		end
		if node.hidden then
			hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = -1, group = "Comment" }
		end
	end

	pcall(function()
		vim.bo[view.buf].modifiable = true
		vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
		vim.bo[view.buf].modifiable = false
		vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
		for _, h in ipairs(hls) do
			pcall(vim.api.nvim_buf_add_highlight, view.buf, view.ns, h.group, h.line, h.col_s, h.col_e)
		end
	end)
end
-- ---------------------------------------------------------------------------
-- Title
-- ---------------------------------------------------------------------------

--- Set the buffer name to a short version of `cwd` (shown in tabline/statusline).
---@param view Beast.Explorer.View
---@param cwd  string
function Win.set_title(view, cwd)
    -- stylua: ignore
    if not view:is_valid() then return end
	local short = vim.fn.fnamemodify(cwd, ":~")
	pcall(vim.api.nvim_buf_set_name, view.buf, "Explorer: " .. short)
end

-- ---------------------------------------------------------------------------
-- Keymaps
-- ---------------------------------------------------------------------------

--- Install buffer-local keymaps into `view`.
---
--- `nodes_ref()` is called lazily each time a keymap fires so the render loop
--- and the keymap handler always share the same flat list.
---
---@param view      Beast.Explorer.View
---@param nodes_ref fun(): Beast.Explorer.Node[]
---@param on_select fun(node: Beast.Explorer.Node)   open a file
---@param on_toggle fun(node: Beast.Explorer.Node)   expand / collapse a dir
---@param on_close  fun()                            close the panel
function Win.set_keymaps(view, nodes_ref, on_select, on_toggle, on_close)
    -- stylua: ignore
    if not view:is_valid() then return end

	local opts = { buffer = view.buf, silent = true, nowait = true }

	--- Return the node that the cursor is currently on.
	---@return Beast.Explorer.Node?
	local function current_node()
		local ok, pos = pcall(vim.api.nvim_win_get_cursor, view.win)
    -- stylua: ignore
    if not ok then return nil end
		return nodes_ref()[pos[1] - 1] -- subtract the header row
	end

	-- <CR> / l : open file or expand directory
	local function activate()
		local node = current_node()
        -- stylua: ignore
        if not node then return end
		if node.dir then
			on_toggle(node)
		else
			on_select(node)
		end
	end
	vim.keymap.set("n", "<CR>", activate, opts)
	vim.keymap.set("n", "l", activate, opts)

	-- h : collapse current directory; if already closed, collapse parent
	vim.keymap.set("n", "h", function()
		local node = current_node()
        -- stylua: ignore
        if not node then return end
		if node.dir and node.open then
			on_toggle(node)
		elseif node.parent and node.parent.depth >= 0 then
			on_toggle(node.parent)
		end
	end, opts)

	-- q / <Esc> : close the panel
	vim.keymap.set("n", "q", on_close, opts)
	vim.keymap.set("n", "<Esc>", on_close, opts)

	-- R : force-refresh current directory
	vim.keymap.set("n", "R", function()
		-- Signal init.lua to re-read disk; init.lua handles the tree call.
		-- We expose a lightweight event so callers can hook it without a
		-- circular require.
		vim.api.nvim_exec_autocmds("User", { pattern = "BeastExplorerRefresh" })
	end, opts)
end

-- ---------------------------------------------------------------------------
-- Cursor / reveal
-- ---------------------------------------------------------------------------

--- Move the cursor to the row that corresponds to `path` in `nodes`.
---@param view  Beast.Explorer.View
---@param nodes Beast.Explorer.Node[]
---@param path  string
function Win.reveal(view, nodes, path)
    -- stylua: ignore
    if not view:is_valid() then return end
	for i, node in ipairs(nodes) do
		if node.path == path then
			pcall(vim.api.nvim_win_set_cursor, view.win, { i + 1, 0 }) -- +1 skips header
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- Destroy
-- ---------------------------------------------------------------------------

--- Close the panel window (the buffer is wiped automatically via bufhidden=wipe).
---@param view Beast.Explorer.View
function Win.destroy(view)
    -- stylua: ignore
    if not view:is_valid() then return end
	pcall(vim.api.nvim_win_close, view.win, true)
end

return Win
