local M = {}

function M.check()
	local health = vim.health

	health.start("beast.libs.packer")

	-- Check Neovim version (vim.pack required)
	if vim.pack == nil then
		health.error("vim.pack not available — Neovim 0.11+ required")
		return
	end
	health.ok("vim.pack available")

	-- Check module loaded
	local packer = package.loaded["beast.libs.packer"]
	if not packer then
		health.warn("Packer module not loaded (require('beast.libs.packer').setup() not called)")
		return
	end
	health.ok("Packer module loaded")

	-- =========================================================================
	-- Plugin state
	-- =========================================================================
	health.start("beast.libs.packer — plugins")

	local ok_state, state = pcall(require, "beast.libs.packer.state")
	if not ok_state then
		health.error("Failed to load state: " .. tostring(state))
		return
	end

	local total = 0
	local loaded = 0
	local eager = 0
	local lazy = 0
	local manual = 0

	for name, spec in pairs(state.plugins) do
		total = total + 1
		if state.loaded_plugins[name] then
			loaded = loaded + 1
		end
		if spec.lazy == false then
			eager = eager + 1
		elseif type(spec.lazy) == "table" then
			lazy = lazy + 1
		else
			manual = manual + 1
		end
	end

	health.ok(string.format("%d plugins registered (eager=%d, lazy=%d, manual=%d)", total, eager, lazy, manual))
	health.ok(string.format("%d/%d plugins loaded", loaded, total))

	-- Check for plugins that failed to install
	local not_installed = {}
	for name, _ in pairs(state.plugins) do
		if not state.installed_plugins[name] then
			not_installed[#not_installed + 1] = name
		end
	end
	if #not_installed == 0 then
		health.ok("All plugins installed")
	else
		-- installed_plugins is populated via vim.schedule, may not be ready yet
		-- Cross-check with filesystem
		local opt_dir = vim.fn.stdpath("data") .. "/site/pack/core/opt/"
		local actually_missing = {}
		for _, name in ipairs(not_installed) do
			if vim.uv.fs_stat(opt_dir .. name) == nil then
				actually_missing[#actually_missing + 1] = name
			end
		end
		if #actually_missing == 0 then
			health.ok("All plugins installed (on disk)")
		else
			health.warn("Plugins not installed: " .. table.concat(actually_missing, ", "))
		end
	end

	-- =========================================================================
	-- API contract
	-- =========================================================================
	health.start("beast.libs.packer — API")

	-- setup exists
	if type(packer.setup) == "function" then
		health.ok("setup() available")
	else
		health.error("setup() missing")
	end

	-- lazy exists
	if type(packer.lazy) == "function" then
		health.ok("lazy() available (library lazy-loading)")
	else
		health.error("lazy() missing")
	end

	-- state.load works for an already-loaded plugin (no-op path)
	if loaded > 0 then
		local test_name
		for name, _ in pairs(state.loaded_plugins) do
			test_name = name
			break
		end
		local ok_load, load_err = pcall(state.load, test_name, { type = "manual", detail = "health" })
		if ok_load then
			health.ok(string.format("state.load() no-op for already-loaded plugin (%s)", test_name))
		else
			health.error("state.load() errored on loaded plugin: " .. tostring(load_err))
		end
	end

	-- =========================================================================
	-- Profile data
	-- =========================================================================
	health.start("beast.libs.packer — profile")

	local ok_profile, profile_mod = pcall(require, "beast.libs.packer.profile")
	if not ok_profile then
		health.error("Failed to load profile module: " .. tostring(profile_mod))
	else
		local data = profile_mod.data or {}
		local slow_plugins = {}
		for name, timing in pairs(data) do
			local config_ms = timing.config_ms or 0
			if config_ms > 50 then
				slow_plugins[#slow_plugins + 1] = string.format("%s (%.1fms)", name, config_ms)
			end
		end
		if #slow_plugins > 0 then
			health.warn("Slow plugin configs (>50ms): " .. table.concat(slow_plugins, ", "))
		else
			health.ok("No slow plugin configs detected")
		end

		-- Report phase times if available
		local phases = profile_mod.phases or {}
		for phase, ms in pairs(phases) do
			health.info(string.format("Phase: %s = %.1fms", phase, ms))
		end
	end
end

return M
