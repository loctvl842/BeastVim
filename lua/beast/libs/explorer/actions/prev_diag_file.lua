local diag_jump = require("beast.libs.explorer.actions._diag_jump")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.run()
	diag_jump.jump("prev")
end

return M
