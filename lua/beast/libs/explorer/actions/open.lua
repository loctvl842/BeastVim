---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")

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

---@param node Beast.Explorer.Node
local function on_toggle(node)
	state.tree:toggle(node.path)
	ui.render()
end

---@param node Beast.Explorer.Node
local function on_select(node)
	local prev = state.source_win
  -- stylua: ignore
  if prev == nil then error("No previous window found") end

	if prev ~= state.view.win and vim.api.nvim_win_is_valid(prev) then
		pcall(vim.api.nvim_set_current_win, prev)
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
	local node = current_node()
  -- stylua: ignore
  if not node then return end

	if node.dir then
		on_toggle(node)
	else
		on_select(node)
	end
end

return M
