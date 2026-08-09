---@class Beast.Select.Filter
local M = {}

--- Case-insensitive, literal (non-pattern) substring test. An empty query
--- matches everything.
---@param text string
---@param query string
---@return boolean
function M.matches(text, query)
	if query == "" then
		return true
	end
	return text:lower():find(query:lower(), 1, true) ~= nil
end

return M
