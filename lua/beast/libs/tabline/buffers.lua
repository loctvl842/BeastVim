local config = require("beast.libs.tabline.config")

local M = {}

--- Check if a buffer is a sidebar based on its filetype.
---@param bufnr integer
---@return boolean
function M.is_sidebar_buf(bufnr)
	local ok, ft = pcall(function()
		return vim.bo[bufnr].filetype
	end)
	-- stylua: ignore
	if not ok or not ft then return false end
	return config.sidebar_filetypes[ft] ~= nil
end

--- Get the sidebar title for a buffer's filetype, or nil if not a sidebar.
---@param bufnr integer
---@return string|nil
function M.sidebar_title(bufnr)
	local ok, ft = pcall(function()
		return vim.bo[bufnr].filetype
	end)
	-- stylua: ignore
	if not ok or not ft then return nil end
	return config.sidebar_filetypes[ft]
end

--- Return sorted listed buffers, hiding empty [No Name] buffers.
--- When every buffer carries a b:buffer_order variable, sort by that instead.
---@return integer[]
function M.list()
	local bufs = {}
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		if info.name ~= "" or info.changed == 1 then
			bufs[#bufs + 1] = info.bufnr
		end
	end

	-- Check if every buffer has b:buffer_order set
	local all_have_order = #bufs > 0
	if all_have_order then
		for _, bufnr in ipairs(bufs) do
			local ok = pcall(vim.api.nvim_buf_get_var, bufnr, "buffer_order")
			if not ok then
				all_have_order = false
				break
			end
		end
	end

	if all_have_order then
		table.sort(bufs, function(a, b)
			return vim.api.nvim_buf_get_var(a, "buffer_order") < vim.api.nvim_buf_get_var(b, "buffer_order")
		end)
	else
		table.sort(bufs)
	end

	return bufs
end

return M
