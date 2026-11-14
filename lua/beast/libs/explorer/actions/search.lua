local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

--- keymaps.mount skips this action (leaving Neovim's own `/` and `?`) when it returns false.
---@return boolean
function M.available()
	local ok, finder_search = pcall(require, "beast.libs.finder.search")
	return ok and finder_search.available()
end

function M.run()
	require("beast.libs.explorer.search").prompt()
end

return M
