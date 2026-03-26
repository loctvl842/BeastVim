local Tree = require("beast.libs.explorer.tree")
---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.run()
  -- stylua: ignore
  if not state.tree then return end

	local current_root = state.tree.root.path
	local parent = vim.fn.fnamemodify(current_root, ":h")

  -- stylua: ignore
  if parent == current_root then return end -- already at filesystem root

	state.tree = Tree(parent)
	state.tree:open(current_root)
	state.view:set_title(parent)
	state.view.cwd = parent
	ui.render(function()
		ui.focus_path(current_root)
	end)
end

return M
