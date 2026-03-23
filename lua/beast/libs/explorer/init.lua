local Tree = require("beast.libs.explorer.tree")
---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")

local M = setmetatable({}, {
	__call = function(self, cwd)
		return self.toggle(cwd)
	end,
})

--- Calls `on_done()` after the render (after the async git fetch when enabled).
---@param cwd? string
---@param on_done? fun()
function M.open(cwd, on_done)
	cwd = cwd and vim.fn.fnamemodify(cwd, ":p"):gsub("/$", "") or vim.fn.getcwd()
	if state.view and state.view:is_valid() then
		pcall(vim.api.nvim_set_current_win, state.view.win)
		return
	end
	if not state.tree then
		state.tree = Tree(cwd)
	end
	state.view = ui.create(cwd)
	state.view:set_title(cwd)
	ui.render(on_done)
end

--- Reveal immediately a certain path in the explorer,
--- opening all parent directories as needed.
---@param path string
function M.reveal(path)
	path = vim.fn.fnamemodify(path, ":p"):gsub("/$", "")
	if not state.view or not state.view:is_valid() then
		if not state.tree then
			state.tree = Tree(vim.fn.getcwd())
		end
		state.view = ui.create(state.tree.root.path)
		state.view:set_title(state.tree.root.path)
	end
	state.tree:collapse_all()
	state.tree:open(path)
	ui.render(function()
		ui.reveal(path)
	end)
end

function M.close()
	ui.close()
end

---@param cwd? string  used only when there is no current file on first open
function M.toggle(cwd)
	if state.view and state.view:is_valid() then
		M.close()
		return
	end

	local file = vim.api.nvim_buf_get_name(0)
	local has_file = file ~= "" and vim.fn.filereadable(file) == 1

	if state.tree then
		M.open(state.tree.root.path, has_file and function()
			ui.reveal(file)
		end or nil)
	else
		if has_file then
			M.reveal(file)
		else
			M.open(cwd)
		end
	end
end

function M.setup(opts)
	config.setup(opts)
end

return M
