-- stylua: ignore start
local cmd_trigger       = require("beast.libs.packer.triggers.cmd")
local event_trigger     = require("beast.libs.packer.triggers.event")
local filetype_trigger  = require("beast.libs.packer.triggers.filetype")
local import            = require("beast.libs.packer.import")
local keys_trigger      = require("beast.libs.packer.triggers.keys")
local module_trigger    = require("beast.libs.packer.triggers.module")
local operation         = require("beast.libs.packer.operation")
local path_trigger      = require("beast.libs.packer.triggers.path")
local profile           = require("beast.libs.packer.profile")
local state             = require("beast.libs.packer.state")
local ui                = require("beast.libs.packer.ui")
-- stylua: ignore end

local M = {}

-- ================================
-- Utils
-- ================================
local function extract_name_from_src(src)
	if type(src) ~= "string" or src == "" then
		error("extract_name_from_src: src must be a non-empty string")
	end

	-- Remove .git suffix
	local name = src:gsub("%.git$", "")

	-- Extract last segment after /
	name = name:match("[^/]+$") or ""

	if name == "" then
		error("extract_name_from_src: could not extract name from src: " .. src)
	end

	return name
end

local function normalize_spec(spec)
	if not spec.src then
		error("normalize_spec: spec must have a src field")
	end

	-- If name is already provided, use it
	if spec.name and spec.name ~= "" then
		return spec
	end

	-- Extract name from src
	spec.name = extract_name_from_src(spec.src)

	return spec
end

-- ================================
-- Methods
-- ================================
---@private
function M.install_module_loader()
	state.install_module_loader(module_trigger)
end

---@param spec Beast.Packer.PluginSpec
local function run_cmd(spec)
	local cmd = spec.build
	local name = spec.name ---@type string
	local dir = vim.fn.stdpath("data") .. "/site/pack/core/opt/" .. name

  -- stylua: ignore
  if cmd == nil then return end

	local is_win = (vim.loop.os_uname().version or ""):match("Windows") ~= nil or vim.fn.has("win32") == 1
	-- Helper to ensure plugin is loaded before running Ex commands
	local function ensure_loaded()
		if not state.loaded_plugins[name] then
			state.load(name, { type = "dependency", detail = "build" })
		end
	end
	local function run_one(c)
    -- stylua: ignore
    if type(c) ~= "string" then return end
		-- Ex command (":Cmd args") vs shell/exec
		if c:sub(1, 1) == ":" then
			ensure_loaded()
			local ex = c:sub(2) -- drop leading ':'
			-- Ensure remote plugin commands are registered (parity with lazy.nvim)
			pcall(function()
				vim.cmd([[silent! runtime plugin/rplugin.vim]])
			end)
			-- Use nvim_cmd with parsed command for robust execution
			local ok_ex, err_ex = pcall(vim.api.nvim_cmd, vim.api.nvim_parse_cmd(ex, {}), {})
			if not ok_ex then
				vim.notify("Build cmd failed for " .. name .. ": " .. tostring(err_ex), vim.log.levels.ERROR, { title = "BeastVim" })
			end
			return
		end
		if vim.system then
			local sh = is_win and { "cmd", "/C", c } or { "sh", "-lc", c }
			vim.system(sh, { cwd = dir, text = true }, function(res)
				if res.code ~= 0 then
					vim.schedule(function()
						vim.notify("Build failed for " .. name .. ": " .. (res.stderr or res.stdout or ""), vim.log.levels.ERROR, { title = "BeastVim" })
					end)
				end
			end)
		else
			-- Fallback to systemlist (synchronous)
			local cwd_save = vim.fn.getcwd()
			vim.cmd(("lcd %s"):format(dir))
			local out = vim.fn.systemlist(c)
			vim.cmd(("lcd %s"):format(cwd_save))
			if vim.v.shell_error ~= 0 then
				vim.notify("Build failed for " .. name .. ": " .. table.concat(out, "\n"), vim.log.levels.ERROR, { title = "BeastVim" })
			end
		end
	end
	if type(cmd) == "string" then
		run_one(cmd)
	elseif vim.islist(cmd) then
		for _, c in ipairs(cmd) do
			run_one(c)
		end
	else
		error("Invalid build cmd: " .. tostring(cmd))
	end
end
--- Setup packer with plugin specs
---@param specs Beast.Packer.PluginSpec[] List of plugin specs
function M.setup(specs)
	for _, plugin in ipairs(vim.pack.get()) do
		state.installed_plugins[plugin.spec.name] = true
	end
	-- Step 0: Expand imports (plugin discovery)
	specs = import.expand_imports(specs)
	-- Filter those with cond == false
	specs = vim.tbl_filter(function(spec)
		return spec.cond == nil or spec.cond()
	end, specs)

	-- Step 1: Normalize all specs to ensure they have names
	for i, spec in ipairs(specs) do
		specs[i] = normalize_spec(spec)
	end

	-- Step 2: Run init functions for all plugins
	for _, spec in ipairs(specs) do
		if spec.init then
			local ok, err = pcall(function()
				profile.measure(spec.name, "config_ms", spec.init)
			end)
			if not ok then
				vim.notify("Error in init for " .. spec.name .. ": " .. tostring(err), vim.log.levels.ERROR, { title = "BeastVim" })
			end
		end
	end

	-- Step 3: Collect all specs and build vim.pack specs
	local vim_pack_specs = {} ---@type (string|vim.pack.Spec)[]
	local lazy_specs = {} ---@type table<string, Beast.Packer.PluginSpec> -- {<plugin_name> = <spec>}
	local eager_specs = {} ---@type table<string, Beast.Packer.PluginSpec> -- {<plugin_name> = <spec>}
	local manual_specs = {} ---@type table<string, Beast.Packer.PluginSpec> -- {<plugin_name> = <spec>}

	for _, spec in ipairs(specs) do
		-- Add to vim.pack list with name so vim.pack uses our extracted name
		table.insert(vim_pack_specs, { src = spec.src, name = spec.name })

		-- Register the plugin
		state.plugins[spec.name] = spec

		-- Classify as lazy, eager, or manual
		-- lazy = false (explicitly) → eager
		-- lazy = { ... } (table)    → lazy with triggers
		-- lazy = nil (not set)      → manual (no automatic loading)
		if spec.lazy == false then
			eager_specs[spec.name] = spec
		elseif type(spec.lazy) == "table" then
			lazy_specs[spec.name] = spec
		elseif spec.lazy == nil then -- lazy is nil - manual loading only
			manual_specs[spec.name] = spec
		else
			error("Invalid lazy value: " .. tostring(spec.lazy))
		end
	end

	-- Setup autocmd to track vim.pack operations and show UI
	vim.api.nvim_create_autocmd("PackChangedPre", {
		callback = function(ev)
			local kind = ev.data.kind -- "install", "update", or "delete"
			local name = ev.data.spec.name

			-- Start tracking operation AFTER user confirms
			if kind == "install" or kind == "update" then
				operation.start(name, kind)
				-- Open UI once on first operation; refresh for subsequent ones
				if not ui.is_open() then
					ui.open()
				else
					ui.refresh()
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("PackChanged", {
		callback = function(ev)
			local kind = ev.data.kind
			local name = ev.data.spec.name

			-- Complete tracking after operation finishes
			if kind == "install" or kind == "update" then
				state.installed_plugins[name] = true
				operation.complete(name, true, kind == "install" and "installed" or "updated")
				ui.refresh()
				local spec = state.plugins[name]
				if spec and spec.build then
					local dir = vim.fn.stdpath("data") .. "/site/pack/core/opt/" .. name
					local ok, err = pcall(function()
						if type(spec.build) == "function" then
							-- Pass spec and plugin directory
							spec.build(spec, dir)
						elseif type(spec.build) == "string" or vim.islist(spec.build) then
							run_cmd(spec)
						end
					end)
					if not ok then
						vim.notify("Build errored for " .. name .. ": " .. tostring(err), vim.log.levels.ERROR, { title = "BeastVim" })
					end
				end
			elseif kind == "delete" then
				state.plugins[name] = nil
				-- Remove from loaded_plugins if present
				state.loaded_plugins[name] = nil
				-- Clear any operation status
				operation.status[name] = nil
				ui.refresh()
			else
				error("Unknown PackChanged kind: " .. tostring(kind))
			end
		end,
	})

	-- Step 4: Install all plugins with vim.pack.add
	local packadd_ok, packadd_err = xpcall(function()
		vim.pack.add(vim_pack_specs, {
			confirm = false,
			load = function(plugin)
				local name = assert(plugin.spec.name, "vim.pack plugin.spec.name is missing")
				-- Only load eager plugins (skip lazy and manual)
				if eager_specs[name] then
					state.load(name, { type = "eager", detail = nil })
				end
			end,
		})
	end, debug.traceback)
	if not packadd_ok then
		local installed = {}
		for _, p in ipairs(vim.pack.get()) do
			installed[p.spec.name] = true
		end

		for plugin_name, _ in pairs(operation.status) do
			if not installed[plugin_name] then
				operation.complete(plugin_name, false, string.format("Failed to install plugin '%s' | error: %s", plugin_name, tostring(packadd_err)))
			end
		end
		vim.notify("vim.pack.add failed:\n" .. tostring(packadd_err), vim.log.levels.ERROR, { title = "BeastVim" })
		return
	else
		operation.clear_completed()
	end

	-- Step 5: Load eager plugins and run their config
	for _, spec in pairs(eager_specs) do
		if spec.config then
			local ok, err = profile.measure(spec.name, "config_ms", spec.config)
			if not ok then
				vim.notify("Error in config for " .. spec.name .. ": " .. tostring(err), vim.log.levels.ERROR, { title = "BeastVim" })
			end
		end
	end

	-- Step 6: Setup packer triggers
	for _, spec in pairs(lazy_specs) do
		local lazy_config = spec.lazy
    -- stylua: ignore
		if not lazy_config then goto continue end

		-- Event triggers
		if lazy_config.event then
			event_trigger.setup(spec, lazy_config.event, state.load)
		end

		-- Command triggers
		if lazy_config.cmd then
			cmd_trigger.setup(spec, lazy_config.cmd, state.load)
		end

		-- Keymap triggers
		if lazy_config.keys then
			keys_trigger.setup(spec, lazy_config.keys, state.load)
		end

		-- Module triggers
		if lazy_config.module then
			---@type string[]
			local modules = type(lazy_config.module) == "string" and { lazy_config.module } or lazy_config.module
			for _, mod in ipairs(modules) do
				module_trigger.register(mod, spec.name)
			end
		end

		-- Filetype triggers
		if lazy_config.filetype then
			filetype_trigger.setup(spec, lazy_config.filetype, state.load)
		end

		-- Path pattern triggers
		if lazy_config.path then
			path_trigger.setup(spec, lazy_config.path, state.load)
		end

		::continue::
	end
	require("beast.libs.packer.highlights")

	-- Install module auto-loader
	M.install_module_loader()
end

return M
