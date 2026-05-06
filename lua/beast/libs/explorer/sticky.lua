--- Sticky ancestor headers.
---
--- A floating overlay sitting at the top of the explorer window that pins the
--- ancestor directories of the topmost visible node when those ancestors have
--- scrolled out of view. Purely visual — non-focusable, does not steal cursor.
---
--- The float overlays the top N rows of the explorer split (`relative = "win"`)
--- without shifting buffer line numbers. To prevent the cursor from landing
--- in the rows hidden under the float, we drive the explorer's `scrolloff`
--- equal to the current sticky height: built-in scrolloff keeps the cursor
--- below the sticky stack on every motion (`gg`, `H`, `j`, `<C-u>`, etc.).
local View = require("beast.libs.view")
local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")

-- =============================================================================
-- VIEW
-- =============================================================================

---@class Beast.Explorer.StickyView : Beast.View
---@field ns integer
local StickyView = View:extend(function(obj, ns)
	obj.ns = ns
end)

-- =============================================================================
-- HELPERS
-- =============================================================================

---@class Beast.Explorer.StickyEntry
---@field kind "root"|"dir"
---@field label string
---@field depth integer

local DEFAULT_SCROLLOFF = 0
local ZINDEX = 30

---@param n integer
local function set_scrolloff(n)
	if state.view and state.view:is_valid() then
		Util.wo(state.view.win, "scrolloff", n)
	end
end

--- Walk the parents of the node under the cursor and return them ordered
--- root → nearest-parent. Only ancestors whose actual buffer line has scrolled
--- above the visible region are pinned (otherwise they'd duplicate the live
--- tree row right below the float). The root header is always prepended when
--- the buffer is scrolled past line 1.
---@return Beast.Explorer.StickyEntry[]
local function compute_pinned()
	if not state.tree or not state.view or not state.view:is_valid() then
		return {}
	end

	local ok, pos = pcall(vim.api.nvim_win_get_cursor, state.view.win)
	if not ok then
		return {}
	end
	local cursor_row = pos[1]
	if cursor_row <= 1 then
		return {}
	end

	local top_row = vim.fn.line("w0", state.view.win) -- 1-indexed buf row

	local nodes = state.tree:flat({ show_hidden = config.show_hidden })
	local cursor_node = nodes[cursor_row - 1] -- line 1 = root header
	if not cursor_node then
		return {}
	end

	-- path → 1-indexed buffer row map (line 1 reserved for the root header).
	local row_of = {} ---@type table<string, integer>
	for i, node in ipairs(nodes) do
		row_of[node.path] = i + 1
	end

	-- Cursor's ancestors, root → nearest-parent order.
	local ancestors = {} ---@type Beast.Explorer.Node[]
	local cur = state.tree.nodes[cursor_node.parent]
	while cur and cur.depth >= 0 do
		table.insert(ancestors, 1, cur)
		cur = state.tree.nodes[cur.parent]
	end

	-- The float covers buffer rows top_row..top_row + N - 1, so an ancestor
	-- is "hidden" (and should be pinned) when its row < top_row + N.
	-- N depends on the pin count, so iterate to a fixed point — this
	-- converges in at most (#ancestors + 1) steps because pinning is
	-- monotonic (adding an entry only ever makes more ancestors qualify).
	local has_root = top_row > 1
	local n = 0
	local pinned_dirs = {} ---@type Beast.Explorer.Node[]
	for _ = 0, #ancestors do
		pinned_dirs = {}
		for _, a in ipairs(ancestors) do
			local row = row_of[a.path]
			if row and row < top_row + n then
				pinned_dirs[#pinned_dirs + 1] = a
			end
		end
		local new_n = #pinned_dirs + (has_root and 1 or 0)
		if new_n == n then
			break
		end
		n = new_n
	end

	local entries = {} ---@type Beast.Explorer.StickyEntry[]
	if has_root then
		entries[#entries + 1] = {
			kind = "root",
			label = string.upper(vim.fn.fnamemodify(state.view.cwd, ":t")),
			depth = -1,
		}
	end
	for _, node in ipairs(pinned_dirs) do
		entries[#entries + 1] = {
			kind = "dir",
			label = node.name,
			depth = node.depth,
		}
	end

	return entries
end

--- Build the lines and highlight specs for the sticky float.
---@param entries Beast.Explorer.StickyEntry[]
---@param width integer  Float width — last line is padded to this so the
---  underline border spans the full explorer width regardless of label length.
---@return string[], { line:integer, col_s:integer, col_e:integer, group:string }[]
local function build(entries, width)
	local lines = {} ---@type string[]
	local hls = {} ---@type { line:integer, col_s:integer, col_e:integer, group:string }[]
	local pad = string.rep(" ", config.padding)

	for i, entry in ipairs(entries) do
		local line_idx = i - 1

		if entry.kind == "root" then
			local line = " " .. entry.label
			lines[#lines + 1] = line
			hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = #line, group = "BeastExplorerTitle" }
		else
			-- Match the explorer's depth-based indent: depth 0 sits flush under
			-- the root, each deeper level adds 2 spaces.
			local indent_units = math.max(0, entry.depth)
			local indent = pad .. string.rep("  ", indent_units)
			local icon = config.icon.dir_open
			local line = indent .. icon .. " " .. entry.label
			lines[#lines + 1] = line

			if #indent > 0 then
				hls[#hls + 1] = { line = line_idx, col_s = 0, col_e = #indent, group = "BeastExplorerIndent" }
			end
			hls[#hls + 1] =
				{ line = line_idx, col_s = #indent, col_e = #indent + #icon, group = "BeastExplorerDir" }
		end
	end

	-- Underline the bottom row to mark the sticky/content boundary.
	-- The underline only paints under actual glyphs, so pad the last line
	-- with spaces to the float width — that way the border spans the full
	-- explorer width even when the entry label is short.
	if #lines > 0 then
		local last = lines[#lines]
		local short = width - vim.fn.strdisplaywidth(last)
		if short > 0 then
			last = last .. string.rep(" ", short)
			lines[#lines] = last
		end
		hls[#hls + 1] = {
			line = #lines - 1,
			col_s = 0,
			col_e = #last,
			group = "BeastExplorerStickyBorder",
		}
	end

	return lines, hls
end

---@param entries Beast.Explorer.StickyEntry[]
---@param width integer
local function write(entries, width)
	local sticky = state.sticky
	if not sticky or not sticky:is_valid() then
		return
	end

	local lines, hls = build(entries, width)

	pcall(function()
		vim.bo[sticky.buf].modifiable = true
		vim.api.nvim_buf_set_lines(sticky.buf, 0, -1, false, lines)
		vim.bo[sticky.buf].modifiable = false

		vim.api.nvim_buf_clear_namespace(sticky.buf, sticky.ns, 0, -1)
		for _, h in ipairs(hls) do
			pcall(vim.api.nvim_buf_set_extmark, sticky.buf, sticky.ns, h.line, h.col_s, {
				end_col = h.col_e,
				hl_group = h.group,
			})
		end
	end)
end

---@param width integer
---@param height integer
---@return boolean ok
local function open_float(width, height)
	local buf = Buffer.new("beast-explorer-sticky")
	local ns = vim.api.nvim_create_namespace("beastvim_explorer_sticky")

	local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
		relative = "win",
		win = state.view.win,
		row = 0,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "none",
		focusable = false,
		noautocmd = true,
		zindex = ZINDEX,
	})
	if not ok or not win then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		return false
	end

	Util.wo(win, "winhighlight", "Normal:BeastExplorerStickyBg")
	Util.wo(win, "wrap", false)
	Util.wo(win, "winblend", 0)

	state.sticky = StickyView(buf, win, ns)
	return true
end

-- =============================================================================
-- MODULE
-- =============================================================================

local M = {}

--- Idempotent setup hook called from explorer lifecycle. Heavy lifting is in
--- `refresh()`; mount just kicks the first refresh so the float opens
--- automatically if the explorer starts scrolled past the root.
function M.mount()
	if not config.sticky then
		return
	end
	M.refresh()
end

--- Recompute pinned ancestors and reconcile the float.
--- - 0 pinned → close the float and reset scrolloff.
--- - ≥1 pinned → open (if absent) or resize the float, render entries,
---   and set scrolloff = N so the cursor parks below the sticky stack.
function M.refresh()
	if not config.sticky then
		return
	end
	if not state.view or not state.view:is_valid() then
		return
	end

	local entries = compute_pinned()
	local n = #entries

	if n == 0 then
		M.close()
		return
	end

	local width = vim.api.nvim_win_get_width(state.view.win)

	if not state.sticky or not state.sticky:is_valid() then
		state.sticky = nil
		if not open_float(width, n) then
			return
		end
	else
		pcall(vim.api.nvim_win_set_config, state.sticky.win, {
			relative = "win",
			win = state.view.win,
			row = 0,
			col = 0,
			width = width,
			height = n,
		})
	end

	write(entries, width)
	set_scrolloff(n)
end

function M.close()
	if state.sticky and state.sticky:is_valid() then
		state.sticky:close()
	end
	state.sticky = nil
	set_scrolloff(DEFAULT_SCROLLOFF)
end

return M
