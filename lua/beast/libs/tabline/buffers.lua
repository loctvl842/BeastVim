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

--- Pick a fallback buffer to switch to: alternate buffer first,
--- then the most recently used listed buffer.
---@param exclude? integer[] buffers to skip
---@return integer?
function M.find_fallback_buffer(exclude)
	local excluded = {}
	for _, bufnr in ipairs(exclude or {}) do
		excluded[bufnr] = true
	end

	-- Prefer alternate buffer first.
	local alt = vim.fn.bufnr("#")
	if alt > 0 and not excluded[alt] and vim.fn.buflisted(alt) == 1 and vim.api.nvim_buf_is_valid(alt) then
		return alt
	end

	-- Then most recently used listed buffer.
	local infos = vim.fn.getbufinfo({ buflisted = 1 })
	table.sort(infos, function(a, b)
		return (a.lastused or 0) > (b.lastused or 0)
	end)

	for _, info in ipairs(infos) do
		if not excluded[info.bufnr] and vim.api.nvim_buf_is_valid(info.bufnr) then
			return info.bufnr
		end
	end

	return nil
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

--- Delete listed file buffers whose backing file no longer exists on disk
--- (external `rm`/`mv`). Modified buffers are kept so unsaved changes are
--- never lost silently. If the current buffer is removed, focus moves to a
--- fallback buffer first.
---@return boolean removed whether any buffer was deleted
function M.cleanup_stale()
	local current = vim.api.nvim_get_current_buf()
	local stale = {}

	for _, bufnr in ipairs(M.list()) do
		if vim.api.nvim_buf_is_valid(bufnr) and not M.is_sidebar_buf(bufnr) and vim.bo[bufnr].buftype == "" then
			local name = vim.api.nvim_buf_get_name(bufnr)
			local missing = name ~= "" and (vim.uv.fs_stat(name) or {}).type ~= "file"
			if missing and not vim.bo[bufnr].modified then
				stale[#stale + 1] = bufnr
			end
		end
	end

	if #stale == 0 then
		return false
	end

	-- Switch away from a stale current buffer before deleting it.
	if vim.tbl_contains(stale, current) then
		local fallback = M.find_fallback_buffer(stale)
		if fallback then
			pcall(vim.api.nvim_set_current_buf, fallback)
		else
			pcall(vim.api.nvim_set_current_buf, vim.api.nvim_create_buf(true, false))
		end
	end

	local removed = false
	for _, bufnr in ipairs(stale) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			removed = pcall(vim.api.nvim_buf_delete, bufnr, { force = false }) or removed
		end
	end

	return removed
end

return M
