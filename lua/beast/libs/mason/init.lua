-- BeastVim mason infrastructure library.
--
-- Thin wrapper around mason-registry: installs LSP/DAP/linter/formatter
-- binaries on demand, mirroring `Treesitter.ensure_parser`. `BeastVim/<Lang>`
-- extensions call `Mason.ensure_package({"lua-language-server"}, register)`
-- as the "yes, install this" signal. `require("mason-registry")` is itself a
-- module-loader trigger (see packer/builtin.lua) that packadds + configures
-- mason.nvim on first use, so no manual plugin-load call is needed here.

---@class Beast.Mason
local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "mason", description = "Mason package install helper for LSP/DAP/linter/formatter binaries" }

-- Packages currently being installed, mapped to the callbacks waiting on
-- them (multiple `ensure_package` calls can race for the same package).
---@type table<string, (fun())[]>
local installing = {}

--- Absolute path to a Mason-managed binary's shim, regardless of whether it
--- is actually installed yet -- check with `vim.fn.executable()`.
---@param bin string
---@return string
function M.bin(bin)
	return vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin", bin)
end

--- Install Mason packages that aren't installed yet, then call `callback`.
---
--- IMPORTANT: `callback` is where the caller should call `Lsp.register(...)`
--- for any server whose `cmd` depends on one of `names` -- not before. A
--- vim.lsp client that fails to spawn once (ENOENT because the binary isn't
--- installed yet) is left in a broken state by Neovim's LSP client and never
--- retries, even if the FileType autocmd that triggers autostart fires again
--- later. Gating registration on this callback means `vim.lsp.enable` only
--- ever runs once the binary is guaranteed to exist, so that first spawn
--- attempt can't race the install.
---
--- `callback` runs synchronously (same call stack) when every name in
--- `names` is already installed and the registry cache is warm -- the
--- common case after the first run -- so this adds no lazy-load delay
--- there. It only runs asynchronously, after installation finishes, the
--- first time a package isn't present yet.
---@param names string[] Mason package names (e.g. "lua-language-server")
---@param callback fun()
function M.ensure_package(names, callback)
	-- Resolve "mason" (not "mason-registry") first, deliberately. Both are
	-- registered as module-loader triggers for the same plugin (see
	-- packer/builtin.lua), but if `require("mason-registry")` is the one
	-- that fires the trigger, the packadd + config() it kicks off runs
	-- *nested inside* that same require() call. If anything mason loads
	-- along the way (e.g. `plugin/mason.lua`, sourced by packadd) does its
	-- own nested `require("mason-registry")` before the outer call returns,
	-- Lua's require() doesn't recheck package.loaded between searchers, so
	-- the outer call's searcher loop resumes and loads mason-registry a
	-- *second* time -- producing two separate Registry singletons (one
	-- used by mason's own UI/health checks, one used here). That's exactly
	-- what caused `:Mason` to show an empty registry while
	-- get_package()/is_installed() here still worked, since they were
	-- reading the second, later-cached instance. Requiring "mason" first
	-- lets the plugin finish loading via a single top-level require, so by
	-- the time "mason-registry" is required below, mason.nvim is already
	-- marked loaded and there is only ever one Registry instance.
	require("mason")
	local registry = require("mason-registry")

	-- mason-core's async internals resolve some of these callbacks from a
	-- libuv "fast" event context, where nvim API calls (which Lsp.register ->
	-- vim.lsp.enable makes) are illegal. vim.schedule_wrap hops back to the
	-- main loop unconditionally, so every path below is always safe to call
	-- Lsp.register from, however it was reached.
	local function install_all()
		local remaining = #names

		local function one_done()
			remaining = remaining - 1
			if remaining == 0 then
				callback()
			end
		end

		for _, name in ipairs(names) do
			local ok, pkg = pcall(registry.get_package, name)
			if not ok then
				vim.notify(string.format("[beast.mason] Unknown package '%s'", name), vim.log.levels.WARN)
				one_done()
			elseif pkg:is_installed() then
				one_done()
			elseif installing[name] then
				table.insert(installing[name], one_done)
			else
				installing[name] = { one_done }
				pkg:install(
					nil,
					vim.schedule_wrap(function(success, err)
						local waiters = installing[name]
						installing[name] = nil
						if not success then
							vim.notify(
								string.format("[beast.mason] Failed to install '%s': %s", name, tostring(err)),
								vim.log.levels.WARN
							)
						end
						for _, waiter in ipairs(waiters) do
							waiter()
						end
					end)
				)
			end
		end
	end

	registry.refresh(vim.schedule_wrap(function()
		-- registry.refresh()'s "cache looks fresh" fast path can report
		-- success without the registry sources actually being loaded into
		-- this process yet, so a get_package() right after can spuriously
		-- fail with "Cannot find package". Detect that and force one real
		-- reload (registry.update(), which always loads) before falling
		-- back to "unknown package".
		local any_missing = false
		for _, name in ipairs(names) do
			if not registry.has_package(name) then
				any_missing = true
				break
			end
		end
		if any_missing then
			registry.update(vim.schedule_wrap(install_all))
		else
			install_all()
		end
	end))
end

return M
