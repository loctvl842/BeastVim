local state = require("beast.libs.packer.state")

local M = {}

--- Custom module loader for lazy plugins and Beast libs.
--- On `require(modname)`:
---   1. If modname is mapped to a lazy plugin → call load_plugin (packadd).
---   2. Else if modname is mapped to a Beast lib → call load_lib (require + setup).
---   3. Else return nil (let Lua's normal loaders handle it).
---@param modname string The module being required
---@param load_plugin fun(plugin_name: string, reason?: Beast.Packer.LoadReason) Plugin loader (state.load)
---@param load_lib fun(lib_name: string, reason?: Beast.Packer.LoadReason) Lib loader (state.load_lib)
---@return function|nil loader function or nil
function M.loader(modname, load_plugin, load_lib)
	-- Plugin route
	local plugin_name = state.module_to_plugin[modname]
	if plugin_name then
		if state.loaded_plugins[plugin_name] then
			return nil
		end
		load_plugin(plugin_name, { type = "module", detail = modname })
		return nil
	end

	-- Lib route
	local lib_name = state.module_to_lib[modname]
	if lib_name then
		if state.loaded_libs[lib_name] then
			return nil
		end
		load_lib(lib_name, { type = "module", detail = modname })
		return nil
	end

	return nil
end

M._installed = false

--- Install the module loader into package.loaders
---@param load_plugin fun(plugin_name: string, reason?: Beast.Packer.LoadReason)
---@param load_lib fun(lib_name: string, reason?: Beast.Packer.LoadReason)
function M.install(load_plugin, load_lib)
	if M._installed then
		return
	end

	---@diagnostic disable-next-line: deprecated
	local searchers = package.searchers or package.loaders
	local inserter = function()
		table.insert(searchers, 2, function(modname)
			return M.loader(modname, load_plugin, load_lib)
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

--- Register a module → Beast lib mapping (for packer.lazy() entries)
---@param module_name string The module name a caller might require (e.g., "beast.libs.finder")
---@param lib_name string The lib registry key (the `mod` passed to packer.lazy)
function M.register_lib(module_name, lib_name)
	state.module_to_lib[module_name] = lib_name
end

return M
