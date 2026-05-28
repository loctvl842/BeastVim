local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end

	local _, err = vim.ui.open(node.path)
	if err then
		vim.notify("Failed to open `" .. node.path .. "`:\n- " .. err, vim.log.levels.ERROR)
	end
end

return M
