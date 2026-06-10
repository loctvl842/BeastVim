local git_jump = require("beast.libs.explorer.actions._git_jump")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

function M.run()
	git_jump.jump("prev")
end

return M
