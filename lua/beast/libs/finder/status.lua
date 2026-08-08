-- "Is finder running a pre-flight LSP check, and for what" state. Finder just
-- emits `User BeastFinderStatusChanged` on every change (below) — it doesn't
-- know or care whether anything is listening. The statusline component
-- (statusline/components/finder_lsp.lua) is the one consumer today, reading
-- this module directly, the same way statusline/components/git_branch.lua
-- reacts to its own external `BeastStatuslineGitChanged` event.

local SPINNER_INTERVAL_MS = 80 -- matches finder/ui/input.lua's picker spinner

---@class Beast.FinderStatus.Config
local defaults = {
	---@type string?
	action = nil,
}

---@type Beast.FinderStatus.Config
local cfg = vim.deepcopy(defaults)

---@type uv.uv_timer_t|nil
local timer = nil

local methods = {}

local function emit_changed()
	vim.api.nvim_exec_autocmds("User", { pattern = "BeastFinderStatusChanged" })
end

---Mark a pre-flight check as in progress. Safe to call again while already
---active (e.g. a rapid re-trigger) — just relabels, doesn't restart the timer.
---@param label string
function methods.start(label)
	cfg.action = label
	emit_changed()

	-- stylua: ignore
	if timer then return end
	timer = assert(vim.uv.new_timer(), "beast.libs.finder.status: failed to create timer")
	-- Re-fires the changed event (not a raw redrawstatus) so the statusline's
	-- own cache-invalidation path re-runs the component's provider each tick —
	-- see statusline/init.lua's `update`-gated cache.
	timer:start(SPINNER_INTERVAL_MS, SPINNER_INTERVAL_MS, vim.schedule_wrap(emit_changed))
end

---Clear the in-progress state. Called exactly once per resolved check.
function methods.stop()
	cfg.action = nil
	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
	emit_changed()
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.libs.finder.status is read-only; cannot assign '%s' directly. Use start()/stop().", tostring(key)), 2)
	end,
})

return M
