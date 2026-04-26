---@class Beast.Packer.Config
---@field event? string|string[] Event(s) to trigger lazy loading (e.g., "BufRead", "VimEnter")
---@field cmd? string|string[] Command(s) to trigger lazy loading (e.g., "Telescope")
---@field keys? Beast.KeymapSpec|Beast.KeymapSpec[]|string|string[] Keymap(s) to trigger lazy loading
---@field module? string|string[] Module name(s) that trigger lazy loading on require()
---@field filetype? string|string[] Filetype(s) to trigger lazy loading (e.g., "rust", {"go", "gomod"})
---@field path? string|string[] Path pattern(s) to trigger lazy loading (e.g., ".github/**", "*_test.go")

---@class Beast.Packer.PluginSpec
---@field name? string Plugin name (must match plugin directory name) - required for plugin specs, nil for import specs
---@field src? string Git repository URL (e.g., "https://github.com/user/repo") - required for plugin specs, nil for import specs
---@field import? string Module path to import specs from (e.g., "beastvim.plugins")
---@field cond? fun(): boolean Condition function for conditional imports
---@field enabled? boolean Whether to process this import (default: true)
---@field cond? fun(): boolean Condition function for conditional imports
---@field dependencies? string[] List of dependency plugin names that must be loaded before this plugin
---@field packer? Beast.Packer.Config|false Packer loading configuration (if false, loads eagerly; if nil, loads manually)
---@field init? fun() Initialization function (runs during setup, before loading)
---@field config? fun() Configuration function (runs after plugin loads)
---@field build? string|string[]|fun(spec: Beast.Packer.PluginSpec, dir: string) Build step to run after install/update (like lazy.nvim)

-- Track packer vs startup plugins
---@class Beast.Packer.LoadReason
---@field type "event"|"cmd"|"keys"|"module"|"filetype"|"path"|"dependency"|"manual"|"eager"
---@field detail string|nil -- Event name, command name, key sequence, module name, or parent plugin

---@class Beast.Packer.LoadProfile
---@field packadd_ms number                           -- time spent in packadd (ms)
---@field config_ms  number                           -- time spent in config() (ms)
---@field total_ms   number                           -- packadd_ms + config_ms (ms)
---@field loaded_at  integer|nil                      -- os.time() when first loaded
---@field reason     Beast.Packer.LoadReason|nil  -- Why the plugin was loaded

---@class Beast.Packer.OperationStatus
---@field status "pending"|"in_progress"|"success"|"error"
---@field kind "install"|"update"|"load"
---@field message string|nil
---@field start_time integer      -- os.time() when started
---@field start_time_hr integer   -- hrtime() for precise elapsed
---@field elapsed_ms number|nil   -- Calculated elapsed time in ms

---@class Beast.Packer.State
---@field lazy_plugins Beast.Packer.PluginSpec[] Plugins to load later
---@field loaded_plugins table<string, boolean> Plugins that have been loaded
---@field module_to_plugin table<string, string> Map module names to plugin names
---@field load_profiles table<string, Beast.Packer.LoadProfile> Map plugin name -> profile timings
---@field operation_status table<string, Beast.Packer.OperationStatus> Track ongoing operations
---@field has_active_operations boolean Quick check for active operations
---@field configured_plugins table<string, boolean> Plugins that have had config() run
local M = {
	lazy_plugins = {},
	loaded_plugins = {},
	module_to_plugin = {},
	load_profiles = {},
	operation_status = {},
	has_active_operations = false,
	configured_plugins = {},
}

-- Track plugins currently being loaded (for circular dependency detection)
local loading_stack = {}

--- Helper to find a plugin spec by name
---@param plugin_name string
---@return Beast.Packer.PluginSpec|nil
local function find_spec(plugin_name)
	for _, spec in ipairs(M.lazy_plugins) do
		if spec.name == plugin_name then
			return spec
		end
	end
	return nil
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

---Ensure and update a plugin's load profile
---@param plugin_name string
---@param field 'packadd_ms'|'config_ms'
---@param delta_ms number
function M.add_time(plugin_name, field, delta_ms)
	local prof = M.load_profiles[plugin_name] or { packadd_ms = 0, config_ms = 0, total_ms = 0, loaded_at = nil }
	prof[field] = (prof[field] or 0) + delta_ms
	prof.total_ms = (prof.packadd_ms or 0) + (prof.config_ms or 0)
	prof.loaded_at = prof.loaded_at or os.time()
	M.load_profiles[plugin_name] = prof
end

---Profile a function and add time to a plugin's profile on success
---@param plugin_name string
---@param field 'packadd_ms'|'config_ms'
---@param fn fun()
---@return boolean ok, any err
function M.profile(plugin_name, field, fn)
	local t0 = M.hrtime()
	local ok, err = pcall(fn)
	local t1 = M.hrtime()
	if ok then
		M.add_time(plugin_name, field, (t1 - t0) / 1e6)
	end
	return ok, err
end

--- Load a plugin manually
---@param plugin_name string Name of the plugin to load
---@param reason Beast.Packer.LoadReason|nil Why the plugin is being loaded
function M.load(plugin_name, reason) -- Already loaded
  -- stylua: ignore
  if M.loaded_plugins[plugin_name] then return end

	if loading_stack[plugin_name] then
		local chain = {}
		for name, _ in pairs(loading_stack) do
			table.insert(chain, name)
		end
		table.insert(chain, plugin_name)
		local msg = "Circular dependency detected: " .. table.concat(chain, " -> ")
		vim.notify(msg, vim.log.levels.ERROR, { title = "BeastVim" })
		error(msg)
	end

	-- Mark as being loaded (for circular dependency detection)
	loading_stack[plugin_name] = true

	-- Find the spec
	local spec = find_spec(plugin_name)

	-- Load dependencies first (recursively)
	if spec and spec.dependencies then
		for _, dep_name in ipairs(spec.dependencies) do
			M.load(dep_name, { type = "dependency", detail = plugin_name })
		end
	end

	-- Start operation tracking
	M.start_operation(plugin_name, "load")

	Toast("Loading " .. plugin_name, vim.log.levels.INFO, { title = "BeastVim", silent = true })
	-- Measure packadd time using wrapper
	local ok, err = M.profile(plugin_name, "packadd_ms", function()
		vim.cmd.packadd(plugin_name)
	end)

	if not ok then
		loading_stack[plugin_name] = nil -- Remove from stack on error
		M.complete_operation(plugin_name, false, tostring(err))
		vim.notify(
			"Failed to load " .. plugin_name .. ": " .. tostring(err),
			vim.log.levels.ERROR,
			{ title = "BeastVim" }
		)
		return
	end

	M.loaded_plugins[plugin_name] = true

	-- Store load reason in profile
	if not M.load_profiles[plugin_name] then
		M.load_profiles[plugin_name] = { packadd_ms = 0, config_ms = 0, total_ms = 0, loaded_at = nil, reason = nil }
	end
	if not M.load_profiles[plugin_name].reason then
		M.load_profiles[plugin_name].reason = reason or { type = "manual", detail = nil }
	end

	-- Run plugin config if available and not already configured
	if spec and spec.config and not M.configured_plugins[plugin_name] then
		local ok_cfg, err_cfg = M.profile(plugin_name, "config_ms", spec.config)
		if not ok_cfg then
			loading_stack[plugin_name] = nil -- Remove from stack on error
			M.complete_operation(plugin_name, false, tostring(err_cfg))
			vim.notify(
				"Error in config for " .. plugin_name .. ": " .. tostring(err_cfg),
				vim.log.levels.ERROR,
				{ title = "BeastVim" }
			)
			return
		end
		M.configured_plugins[plugin_name] = true
	end

	-- Remove from loading stack (successfully loaded)
	loading_stack[plugin_name] = nil

	M.complete_operation(plugin_name, true, "loaded")
	-- Profile already recorded (packadd_ms, config_ms)
end

-- High-resolution timer helper
---@return integer ns Nanoseconds
local function hrtime()
	local uv = vim.uv or vim.loop
	if uv and uv.hrtime then
		return uv.hrtime()
	end
	-- Fallback using reltime (seconds as float)
	return math.floor(vim.fn.reltimefloat(vim.fn.reltime()) * 1e9)
end

--- Install the module loader into package.loaders
---@param module_trigger table The module trigger module
function M.install_module_loader(module_trigger)
	module_trigger.install(M.load)
end

--- Start tracking an operation
---@param plugin_name string Name of the plugin
---@param kind "install"|"update"|"load" Type of operation
function M.start_operation(plugin_name, kind)
	M.operation_status[plugin_name] = {
		status = "in_progress",
		kind = kind,
		message = nil,
		start_time = os.time(),
		start_time_hr = hrtime(),
		elapsed_ms = nil,
	}
	M.has_active_operations = true
end

--- Complete an operation and calculate elapsed time
---@param plugin_name string Name of the plugin
---@param success boolean Whether the operation succeeded
---@param message string|nil Optional status message
function M.complete_operation(plugin_name, success, message)
	local op = M.operation_status[plugin_name]
  -- stylua: ignore
	if not op then return end

	local elapsed_ns = M.hrtime() - op.start_time_hr
	op.elapsed_ms = elapsed_ns / 1e6 -- Convert to milliseconds
	op.status = success and "success" or "error"
	op.message = message

	-- Check if any operations still active
	M.has_active_operations = false
	for _, status in pairs(M.operation_status) do
		if status.status == "in_progress" or status.status == "pending" then
			M.has_active_operations = true
			break
		end
	end
end

--- Clear all completed operations (success or error status)
function M.clear_completed_operations()
	for plugin_name, status in pairs(M.operation_status) do
		if status.status == "success" or status.status == "error" then
			M.operation_status[plugin_name] = nil
		end
	end

	-- Recheck if any operations are still active
	M.has_active_operations = false
	for _, status in pairs(M.operation_status) do
		if status.status == "in_progress" or status.status == "pending" then
			M.has_active_operations = true
			break
		end
	end
end

return M
