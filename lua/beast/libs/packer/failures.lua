---@class Beast.Packer.Failure
---@field src string Source URL the install was attempted from
---@field reason string Short reason shown to the user
---@field at integer os.time() of the failed attempt

local M = {}

local records = {} ---@type table<string, Beast.Packer.Failure>

---@param name string
---@return boolean
function M.is_installed(name)
	return vim.uv.fs_stat(vim.fn.stdpath("data") .. "/site/pack/core/opt/" .. name) ~= nil
end

--- Pull one plugin's reason out of the combined error `vim.pack.add` throws.
--- The error has one "`name`:" block per failed plugin.
---@param err any
---@param name string
---@return string
function M.reason_for(err, name)
	local msg = tostring(err)
	local _, stop = msg:find("`" .. name .. "`:", 1, true)
	local line = stop and msg:sub(stop + 1):match("[^\n]+")
	if not line then
		return "install failed"
	end
	return vim.trim((line:gsub("^%S*pack%.lua:%d+:%s*", "")))
end

---@param name string
---@param src string
---@param reason string
function M.record(name, src, reason)
	records[name] = { src = src, reason = reason, at = os.time() }
end

---@param name string
function M.clear(name)
	records[name] = nil
end

---@return table<string, Beast.Packer.Failure>
function M.list()
	return records
end

return M
