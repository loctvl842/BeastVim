local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

--- Same condition as `search`: without the finder there is no search mode to leave.
---@return boolean
function M.available()
	return require("beast.libs.explorer.actions.search").available()
end

--- Leave search mode with the cursor on the row it was on.
function M.run()
	require("beast.libs.explorer.search").exit()
end

return M
