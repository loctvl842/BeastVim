---@class Beast.Packer.LoadProfile
---@field packadd_ms number                           -- time spent in packadd (ms)
---@field config_ms  number                           -- time spent in config() (ms)
---@field total_ms   number                           -- packadd_ms + config_ms (ms)
---@field loaded_at  integer|nil                      -- os.time() when first loaded
---@field reason     Beast.Packer.LoadReason|nil  -- Why the plugin was loaded

local profiles = {} ---@type table<string, Beast.Packer.LoadProfile>
local methods = {}

---Store or update a profile's timing data
---@private
---@param plugin_name string
---@param field 'packadd_ms'|'config_ms'
---@param delta_ms number
function methods.add_time(plugin_name, field, delta_ms)
	local prof = profiles[plugin_name] or { packadd_ms = 0, config_ms = 0, total_ms = 0, loaded_at = nil }
	prof[field] = (prof[field] or 0) + delta_ms
	prof.total_ms = (prof.packadd_ms or 0) + (prof.config_ms or 0)
	prof.loaded_at = prof.loaded_at or os.time()
	profiles[plugin_name] = prof
end

---Execute a function, measure time, and record on success
---@param plugin_name string
---@param field 'packadd_ms'|'config_ms'
---@param fn fun()
---@return boolean ok, any err
function methods.measure(plugin_name, field, fn)
	local t0 = Util.hrtime()
	local ok, err = pcall(fn)
	local t1 = Util.hrtime()
	if ok then
		methods.add_time(plugin_name, field, (t1 - t0) / 1e6)
	end
	return ok, err
end

---Store the load reason
---@param plugin_name string
---@param reason? Beast.Packer.LoadReason
function methods.set_reason(plugin_name, reason)
	if not profiles[plugin_name] then
		profiles[plugin_name] = { packadd_ms = 0, config_ms = 0, total_ms = 0, loaded_at = nil }
	end
	if not profiles[plugin_name].reason then
		profiles[plugin_name].reason = reason or { type = "manual", detail = nil }
	end
end

function methods.iter()
	return pairs(profiles)
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return profiles[key]
	end,
	__newindex = function(_, key, _)
		error(string.format("beast.packer.profile is read-only; cannot assign '%s' directly.", tostring(key)), 2)
	end,
	__pairs = function()
		return pairs(profiles)
	end,
})

return M
