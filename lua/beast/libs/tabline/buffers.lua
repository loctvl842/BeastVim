local config = require("beast.libs.tabline.config")

local M = {}

--- Cached file identity for rename detection (bufnrs are reused, so path is checked).
---@type table<integer, { dev: integer, ino: integer, path: string }>
local file_id = {}

--- Remember a buffer's on-disk identity so a later same-dir rename can be rewired.
---@param bufnr integer
function M.remember_file(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	if vim.bo[bufnr].buftype ~= "" then
		return
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return
	end
	local st = vim.uv.fs_stat(name)
	if st and st.type == "file" and st.dev and st.ino then
		file_id[bufnr] = { dev = st.dev, ino = st.ino, path = name }
	end
end

--- Find a same-directory file that matches the cached identity of a missing path.
---@param bufnr integer
---@param old_path string
---@return string?
local function find_renamed_path(bufnr, old_path)
	local id = file_id[bufnr]
	if not id or id.path ~= old_path then
		return nil
	end

	local parent = vim.fs.dirname(old_path)
	local handle = vim.uv.fs_scandir(parent)
	if not handle then
		return nil
	end

	while true do
		local entry = vim.uv.fs_scandir_next(handle)
		if not entry then
			break
		end
		local candidate = vim.fs.joinpath(parent, entry)
		if candidate ~= old_path then
			local st = vim.uv.fs_stat(candidate)
			if st and st.type == "file" and st.dev == id.dev and st.ino == id.ino then
				return candidate
			end
		end
	end

	return nil
end

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

--- Sync listed file buffers with the filesystem.
--- - Same-directory external rename (`mv old new`): rewire buffer name to the new path.
--- - External delete (`rm`): drop unmodified buffers; keep modified ones.
--- If the current buffer is deleted, focus moves to a fallback buffer first.
---@return boolean changed whether any buffer was renamed or deleted
function M.cleanup_stale()
	local current = vim.api.nvim_get_current_buf()
	local stale = {}
	local changed = false

	for _, bufnr in ipairs(M.list()) do
		if vim.api.nvim_buf_is_valid(bufnr) and not M.is_sidebar_buf(bufnr) and vim.bo[bufnr].buftype == "" then
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name ~= "" then
				local st = vim.uv.fs_stat(name)
				if st and st.type == "file" then
					M.remember_file(bufnr)
				else
					-- Path gone: try same-dir rename via cached inode, else mark for delete.
					local new_path = find_renamed_path(bufnr, name)
					if new_path then
						local existing = vim.fn.bufnr(new_path)
						if existing == -1 or existing == bufnr then
							if pcall(vim.api.nvim_buf_set_name, bufnr, new_path) then
								-- set_name leaves an unlisted ghost buffer on the old path; wipe it.
								local ghost = vim.fn.bufnr(name)
								if ghost > 0 and ghost ~= bufnr then
									pcall(vim.api.nvim_buf_delete, ghost, { force = true })
								end
								file_id[bufnr] = nil
								M.remember_file(bufnr)
								changed = true
							end
						elseif not vim.bo[bufnr].modified then
							stale[#stale + 1] = bufnr
						end
					elseif not vim.bo[bufnr].modified then
						stale[#stale + 1] = bufnr
					end
				end
			end
		end
	end

	if #stale == 0 then
		return changed
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

	for _, bufnr in ipairs(stale) do
		if vim.api.nvim_buf_is_valid(bufnr) then
			if pcall(vim.api.nvim_buf_delete, bufnr, { force = false }) then
				file_id[bufnr] = nil
				changed = true
			end
		end
	end

	return changed
end

return M
