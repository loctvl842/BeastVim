--- Diagnostic decorations for the explorer.
---
--- Subscribes (via autocmds.lua) to `DiagnosticChanged` and recomputes a
--- per-file severity map from `vim.diagnostic.get()`. Each file gets the
--- highest-priority severity (ERROR < WARN < INFO < HINT). Directories
--- aggregate the highest-priority severity of any descendant.
---
--- Other modules read `node.diagnostic` (a `vim.diagnostic.severity` number)
--- during rendering — this module never touches highlights or extmarks.

local state = require("beast.libs.explorer.state")

local M = {}

---@type Beast.Util.Debouncer|nil
local debounced = nil

local SEVERITY = vim.diagnostic.severity -- ERROR=1, WARN=2, INFO=3, HINT=4

--- Walk all diagnostics across loaded buffers and return abs_path → severity.
---@return table<string, integer>
function M.build_status()
	local status = {} ---@type table<string, integer>
	for _, d in ipairs(vim.diagnostic.get(nil)) do
		local buf = d.bufnr
		if buf and vim.api.nvim_buf_is_valid(buf) then
			local name = vim.api.nvim_buf_get_name(buf)
			if name ~= "" then
				local path = vim.fn.fnamemodify(name, ":p"):gsub("/$", "")
				local cur = status[path]
				if not cur or d.severity < cur then
					status[path] = d.severity
				end
			end
		end
	end
	return status
end

--- Build the directory-aggregate map: for every ancestor of every file in
--- `status`, record the highest-priority (lowest number) descendant severity.
--- Each ancestor walk short-circuits as soon as the current dir already
--- holds an equal-or-higher priority than our contribution.
---@param status table<string, integer>
---@return table<string, integer>
local function build_dir_status(status)
	local dir_status = {} ---@type table<string, integer>
	for abs_path, sev in pairs(status) do
		local dir = vim.fn.fnamemodify(abs_path, ":h")
		while dir and #dir > 0 do
			local cur = dir_status[dir]
			if cur and cur <= sev then
				break -- this dir (and its ancestors) already absorb our contribution
			end
			dir_status[dir] = sev

			local parent = vim.fn.fnamemodify(dir, ":h")
			-- stylua: ignore
			if parent == dir then break end
			dir = parent
		end
	end
	return dir_status
end

--- Resolve the diagnostic severity to stamp on a tree node at `path`.
--- Direct hit first, then aggregated dir_status. Unlike git there is no
--- "propagating ancestor" fallback — diagnostics never collapse to a dir entry.
---@param path string
---@return integer?
function M.resolve(path)
	local s = state.diagnostics
	-- stylua: ignore
	if not s or not s.status then return nil end
	return s.status[path] or (s.dir_status and s.dir_status[path])
end

--- Stamp `node.diagnostic` on every tree node.
---@param status table<string, integer>
function M.apply(status)
	-- stylua: ignore
	if not state.tree then return end

	state.diagnostics.status = status
	state.diagnostics.dir_status = build_dir_status(status)

	for path, node in pairs(state.tree.nodes) do
		node.diagnostic = M.resolve(path)
	end
end

--- Clear all diagnostic state from the tree.
function M.clear()
	-- stylua: ignore
	if not state.tree then return end
	for _, node in pairs(state.tree.nodes) do
		node.diagnostic = nil
	end
	state.diagnostics.status = nil
	state.diagnostics.dir_status = nil
end

--- Synchronously rescan all diagnostics and re-stamp the tree.
function M.refresh()
	-- stylua: ignore
	if not state.tree or not state.view or not state.view:is_valid() then return end
	M.apply(M.build_status())
end

local DEBOUNCE_MS = 100

local pending_on_done = nil ---@type fun()|nil

--- Debounced refresh — collapses rapid DiagnosticChanged bursts (e.g. on
--- attach, on save when multiple servers republish) into one effective run.
---@param on_done? fun()
function M.schedule_refresh(on_done)
	if on_done then
		pending_on_done = on_done
	end

	if not debounced then
		debounced = Util.debounce(DEBOUNCE_MS, function()
			local cb = pending_on_done
			pending_on_done = nil
			M.refresh()
			-- stylua: ignore
			if cb then cb() end
		end)
	end
	debounced()
end

--- Stop debounce timer. Called on explorer close.
function M.stop()
	if debounced then
		debounced:close()
		debounced = nil
	end
	pending_on_done = nil
end

M.SEVERITY = SEVERITY

return M
