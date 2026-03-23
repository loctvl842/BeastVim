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

function M.open(cwd)
	cwd = cwd and vim.fn.fnamemodify(cwd, ":p"):gsub("/$", "") or vim.fn.getcwd()
	if state.view and state.view:is_valid() then
		pcall(vim.api.nvim_set_current_win, state.view.win)
		return
	end
	state.tree = Tree(cwd)
	state.view = ui.create(cwd)
	state.view:set_title(cwd)
	ui.render()
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
	else
		if has_file then
		-- ...
		else
			M.open(cwd)
		end
	end
end

function M.setup(opts)
	config.setup(opts)
end

return M
