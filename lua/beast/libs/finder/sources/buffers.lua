local M = {}

---@param filter Beast.Finder.Filter
---@return Beast.Finder.Item[]
function M.get(filter)
	local raw = vim.fn.getbufinfo({ buflisted = 1 })
	local items = {}
	for i, info in ipairs(raw) do
		local name = vim.api.nvim_buf_get_name(info.bufnr)
		-- Skip beast UI buffers
		local ft = vim.bo[info.bufnr].filetype or ""
		if not ft:match("^beastvim%-") then
			items[#items + 1] = {
				idx = i,
				score = 0,
				text = name ~= "" and name or ("[No Name] " .. info.bufnr),
				buf = info.bufnr,
				file = name ~= "" and name or nil,
				cwd = filter.cwd,
			}
		end
	end
	return items
end

return M
