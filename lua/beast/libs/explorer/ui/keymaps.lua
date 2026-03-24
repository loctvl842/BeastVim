---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local create = require("beast.libs.explorer.ui.create")

local M = {}

--- Bind buffer-local keymaps for the explorer.
--- Called after every render so that the `nodes` closure stays fresh.
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

	-- a : create file or folder inside the target directory
	local function do_create()
		local node = current_node()
    -- stylua: ignore
    if not node then return end

		local target_dir = node.dir and node or state.tree.nodes[node.parent]
    -- stylua: ignore
    if not target_dir then return end

		local function show_popup()
			local fresh = state.tree:flat({ show_hidden = config.show_hidden })

			local dir_line = 1 -- below header for root
			if target_dir.depth ~= -1 then
				for i, n in ipairs(fresh) do
					if n.path == target_dir.path then
						dir_line = i + 1 -- +1 for header line
						break
					end
				end
			end

			local has_children = false
			for _, n in ipairs(fresh) do
				if n.parent == target_dir.path then
					has_children = true
					break
				end
			end

			create.open(target_dir, dir_line, not has_children, function(full_path, _)
				state.tree:refresh(target_dir.path)
				state.tree:open(full_path)
				ui.render(function()
					ui.focus_path(full_path)
				end)
			end)
		end

		-- Open closed directory first so children are visible before the popup
		if target_dir.dir and not target_dir.open then
			state.tree:open(target_dir.path)
			ui.render(show_popup)
		else
			show_popup()
		end
	end

	local action_handlers = {
		open = open,
		create = do_create,
	}

	for lhs, action in pairs(config.mappings) do
		vim.keymap.set("n", lhs, action_handlers[action], opts)
	end
end

return M
