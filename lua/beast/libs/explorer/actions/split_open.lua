local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

---@param node Beast.Explorer.Node
local function on_toggle(node)
	state.tree:toggle(node.path)
	ui.render()
end

---@param node Beast.Explorer.Node
local function on_split(node)
	local prev = state.source_win
  -- stylua: ignore
  if prev == nil then error("No previous window found") end

	if prev ~= state.view.win and vim.api.nvim_win_is_valid(prev) then
		pcall(vim.api.nvim_set_current_win, prev)
		vim.cmd("vsplit")
	else
		vim.wo[state.view.win].winfixwidth = false
		vim.cmd("vsplit")
		local new_win = vim.api.nvim_get_current_win()
		if state.saved_win_opts then
			for k, v in pairs(state.saved_win_opts) do
				vim.wo[new_win][k] = v
			end
		end
		vim.wo[new_win].winfixwidth = false
		vim.api.nvim_win_set_width(state.view.win, config.width)
		vim.wo[state.view.win].winfixwidth = true
	end
	vim.cmd("edit " .. vim.fn.fnameescape(node.path))
end

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end

	if node.dir then
		on_toggle(node)
	else
		on_split(node)
	end
end

return M
