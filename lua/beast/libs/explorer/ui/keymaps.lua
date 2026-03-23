---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")

local M = {}

---@param nodes Beast.Explorer.Node[]
function M.mount(nodes)
  -- stylua: ignore
  if not state.view:is_valid() then return end

	-- Lazy require to avoid circular dependency with ui.lua
	local ui = require("beast.libs.explorer.ui")
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
		ui.render()
	end

	---@param node Beast.Explorer.Node
	local function on_select(node)
		local prev = vim.fn.win_getid(vim.fn.winnr("#"))
		if prev ~= 0 and prev ~= state.view.win then
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

	-- <CR> / l : open file or expand/collapse directory
	local function open()
		local node = current_node()
    -- stylua: ignore
    if not node then return end
		if node.dir then
      on_toggle(node)
		else
			on_select(node)
		end
	end

	local action_handlers = {
		open = open,
	}

	for lhs, action in pairs(config.mappings) do
		vim.keymap.set("n", lhs, action_handlers[action], opts)
	end
end

return M
