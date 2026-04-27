---@class Beast.Util
---@class Beast.Util.View
local M = {}

function M.wo(win, k, v)
	if vim.api.nvim_set_option_value then
		-- 0.9+ recommended
		vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
	else -- pre-0.9, still works
		vim.wo[win][k] = v
	end
end

---@param filetype string
---@return integer
function M.create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

---@param prefix string Prefix for highlight groups e.g. "BeastNotify" -> will create "BeastNotifyInfo", "BeastNotifyWarn", etc.
---@param groups table<string, vim.api.keyset.highlight> Map of highlight group names to their definition.
function M.set_hl(prefix, groups)
	for name, def in pairs(groups) do
		local group = prefix .. name
		if def.link then
			vim.api.nvim_command("hi! link " .. group .. " " .. def.link)
		else
			vim.api.nvim_set_hl(0, group, def)
		end
	end
end

-- High-resolution timer helper
---@return integer ns Nanoseconds
function M.hrtime()
	local uv = vim.uv or vim.loop
	if uv and uv.hrtime then
		return uv.hrtime()
	end
	-- Fallback using reltime (seconds as float)
	return math.floor(vim.fn.reltimefloat(vim.fn.reltime()) * 1e9)
end

return M
