--- Public API for beast.libs.explorer.
--- This is the ONLY file that owns mutable state.
---
--- Usage:
---   local Explorer = require("beast.libs.explorer")
---   Explorer.setup({ width = 35, git = true })
---   Explorer.toggle()          -- open/close
---   Explorer.open("/some/dir") -- open at a specific root
---   Explorer.reveal(vim.api.nvim_buf_get_name(0)) -- focus current file

---@class Beast.Explorer
---@overload fun(cwd?: string)
local M = {}

local config = require("beast.libs.explorer.config")
local Win = require("beast.libs.explorer.win")
local Tree = require("beast.libs.explorer.tree")
local Git = require("beast.libs.explorer.git")

-- ---------------------------------------------------------------------------
-- Module-level mutable state (lives here and nowhere else)
-- ---------------------------------------------------------------------------

local view = nil ---@type Beast.Explorer.View?
local tree = nil ---@type Beast.Explorer.Tree?
local flat_nodes = {} ---@type Beast.Explorer.Node[]
local augroup = nil ---@type integer?

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Register autocmds the first time M.open() is called.
local function ensure_autocmds()
    -- stylua: ignore
    if augroup then return end
	augroup = vim.api.nvim_create_augroup("BeastExplorer", { clear = true })

	-- Clean up state when the panel window is closed by any means (q, :q, wincmd c…)
	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(ev)
            -- stylua: ignore
            if not view then return end
			local ok, closed_id = pcall(tonumber, ev.match)
			if ok and closed_id == view.win then
				view = nil
				tree = nil
				flat_nodes = {}
			end
		end,
	})

	-- R keymap fires this User event so it can trigger a refresh without a
	-- circular require back into init.lua.
	vim.api.nvim_create_autocmd("User", {
		pattern = "BeastExplorerRefresh",
		group = augroup,
		callback = function()
			if not view or not tree then
				return
			end
			Tree.refresh(tree, view.cwd)
			Git.invalidate(view.cwd)
			M._refresh()
		end,
	})
end

--- Rebuild the flat node list and push it to the panel window.
--- Fetches git status asynchronously when enabled.
function M._refresh()
    -- stylua: ignore
    if not view then return end
    -- stylua: ignore
    if not tree  then return end

	local cwd = view.cwd
	local show_hidden = config.cfg.show_hidden

	if config.cfg.git then
		Git.fetch(cwd, function(git_status)
            -- Guard: panel may have been closed while we waited for git
            -- stylua: ignore
            if not view then return end
			flat_nodes = Tree.flat(tree, cwd, { show_hidden = show_hidden, git_status = git_status })
			Win.render(view, flat_nodes)
		end)
	else
		flat_nodes = Tree.flat(tree, cwd, { show_hidden = show_hidden })
		Win.render(view, flat_nodes)
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Apply user configuration.  Call this from your setup/init file.
---@param opts Beast.Explorer.Config
function M.setup(opts)
	config.setup(opts)
end

--- Open the explorer panel rooted at `cwd`.
--- If the panel is already open, focus it instead of opening a second one.
---@param cwd? string  defaults to vim.fn.getcwd()
function M.open(cwd)
	cwd = cwd and vim.fn.fnamemodify(cwd, ":p"):gsub("/$", "") or vim.fn.getcwd()

	if view and view:is_valid() then
		pcall(vim.api.nvim_set_current_win, view.win)
		return
	end

	ensure_autocmds()

	tree = Tree.new(cwd)
	view = Win.create(cwd)
	Win.set_title(view, cwd)
	Win.set_keymaps(
		view,
		function()
			return flat_nodes
		end,
		-- on_select: open the chosen file in the previous (editing) window
		function(node)
			local prev = vim.fn.win_getid(vim.fn.winnr("#"))
			if prev ~= 0 and prev ~= view.win then
				pcall(vim.api.nvim_set_current_win, prev)
			end
			vim.cmd("edit " .. vim.fn.fnameescape(node.path))
		end,
		-- on_toggle: expand / collapse a directory then re-render
		function(node)
			Tree.toggle(tree, node.path)
			M._refresh()
		end,
		-- on_close: close the panel
		M.close
	)

	M._refresh()
end

--- Close the explorer panel.
function M.close()
    -- stylua: ignore
    if not view then return end
	Win.destroy(view)
	view = nil
	tree = nil
	flat_nodes = {}
end

--- Toggle the explorer panel open/closed.
---@param cwd? string  passed to M.open() when opening
function M.toggle(cwd)
	if view and view:is_valid() then
		M.close()
	else
		M.open(cwd)
	end
end

--- Reveal `path` in the explorer, opening it if necessary.
--- Expands all ancestor directories and moves the cursor to the target row.
---@param path string  absolute path to a file or directory
function M.reveal(path)
	path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")

	if not view or not view:is_valid() then
		M.open(vim.fn.getcwd())
	end

	-- Ensure all ancestors are open
	Tree.open(tree, path)
	-- Invalidate git so reveal always shows fresh status
	Git.invalidate(view.cwd)

	if config.cfg.git then
		Git.fetch(view.cwd, function(git_status)
            -- stylua: ignore
            if not view then return end
			flat_nodes = Tree.flat(tree, {
				show_hidden = config.cfg.show_hidden,
				git_status = git_status,
			})
			Win.render(view, flat_nodes)
			Win.reveal(view, flat_nodes, path)
			pcall(vim.api.nvim_set_current_win, view.win)
		end)
	else
		flat_nodes = Tree.flat(tree, { show_hidden = config.cfg.show_hidden })
		Win.render(view, flat_nodes)
		Win.reveal(view, flat_nodes, path)
		pcall(vim.api.nvim_set_current_win, view.win)
	end
end

--- Return true when the explorer panel is currently open.
---@return boolean
function M.is_open()
	return view ~= nil and view:is_valid()
end

-- Make the module callable as a drop-in: require("beast.libs.explorer")()
setmetatable(M, {
	__call = function(_, cwd)
		return M.toggle(cwd)
	end,
})

return M
