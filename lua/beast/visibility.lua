-- Global file-visibility state shared by Explorer, Finder, and any future
-- file-based surface. Single source of truth for "hidden files" and
-- "gitignored files" so toggling either one anywhere applies everywhere.
--
-- Consumers invalidate their own caches/queries by listening for the
-- `User BeastVisibilityChanged` autocmd (data = { key, value }) fired below —
-- same pattern as `BeastGitIndexChanged` (explorer) and `BeastStatuslineGitChanged`
-- (statusline).

---@class Beast.Visibility.Config
local defaults = {
	hidden = false,
	gitignored = false,
}

---@type Beast.Visibility.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param key "hidden"|"gitignored"
local function emit_changed(key)
	vim.api.nvim_exec_autocmds("User", {
		pattern = "BeastVisibilityChanged",
		data = { key = key, value = cfg[key] },
	})
end

function methods.toggle_hidden()
	cfg.hidden = not cfg.hidden
	emit_changed("hidden")
end

function methods.toggle_gitignored()
	cfg.gitignored = not cfg.gitignored
	emit_changed("gitignored")
end

---@param opts? Beast.Visibility.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.visibility is read-only; cannot assign '%s' directly. Use setup()/toggle_*().", tostring(key)), 2)
	end,
})

return M
