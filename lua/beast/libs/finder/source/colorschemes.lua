local M = {}

---@return Beast.Finder.Item[]
function M.get()
	-- Only include colorschemes from currently loaded plugins (in rtp)
	local rtp = vim.o.runtimepath
	local seen = {} ---@type table<string, boolean>
	local items = {}
	local idx = 0

	for _, pattern in ipairs({ "colors/*.vim", "colors/*.lua" }) do
		local files = vim.fn.globpath(rtp, pattern, true, true)
		for _, fullpath in ipairs(files) do
			local name = vim.fn.fnamemodify(fullpath, ":t:r")
			if not seen[name] then
				seen[name] = true
				idx = idx + 1
				items[#items + 1] = {
					idx = idx,
					score = 0,
					text = name,
				}
			end
		end
	end

	return items
end

return M
