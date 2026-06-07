-- stylua: ignore start
local config            = require("beast.libs.packer.config")
local event_trigger     = require("beast.libs.packer.triggers.event")
local import            = require("beast.libs.packer.import")
local keys_trigger      = require("beast.libs.packer.triggers.keys")
local module_trigger    = require("beast.libs.packer.triggers.module")
local profile           = require("beast.libs.packer.profile")
local state             = require("beast.libs.packer.state")
-- stylua: ignore end

-- Lazy submodules. Loaded on first use; require cache makes repeat calls free.
-- - operation / ui  → only fire inside PackChanged autocmd handlers (install/update)
-- - cmd / path / filetype triggers → only used when a spec opts in
local function _lazy(mod)
	local cached
	return function()
		if not cached then cached = require(mod) end
		return cached
	end
end

local operation         = _lazy("beast.libs.packer.operation")
local ui                = _lazy("beast.libs.packer.ui")
local cmd_trigger       = _lazy("beast.libs.packer.triggers.cmd")
local filetype_trigger  = _lazy("beast.libs.packer.triggers.filetype")
local path_trigger      = _lazy("beast.libs.packer.triggers.path")

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
--- Eagerly apply the configured colorscheme so its colors are available
--- before the rest of packer.setup runs, avoiding a flash of the default
--- colorscheme during startup.
---
--- When `plugin` is set, loads the plugin first (with dependency checks).
--- When `plugin` is nil, applies a builtin colorscheme directly via `:colorscheme`.
---
--- Must be called AFTER specs are normalized, init() has run for every
--- spec, and state.plugins is fully populated, so spec dependency lookup
--- works and the existing init-before-config invariant is preserved.
---@return string|nil plugin_name
local function apply_early_colorscheme()
	local cs = config.colorscheme
	-- stylua: ignore
	if cs == nil then return nil end

	if type(cs) ~= "table" or type(cs.name) ~= "string" or cs.name == "" then
		vim.notify("packer: invalid `colorscheme` config; expected { name = string, plugin? = string }", vim.log.levels.WARN, { title = "BeastVim" })
		return nil
	end

	-- Builtin colorscheme: no plugin to load, just apply it directly.
	if not cs.plugin or cs.plugin == "" then
		pcall(vim.cmd.colorscheme, cs.name)
		return nil
	end

	local opt_dir = vim.fn.stdpath("data") .. "/site/pack/core/opt/"
	local function is_installed(plugin_name)
		return vim.uv.fs_stat(opt_dir .. plugin_name) ~= nil
	end

	-- stylua: ignore
	if not is_installed(cs.plugin) then return nil end

	local spec = state.plugins[cs.plugin]
	-- stylua: ignore
	if spec == nil then return nil end

	-- Bail if any declared dependency is not yet installed; fall back to
	-- the normal install/load path rather than half-loading a broken graph.
	if spec.dependencies then
		for _, dep in ipairs(spec.dependencies) do
			if not is_installed(dep) then
				return nil
			end
		end
	end

	local ok, err = pcall(state.load, cs.plugin, { type = "eager", detail = "colorscheme" })
	if not ok then
		-- state.load sets loaded_plugins[name] = true BEFORE packadd, so a
		-- failure leaves the flag stuck. Roll it back so the normal trigger
		-- path can retry once vim.pack.add finishes.
		state.loaded_plugins[cs.plugin] = nil
		vim.notify("packer: early colorscheme load failed for " .. cs.plugin .. ": " .. tostring(err), vim.log.levels.ERROR, { title = "BeastVim" })
		return nil
	end

	-- Safety net: most colorscheme `config()`s already call vim.cmd.colorscheme
	-- themselves, but some (e.g. tokyonight) only define the scheme.
	pcall(vim.cmd.colorscheme, cs.name)
	return cs.plugin
end

--- Setup packer with plugin specs
---@param opts? Beast.Packer.Config
function M.setup(opts)
	config.setup(opts)
	-- NOTE: state.installed_plugins is primed lazily on first :Pack UI open
	-- (see ui.M.open). vim.pack.get() shells out to git ~3× per plugin
	-- (~50 ms wall + ~100 ms total CPU for ~7 plugins on macOS), and the
	-- only consumer is the UI. PackChanged (below) keeps the table fresh
	-- within the session after install/update. Health checks fall back to
	-- a filesystem check when the table is empty.
	local specs = config.spec

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

	for _, spec in ipairs(specs) do
		-- Add to vim.pack list with name so vim.pack uses our extracted name.
		-- `version` is optional; forwarded so plugins like blink.cmp that key
		-- their downloaded binaries off a git tag can pin to a release.
		table.insert(vim_pack_specs, { src = spec.src, name = spec.name, version = spec.version })

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
			-- Do nothing
		else
			error("Invalid lazy value: " .. tostring(spec.lazy))
		end
	end

	-- Apply the configured colorscheme as early as possible (before vim.pack.add
	-- and before lazy triggers register). Skips silently if not configured, not
	-- installed, or any dep is missing. Lazy triggers and the vim.pack.add load
	-- callback are unaffected: both funnel through state.load, which short-circuits
	-- on state.loaded_plugins[name].
	profile.measure("early_cs", "phase_ms", apply_early_colorscheme)

	-- Setup autocmd to track vim.pack operations and show UI
	vim.api.nvim_create_autocmd("PackChangedPre", {
		callback = function(ev)
			local kind = ev.data.kind -- "install", "update", or "delete"
			local name = ev.data.spec.name

			-- Start tracking operation AFTER user confirms
			if kind == "install" or kind == "update" then
				operation().start(name, kind)
				-- Open UI once on first operation; refresh for subsequent ones
				local _ui = ui()
				if not _ui.is_open() then
					_ui.open()
				else
					_ui.refresh()
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
				operation().complete(name, true, kind == "install" and "installed" or "updated")
				ui().refresh()
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
				operation().status[name] = nil
				ui().refresh()
			else
				error("Unknown PackChanged kind: " .. tostring(kind))
			end
		end,
	})

	-- Step 4: Install all plugins with vim.pack.add
	-- Time outside the xpcall so a failure still surfaces to the existing
	-- error path. profile.measure can't be used here because its inner pcall
	-- would swallow the error and break xpcall's traceback.
	local t_pack_add = Util.hrtime()
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
	if packadd_ok then
		profile.add_phase_time("pack_add", (Util.hrtime() - t_pack_add) / 1e6)
	end
	if not packadd_ok then
		local installed = {}
		for _, p in ipairs(vim.pack.get()) do
			installed[p.spec.name] = true
		end

		local op = operation()
		for plugin_name, _ in pairs(op.status) do
			if not installed[plugin_name] then
				op.complete(plugin_name, false, string.format("Failed to install plugin '%s' | error: %s", plugin_name, tostring(packadd_err)))
			end
		end
		vim.notify("vim.pack.add failed:\n" .. tostring(packadd_err), vim.log.levels.ERROR, { title = "BeastVim" })
		return
	else
		operation().clear_completed()
	end

	-- Step 5: Load eager plugins and run their config
	for _, spec in pairs(eager_specs) do
		if spec.config and not state.loaded_plugins[spec.name] then
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
			cmd_trigger().setup(spec, lazy_config.cmd, state.load)
		end

		-- Keymap triggers
		if lazy_config.keys then
			keys_trigger.setup(spec, lazy_config.keys, state.load)
		end

		-- Module triggers
		if lazy_config.module then
			---@type string[]
			---@diagnostic disable-next-line: assign-type-mismatch
			local modules = type(lazy_config.module) == "string" and { lazy_config.module } or lazy_config.module
			for _, mod in ipairs(modules) do
				module_trigger.register(mod, spec.name)
			end
		end

		-- Filetype triggers
		if lazy_config.filetype then
			filetype_trigger().setup(spec, lazy_config.filetype, state.load)
		end

		-- Path pattern triggers
		if lazy_config.path then
			path_trigger().setup(spec, lazy_config.path, state.load)
		end

		::continue::
	end
	require("beast").apply_highlights("beast.libs.packer.highlights")

	-- Install module auto-loader
	M.install_module_loader()
end

-- ================================
-- Lazy loading for Beast libraries
-- ================================

---@class Beast.Packer.LazyLibOpts
---@field event? string|string[]|Beast.Packer.EventSpec|Beast.Packer.EventSpec[] Event trigger(s). Per-event `defer = true` available — see Beast.Packer.EventSpec.
---@field keys? Beast.KeymapSpec|Beast.KeymapSpec[]|string|string[] Key trigger(s). Always sync — user is actively waiting.
---@field filetype? string|string[] Filetype trigger(s). Always sync — render-critical.
---@field setup fun(lib: table) Called after require(mod), receives the module

--- Lazy-load a Beast library using the same trigger infrastructure as plugins.
--- Instead of packadd, the load action is require(mod) + opts.setup(lib).
---
--- NOTE: `defer` is per-event only (see Beast.Packer.EventSpec). Keys,
--- filetype, cmd, module, and path triggers always load synchronously
--- because the caller is actively awaiting the result.
---@param mod string Lua module path (e.g. "beast.libs.tabline")
---@param opts Beast.Packer.LazyLibOpts
function M.lazy(mod, opts)
	local loaded = false

	local function do_load()
		-- stylua: ignore
		if loaded then return end
		loaded = true

		local lib = require(mod)
		if opts.setup then
			opts.setup(lib)
		end
	end

	local spec = { name = mod }

	if opts.event then
		event_trigger.setup(spec, opts.event, do_load)
	end

	if opts.keys then
		keys_trigger.setup(spec, opts.keys, do_load)
	end

	if opts.filetype then
		filetype_trigger().setup(spec, opts.filetype, do_load)
	end
end

return M
