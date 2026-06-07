---@class Beast.Packer.Lazy
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
---@field lazy? Beast.Packer.Lazy|false Packer loading configuration (if false, loads eagerly; if nil, loads manually)
---@field init? fun() Initialization function (runs during setup, before loading)
---@field config? fun() Configuration function (runs after plugin loads)
---@field build? string|string[] Build step to run after install/update (like lazy.nvim)
---@field version? string|vim.VersionRange Version constraint passed to `vim.pack.add` (e.g. `vim.version.range("*")`)

-- Track packer vs startup plugins
---@class Beast.Packer.LoadReason
---@field type "event"|"cmd"|"keys"|"module"|"filetype"|"path"|"dependency"|"manual"|"eager"
---@field detail string|nil -- Event name, command name, key sequence, module name, or parent plugin

local operation = require("beast.libs.packer.operation")
local profile = require("beast.libs.packer.profile")

---@class Beast.Packer.State
local M = {
	plugins = {}, ---@type table<string, Beast.Packer.PluginSpec> All plugins
	installed_plugins = {}, ---@type table<string, boolean> Plugins that have been installed
	loaded_plugins = {}, ---@type table<string, boolean> Plugins that have been loaded
	module_to_plugin = {}, ---@type table<string, string> Map module names to plugin names
}

-- Track plugins currently being loaded (for circular dependency detection)
local loading_stack = {} ---@type string[] Array for ordered tracking

---@private
function M.check_circular_dependency(plugin_name)
	for _, name in ipairs(loading_stack) do
		if name == plugin_name then
			table.insert(loading_stack, plugin_name) -- Add to show the cycle
			local msg = "Circular dependency detected: " .. table.concat(loading_stack, " -> ")
			vim.notify(msg, vim.log.levels.ERROR, { title = "BeastVim" })
			error(msg)
		end
	end
end

---@param plugin_name string
local function start_load(plugin_name)
	-- Mark as being loaded (for circular dependency detection)
	table.insert(loading_stack, plugin_name)
	operation.start(plugin_name, "load")
end

---Clean up after loading (pop stack and record operation)
---@param plugin_name string
---@param success boolean
---@param message string|nil
local function finish_load(plugin_name, success, message)
	table.remove(loading_stack)
	operation.complete(plugin_name, success, message)
end

--- Load a plugin manually
---@param plugin_name string Name of the plugin to load
---@param reason? Beast.Packer.LoadReason Why the plugin is being loaded
function M.load(plugin_name, reason) -- Already loaded
  -- stylua: ignore
  if M.loaded_plugins[plugin_name] then return end

	M.check_circular_dependency(plugin_name)
	start_load(plugin_name)

	-- Find the spec
	local spec = M.plugins[plugin_name]

	-- Load dependencies first (recursively)
	if spec and spec.dependencies then
		for _, dep_name in ipairs(spec.dependencies) do
			M.load(dep_name, { type = "dependency", detail = plugin_name })
		end
	end

	-- Measure packadd time using wrapper
	local ok_packadd, err_packadd = profile.measure(plugin_name, "packadd_ms", function()
		Toast("Loading " .. plugin_name, vim.log.levels.INFO, { title = "BeastVim", silent = true })
		M.loaded_plugins[plugin_name] = true
		vim.cmd.packadd(plugin_name)
		-- Store load reason in profile
		profile.set_reason(plugin_name, reason)
	end)

	if not ok_packadd then
		finish_load(plugin_name, false, tostring(err_packadd))
		vim.notify("Failed to load " .. plugin_name .. ": " .. tostring(err_packadd), vim.log.levels.ERROR, { title = "BeastVim" })
		return
	end

	-- Run plugin config if available and not already configured
	if spec and spec.config then
		local ok_cfg, err_cfg = profile.measure(plugin_name, "config_ms", spec.config)
		if not ok_cfg then
			finish_load(plugin_name, false, tostring(err_cfg))
			vim.notify("Error in config for " .. plugin_name .. ": " .. tostring(err_cfg), vim.log.levels.ERROR, { title = "BeastVim" })
			return
		end
	end

	-- Remove from loading stack (successfully loaded)
	finish_load(plugin_name, true, "loaded")
	-- Profile already recorded (packadd_ms, config_ms)
end

--- Get total number of plugins
---@return integer
function M.total()
	local total = 0
	for _ in pairs(M.plugins) do
		total = total + 1
	end
	return total
end

--- Install the module loader into package.loaders
---@param module_trigger table The module trigger module
function M.install_module_loader(module_trigger)
	module_trigger.install(M.load)
end

return M
