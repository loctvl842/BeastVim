---@class Beast.Packer.LoadProfile
---@field packadd_ms number                           -- time spent in packadd (ms)
---@field config_ms  number                           -- time spent in config() (ms)
---@field total_ms   number                           -- packadd_ms + config_ms (ms)
---@field loaded_at  integer|nil                      -- os.time() when first loaded
---@field reason     Beast.Packer.LoadReason|nil  -- Why the plugin was loaded

---@class Beast.Packer.PhaseProfile
---@field ms    number   total milliseconds across all calls
---@field calls integer  number of times this phase was measured
---@field min   number   min single-call ms
---@field max   number   max single-call ms

local profiles = {} ---@type table<string, Beast.Packer.LoadProfile>
local phases = {} ---@type table<string, Beast.Packer.PhaseProfile>
local methods = {}

---Store or update a profile's timing data
---@private
---@param plugin_name string
---@param field 'packadd_ms'|'config_ms'|'phase_ms'
---@param delta_ms number
function methods.add_time(plugin_name, field, delta_ms)
	local prof = profiles[plugin_name] or { packadd_ms = 0, config_ms = 0, total_ms = 0, loaded_at = nil }
	prof[field] = (prof[field] or 0) + delta_ms
	prof.total_ms = (prof.packadd_ms or 0) + (prof.config_ms or 0)
	prof.loaded_at = prof.loaded_at or os.time()
	profiles[plugin_name] = prof
end

---Store or update a phase's timing data
---@private
---@param name string
---@param delta_ms number
function methods.add_phase_time(name, delta_ms)
	local p = phases[name] or { ms = 0, calls = 0, min = math.huge, max = 0 }
	p.ms = p.ms + delta_ms
	p.calls = p.calls + 1
	if delta_ms < p.min then
		p.min = delta_ms
	end
	if delta_ms > p.max then
		p.max = delta_ms
	end
	phases[name] = p
end

---Execute a function, measure time, and record on success.
---When `field == "phase_ms"`, the timing is recorded in the per-phase
---table; otherwise it is recorded in the per-plugin profile.
---@param name string  plugin name (per-plugin) OR phase name (phase_ms)
---@param field 'packadd_ms'|'config_ms'|'phase_ms'
---@param fn fun()
---@return boolean ok, any err
function methods.measure(name, field, fn)
	local t0 = Util.hrtime()
	local ok, err = pcall(fn)
	local t1 = Util.hrtime()
	if ok then
		local delta_ms = (t1 - t0) / 1e6
		if field == "phase_ms" then
			methods.add_phase_time(name, delta_ms)
		else
			methods.add_time(name, field, delta_ms)
		end
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
		if key == "phases" then
			return phases
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
