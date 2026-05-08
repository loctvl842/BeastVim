local Tree = require("beast.libs.explorer.tree")
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node or not node.dir then return end

	local new_root = node.path
  -- stylua: ignore
  if new_root == state.tree.root.path then return end

	state.tree = Tree(new_root)
	ui.render()
end

return M
