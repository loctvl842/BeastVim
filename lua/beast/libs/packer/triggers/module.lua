local state = require("beast.libs.packer.state")

local M = {}

--- Custom module loader for lazy plugins
---@param modname string The module being required
---@param load_fn function Function to load the plugin
---@return function|nil loader function or nil
function M.loader(modname, load_fn)
	-- Check if this module belongs to a lazy plugin
	local plugin_name = state.module_to_plugin[modname]

	if not plugin_name then
		-- Not a lazy plugin module, let other loaders handle it
		return nil
	end

	if state.loaded_plugins[plugin_name] then
		-- Plugin already loaded, let normal loader find the module
		return nil
	end

	-- Load the plugin!
	-- Pass the module name that triggered the load
	load_fn(plugin_name, { type = "module", detail = modname })

	-- Now let Lua's normal loaders find the module
	-- (the plugin is now loaded, so the module should be available)
	return nil
end

M._installed = false

--- Install the module loader into package.loaders
---@param load_fn function Function to load the plugin
function M.install(load_fn)
	if M._installed then
		return
	end

	---@diagnostic disable-next-line: deprecated
	local searchers = package.searchers or package.loaders
	local inserter = function()
		table.insert(searchers, 2, function(modname)
			return M.loader(modname, load_fn)
		end)
	end

	inserter()
	M._installed = true
end

--- Register a module → plugin mapping
---@param module_name string The module name (e.g., "telescope")
---@param plugin_name string The plugin name (e.g., "telescope.nvim")
function M.register(module_name, plugin_name)
	state.module_to_plugin[module_name] = plugin_name
end

return M
