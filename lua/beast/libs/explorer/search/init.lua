--- Explorer search mode: type a query, see the matching files (from anywhere
--- under the explorer root, even inside closed folders) as a tree. The explorer
--- itself is unchanged: `state.tree` is swapped for a `SearchTree` and the real
--- tree is put back when search ends.
local SearchTree = require("beast.libs.explorer.search.tree")
local config = require("beast.libs.explorer.config")
local prompt = require("beast.libs.explorer.search.prompt")
local state = require("beast.libs.explorer.state")
local sticky = require("beast.libs.explorer.sticky")
local ui = require("beast.libs.explorer.ui")

local M = {}

M.decorate = function(...)
	return require("beast.libs.explorer.search.decorate").apply(...)
end

---@class Beast.Explorer.SearchState
---@field root string
---@field real_tree Beast.Explorer.Tree  the explorer's own tree, untouched while searching
---@field session Beast.Finder.Search.Session
---@field query string
---@field confirmed? string  last query accepted with <Enter>
---@field prompting boolean  typing on the top line
---@field loading boolean  the file list is still streaming in
---@field focus_pending boolean  next results are for a new query: cursor goes to the first match
---@field saved_cursor integer[]
---@field augroup integer

---@return boolean
function M.is_active()
	return state.mode == "search"
end

--- Put the cursor on the first file row (or leave it on the top line when there is none).
---@param nodes Beast.Explorer.Node[]
local function focus_first(nodes)
	for i, node in ipairs(nodes) do
		if not node.dir then
			pcall(vim.api.nvim_win_set_cursor, state.view.win, { i + 1, 0 })
			return
		end
	end
	pcall(vim.api.nvim_win_set_cursor, state.view.win, { 1, 0 })
end

--- Show `tree` and repaint; while the prompt reads keys nothing repaints on its own.
---@param tree Beast.Explorer.SearchTree
---@param keep? string  path whose row keeps the cursor
local function show(tree, keep)
	local ms = state.mode_state
	state.tree = tree
	local nodes = ui.flush()
	local row
	for i, node in ipairs(nodes) do
		if node.path == keep then
			row = i + 1
			break
		end
	end
	if row then
		pcall(vim.api.nvim_win_set_cursor, state.view.win, { row, 0 })
	else
		focus_first(nodes)
	end
	sticky.refresh()
	if ms.prompting then
		vim.cmd.redraw()
	end
end

--- Re-match `query` and redraw. An empty query clears the results.
---@param query string
function M.set_query(query)
	-- stylua: ignore
	if not M.is_active() then return end
	local ms = state.mode_state
	ms.query = query

	if query == "" then
		ms.loading = false
		show(SearchTree.from_matches(ms.root, {}))
		return
	end

	ms.focus_pending = true
	-- The query line shows the new text right away; results follow when matched.
	ui.flush()
	if ms.prompting then
		vim.cmd.redraw()
	end
	ms.session:query(query, function(matched, result)
		-- A newer query (or exit) may have superseded this one.
		-- stylua: ignore
		if state.mode_state ~= ms or ms.query ~= query then return end

		-- The same query can report again (streaming finished, visibility toggled):
		-- keep the cursor on the row the user is on instead of jumping to the top.
		local node = not ms.focus_pending and state.current_node({ show_hidden = config.show_hidden }) or nil
		ms.loading = result.loading
		show(SearchTree.from_matches(ms.root, matched, result.capped), node and node.path)
		ms.focus_pending = false
	end)
end

--- Enter search mode: an empty `SearchTree` takes the place of the tree.
function M.start()
	-- stylua: ignore
	if M.is_active() then return end
	-- stylua: ignore
	if not (state.view and state.view:is_valid() and state.tree) then return end

	local root = state.tree.root.path
	local ms = { ---@type Beast.Explorer.SearchState
		root = root,
		real_tree = state.tree,
		session = require("beast.libs.finder.search").files({ cwd = root }),
		query = "",
		prompting = false,
		loading = false,
		focus_pending = false,
		saved_cursor = vim.api.nvim_win_get_cursor(state.view.win),
		augroup = vim.api.nvim_create_augroup("BeastExplorerSearch", { clear = true }),
	}
	state.mode, state.mode_state = "search", ms

	local explorer_win = state.view.win
	vim.api.nvim_create_autocmd("WinClosed", {
		group = ms.augroup,
		pattern = tostring(explorer_win),
		once = true,
		callback = M.stop,
	})
	-- Search mode belongs to the explorer window: leaving it (opening a result,
	-- <C-w>l, a click) ends it. Scheduled because the window switch is still in progress.
	vim.api.nvim_create_autocmd("WinLeave", {
		group = ms.augroup,
		buffer = state.view.buf,
		callback = function()
			vim.schedule(function()
				local win = vim.api.nvim_get_current_win()
				-- Transient floats (toasts, hints) are not a real change of focus.
				local floating = (vim.api.nvim_win_get_config(win).relative or "") ~= ""
				if state.mode_state == ms and win ~= explorer_win and not floating then
					-- Back to the file the user is on now, not to the row search left off at.
					local file = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
					local inside = file:sub(1, #root + 1) == root .. "/" and vim.fn.filereadable(file) == 1
					M.exit(inside and { path = file } or { reveal = false })
				end
			end)
		end,
	})
	-- Hidden/gitignored toggles change which files exist for the finder.
	vim.api.nvim_create_autocmd("User", {
		group = ms.augroup,
		pattern = "BeastVisibilityChanged",
		callback = function()
			ms.session:refresh()
		end,
	})

	show(SearchTree.from_matches(root, {}))
end

--- Type a query on the top line, starting search mode first if needed. <Enter>
--- keeps the results; <Esc> goes back to what was showing before.
function M.prompt()
	M.start()
	-- stylua: ignore
	if not M.is_active() then return end
	local ms = state.mode_state

	ms.prompting = true
	ui.flush()
	vim.cmd.redraw()
	local text = prompt.ask(ms.query, M.set_query)
	ms.prompting = false

	-- The window may have been closed while typing.
	-- stylua: ignore
	if state.mode_state ~= ms then return end
	if text then
		ms.confirmed = text
		M.set_query(text)
	elseif ms.confirmed then
		M.set_query(ms.confirmed)
	else
		M.exit({ reveal = false })
	end
end

--- Leave search mode without touching the cursor.
function M.stop()
	-- stylua: ignore
	if not M.is_active() then return end
	local ms = state.mode_state
	ms.session:close()
	pcall(vim.api.nvim_del_augroup_by_id, ms.augroup)
	state.tree = ms.real_tree
	state.mode, state.mode_state = "normal", nil
	ui.render()
end

--- Leave search mode. By default the row under the cursor is revealed in the
--- explorer tree; `path` reveals that file instead; with `reveal = false` the
--- explorer cursor is put back where it was.
---@param opts? { reveal?: boolean, path?: string }
function M.exit(opts)
	-- stylua: ignore
	if not M.is_active() then return end
	local ms = state.mode_state
	local target = opts and opts.path
	if not target and not (opts and opts.reveal == false) then
		local node = state.current_node({ show_hidden = config.show_hidden })
		target = node and node.path
	end
	M.stop()

	if target then
		ui.focus_path(target)
	else
		pcall(vim.api.nvim_win_set_cursor, state.view.win, ms.saved_cursor)
	end
	sticky.refresh()
end

return M
