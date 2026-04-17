---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")
local prompt = require("beast.libs.explorer.prompt")

local uv = vim.uv or vim.loop
local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end
  -- stylua: ignore
  if node.depth == -1 then return end -- cannot rename root

	local flat = state.tree:flat({ show_hidden = config.show_hidden })
	local node_line = 1
	for i, n in ipairs(flat) do
		if n.path == node.path then
			node_line = i + 1 -- +1 for header
			break
		end
	end
	prompt.overlay(node, node_line, function(input)
		if input == node.name then
			return
		end

		local parent_path = node.parent or vim.fs.dirname(node.path)
		local new_path = parent_path .. "/" .. input

		if uv.fs_stat(new_path) then
			vim.notify("Already exists: " .. input, vim.log.levels.WARN)
			return false
		end

		return function()
			local ok, err = uv.fs_rename(node.path, new_path)
			if not ok then
				vim.notify("Rename failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
				return
			end

			-- Update any open buffers pointing to the old path
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) then
					local buf_name = vim.api.nvim_buf_get_name(buf)
					if buf_name == node.path or buf_name:find(node.path .. "/", 1, true) == 1 then
						local new_name = new_path .. buf_name:sub(#node.path + 1)
						vim.api.nvim_buf_set_name(buf, new_name)
					end
				end
			end

			state.clipboard = nil -- avoid side-effect from clipboard
			state.tree:refresh(parent_path)
			ui.render(function()
				ui.focus_path(new_path)
			end)
		end
	end)
end

return M
