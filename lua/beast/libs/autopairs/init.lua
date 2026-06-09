--- Beast Autopairs — public API and state owner.
---
--- Lifecycle:
---   setup(opts)  — merge config; does NOT install mappings
---   enable()     — install mappings (idempotent)
---   disable()    — remove mappings
---   toggle()     — flip `vim.g.beast_autopairs_disable` (cheap, no remap)

local config = require("beast.libs.autopairs.config")
local keymap = require("beast.libs.autopairs.keymap")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "autopairs", description = "Auto-insert and balance matching brackets, quotes, and tags" }

-- Module state.
---@type table<string, { mode: string, lhs: string }>
local registry = {}
local installed = false

---@param opts? Beast.Autopairs.Config
function M.setup(opts)
	config.setup(opts)
end

--- Install the autopairs mappings. Idempotent — calling twice is a no-op.
--- Honors `config.enabled` (returns silently when false).
---
--- Note: the installed closures capture the live config table by reference,
--- so calling `setup()` after `enable()` does NOT reconfigure already-mapped
--- keys. To reconfigure: `disable()` → `setup(new_opts)` → `enable()`.
function M.enable()
	if installed then
		return
	end
	if not config.enabled then
		return
	end
	keymap.install(config.get(), registry)
	installed = true
end

--- Remove all autopairs mappings. Safe to call when not installed.
function M.disable()
	if not installed then
		return
	end
	keymap.uninstall(registry)
	installed = false
end

--- Flip the global runtime disable flag. Does not unmap — actions short-
--- circuit to the literal char while `vim.g.beast_autopairs_disable` is true.
--- This is what `<leader>up` will bind to in Phase 3.
function M.toggle()
	vim.g.beast_autopairs_disable = not vim.g.beast_autopairs_disable
end

--- Whether the mappings are currently installed (for tests + health).
---@return boolean
function M.is_installed()
	return installed
end

return M
