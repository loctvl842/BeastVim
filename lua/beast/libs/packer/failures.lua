---@class Beast.Packer.Failure
---@field src string Source URL the install was attempted from
---@field reason string Short reason shown to the user
---@field at integer os.time() of the failed attempt

local M = {}

local records ---@type table<string, Beast.Packer.Failure>|nil Lazily read from disk

local function path()
	return vim.fn.stdpath("state") .. "/beast/packer-failures.json"
end

---@return table<string, Beast.Packer.Failure>
local function all()
	if records then
		return records
	end
	records = {}
	local f = io.open(path(), "r")
	if f then
		local ok, data = pcall(vim.json.decode, f:read("*a"))
		f:close()
		if ok and type(data) == "table" then
			records = data
		end
	end
	return records
end

local function save()
	vim.fn.mkdir(vim.fn.fnamemodify(path(), ":h"), "p")
	local f = io.open(path(), "w")
	if f then
		f:write(vim.json.encode(all()))
		f:close()
	end
end

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
	all()[name] = { src = src, reason = reason, at = os.time() }
	save()
end

---@param name string
function M.clear(name)
	if all()[name] then
		all()[name] = nil
		save()
	end
end

---@return table<string, Beast.Packer.Failure>
function M.list()
	return all()
end

--- Drop records that no longer apply: plugin removed from the config, source
--- changed, or the plugin is now on disk.
---@param specs { name: string, src: string }[]
function M.prune(specs)
	local by_name = {}
	for _, spec in ipairs(specs) do
		by_name[spec.name] = spec
	end
	local dirty = false
	for name, rec in pairs(all()) do
		local spec = by_name[name]
		if not spec or spec.src ~= rec.src or M.is_installed(name) then
			all()[name] = nil
			dirty = true
		end
	end
	if dirty then
		save()
	end
end

--- True while a recorded failure is younger than the retry window.
---@param name string
---@param window_hours number
---@return boolean
function M.is_blocked(name, window_hours)
	local rec = all()[name]
	return rec ~= nil and os.time() - rec.at < window_hours * 3600
end

return M
