local config = require("beast.libs.explorer.config")
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

	config.toggle_hidden()
	state.tree:_touch()
	ui.render()
end

return M
