local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

local function set_clipboard(paths)
	if state.clipboard and state.clipboard.mode == "copy" then
		state.clipboard = nil
	else
		state.clipboard = { paths = paths, mode = "copy" }
	end
	ui.render()
end

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node or node.depth == -1 then return end
	set_clipboard({ node.path })
end

function M.run_visual()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	local flat = state.tree:flat({ show_hidden = config.show_hidden })
	local paths = {}
	for line = start_line, end_line do
		local idx = line - 1 -- row 1 = header; nodes[1] = line 2
		if idx >= 1 and flat[idx] and flat[idx].depth ~= -1 then
			table.insert(paths, flat[idx].path)
		end
	end
  -- stylua: ignore
  if #paths == 0 then return end
	set_clipboard(paths)
end

return M
