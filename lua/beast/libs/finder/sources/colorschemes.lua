local M = {}

---@param _filter Beast.Finder.Filter
---@return Beast.Finder.Item[]
function M.get(_filter)
	local schemes = vim.fn.getcompletion("", "color")
	local items = {}
	for i, name in ipairs(schemes) do
		items[#items + 1] = {
			idx = i,
			score = 0,
			text = name,
		}
	end
	return items
end

return M
