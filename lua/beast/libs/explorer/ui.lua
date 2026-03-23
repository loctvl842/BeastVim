---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local View = require("beast.libs.view")
local config = require("beast.libs.explorer.config")

---@class Beast.Explorer.View : Beast.View
---@field ns integer
---@field cwd string
local ExplorerView = View:extend(function(obj, ns, cwd)
	obj.ns = ns
	obj.cwd = cwd
end)

--- Set the buffer name to a short version of cwd
---@param cwd? string
function ExplorerView:set_title(cwd)
	if not self:is_valid() then
		return
	end

	cwd = cwd or self.cwd

	local short = vim.fn.fnamemodify(cwd, ":~")
	pcall(vim.api.nvim_buf_set_name, self.buf, "Explorer: " .. short)
end
-- =============================================================================
-- UTILS
-- =============================================================================

---@param filetype string
---@return integer
local function create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

--- Build the tree-line prefix for `node`.
---
--- Depth-0 nodes (direct children of root) get no connector — they sit
--- flush under the uppercase root header with just a leading space.
---
--- Depth-1+ nodes get the standard box-drawing connectors:
---   Ancestor levels → "│ " (has more siblings) or "  " (was last)
---   Own level       → "├╴" (not last) or "└╴" (last)
---
--- The depth-0 ancestor indicator is intentionally skipped so that the
--- top-level items don't show a │ connecting them to the plain-text header.
---
---@param node Beast.Explorer.Node
---@return string
local function build_prefix(node)
  -- stylua: ignore
  if node.depth == 0 then return " " end  -- no connector for top-level items

	-- Collect `last` flags from depth-0 up to this node (inclusive).
	local levels = {} ---@type boolean[]
	local n = node
	while n.depth >= 0 do
		table.insert(levels, 1, n.last)
		n = state.tree.nodes[n.parent]
	end
	-- levels[1] = depth-0 ancestor's flag — skipped below
	-- levels[#levels] = this node's flag
	local styles = {
		compact = {
			indent = "  ",
			vertical = "│ ",
			branch = "├╴",
			last_branch = "└╴",
		},
		classic = {
			indent = "  ",
			vertical = "│ ",
			branch = "│ ",
			last_branch = "└╴",
		},
	}

	local prefix = " " -- leading padding
	local st = styles[config.style]
	for i = 2, #levels do -- start at 2 to skip the depth-0 indicator
		if i == #levels then
			prefix = prefix .. (levels[i] and st.last_branch or st.branch)
		else
			prefix = prefix .. (levels[i] and st.indent or st.vertical)
		end
	end
	return prefix
end

-- =============================================================================
-- VIEW
-- =============================================================================

local M = {}

--- Open a vertical split and return a new Beast.Explorer.View.
--- The split is placed on the side specified by config.cfg.side.
---@param cwd string  absolute path to root directory
---@return Beast.Explorer.View
function M.create(cwd)
	local ns = vim.api.nvim_create_namespace("beastvim_explorer")
	local buf = create_scratch_buf("beast-explorer")

	local side = config.side == "right" and "botright" or (config.side == "left" and "topleft" or error("invalid side"))
	vim.cmd(side .. " " .. config.width .. "vsplit")

	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Window-local options
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].wrap = false
	vim.wo[win].cursorline = true
	vim.wo[win].winfixwidth = true
	vim.wo[win].statusline = "Explorer"

	return ExplorerView(buf, win, ns, cwd)
end
---@param nodes Beast.Explorer.Node[]
local function mount_keymaps(nodes)
  -- stylua: ignore
  if not state.view:is_valid() then return end

	local opts = { buffer = state.view.buf, silent = true, nowait = true }

	--- Return the node under the cursor.
	--- Subtracts 1 to skip the root header line (line 1 in the buffer).
	---@return Beast.Explorer.Node?
	local function current_node()
		local ok, pos = pcall(vim.api.nvim_win_get_cursor, state.view.win)
    -- stylua: ignore
    if not ok then return end
		return nodes[pos[1] - 1] -- row 1 = header, row 2 = nodes[1]
	end

	local function on_toggle(node)
		state.tree:toggle(node.path)
		M.render()
	end

	local function on_select(node)
		local prev = vim.fn.win_getid(vim.fn.winnr("#"))
		if prev ~= 0 and prev ~= state.view.win then
			pcall(vim.api.nvim_set_current_win, prev)
		else
			vim.cmd("vsplit")
		end
		vim.cmd("edit " .. vim.fn.fnameescape(node.path))
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
end

local function mount_autocmds()
	-- stylua: ignore
	if state.augroup then return end
	if not state.view or not state.view.buf or not state.view.win then
		return
	end

	state.augroup = vim.api.nvim_create_augroup("BeastExplorerUI_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_set_hl(0, "BeastExplorerCursor", {
		blend = 100,
		nocombine = true,
	})

	---@type string?
	local prev_guicursor = vim.o.guicursor
	vim.o.guicursor = "a:block-BeastExplorerCursor"

	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		group = state.augroup,
		buffer = state.view.buf,
		callback = function()
			if vim.api.nvim_get_current_win() ~= state.view.win then
				return
			end
			if prev_guicursor == nil then
				prev_guicursor = vim.o.guicursor
			end
			vim.o.guicursor = "a:block-BeastExplorerCursor"
		end,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		group = state.augroup,
		buffer = state.view.buf,
		callback = function()
			if prev_guicursor ~= nil then
				vim.o.guicursor = prev_guicursor
				prev_guicursor = nil
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		pattern = tostring(state.view.win),
		once = true,
		callback = function()
			if prev_guicursor ~= nil then
				vim.o.guicursor = prev_guicursor
				prev_guicursor = nil
			end
			state.augroup = nil
		end,
	})
end

--- Write `nodes` into `view`'s buffer and apply highlight decorations.
--- Line 1 is always the root header; nodes occupy lines 2..N.
--- Safe to call even when the window has been closed externally.
--- Calls `on_done()` after the render (after the async git fetch when enabled).
---@param on_done? fun()
function M.render(on_done)
  -- stylua: ignore
  if not state.view or not state.view:is_valid() then return end
  -- stylua: ignore
  if not state.tree then return end
	local nodes = state.tree:flat({ show_hidden = config.show_hidden, git_status = nil })

	local lines = {} ---@type string[]
	local hls = {} ---@type {line:integer,col_s:integer,col_e:integer,group:string}[]

	-- Root header: " UPPERCASE-BASENAME" — no icon, plain text, visually distinct
	local root_name = string.upper(vim.fn.fnamemodify(state.view.cwd, ":t"))

	lines[1] = " " .. root_name
	hls[#hls + 1] = { line = 0, col_s = 0, col_e = -1, group = "Directory" }

	-- Lazy-load devicons once per render (not at require time)
	local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
	for _, node in ipairs(nodes) do
		local line_idx = #lines -- 0-indexed: lines[1] is already the header
		local prefix = build_prefix(node)

		-- Icon
		local icon_str = ""
		local icon_hl = nil ---@type string?

		if config.icons then
			if node.dir then
				icon_str = node.open and config.icon.dir_open or config.icon.dir_closed
				icon_hl = "Directory"
			else
				local icon, hl
				if devicons_ok then
					icon, hl = devicons.get_icon(node.name, nil, { default = true })
				end
				icon_str = icon or config.icon.file
				icon_hl = hl
			end
		end

		-- Assemble line: prefix + icon + " " + name, git right-aligned
		local main = prefix .. icon_str .. " " .. node.name
		local line = main
		lines[#lines + 1] = line

		-- Highlights
		local prefix_w = vim.fn.strdisplaywidth(prefix)
		local icon_w = vim.fn.strdisplaywidth(icon_str)

		-- Tree-line characters in a subtle colour
		hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = #prefix, group = "NonText" }

		-- File / directory icon
		if icon_hl then
			hls[#hls + 1] = { line = line_idx, col_s = #prefix, col_e = #prefix + #icon_str, group = icon_hl }
		end

		-- Dim hidden files/dirs
		if node.hidden then
			hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = -1, group = "Comment" }
		end

		-- Suppress the _ prefix_w / icon_w unused-warning (they're for future use)
		_ = prefix_w
		_ = icon_w
	end

	-- Write lines + highlights atomically; ignore errors from a race-closed window
	pcall(function()
		vim.bo[state.view.buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.view.buf, 0, -1, false, lines)
		vim.bo[state.view.buf].modifiable = false

		vim.api.nvim_buf_clear_namespace(state.view.buf, state.view.ns, 0, -1)
		for _, h in ipairs(hls) do
			pcall(vim.api.nvim_buf_set_extmark, state.view.buf, state.view.ns, h.line, h.col_s, {
				end_col = h.col_e,
				hl_group = h.group,
			})
		end
	end)

	if on_done then
		on_done()
	end

	mount_keymaps(nodes)
	mount_autocmds()
end

--- Move the cursor to the row that matches `path` in `nodes`.
--- Adds 1 to account for the root header occupying line 1.
---@param path  string
function M.reveal(path)
	if not state.view or not state.view:is_valid() then
		return
	end
	local nodes = state.tree:flat({ show_hidden = config.show_hidden, git_status = nil })
	for i, node in ipairs(nodes) do
		if node.path == path then
			pcall(vim.api.nvim_win_set_cursor, state.view.win, { i + 1, 0 }) -- +1 for header
			return
		end
	end
end

--- Open the explorer panel rooted at `cwd`.
--- Always creates a fresh tree. If the panel is already open, just focus it.
---@param cwd? string  defaults to vim.fn.getcwd()
function M.open(cwd)
	if state ~= nil and state:is_valid() then
		vim.api.nvim_set_current_win(state.view.win)
		return state
	end
	cwd = cwd and vim.fn.fnamemodify(cwd, ":p"):gsub("/$", "") or vim.fn.getcwd()
end

function M.close()
	if state.view and state.view:is_valid() then
		state.view:close()
	end
end

return M
