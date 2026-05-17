local state = require("beast.libs.explorer.state")
local ui = require("beast.libs.explorer.ui")

local uv = vim.uv or vim.loop

local M = {}

-- Dirty dirs accumulated during the debounce window.
---@type table<string, boolean>
local dirty_dirs = {}

-- Single reusable timer for debouncing.
---@type uv_timer_t?
local timer = nil

local DEBOUNCE_MS = 100

local function flush()
	if not state.tree or not state.view or not state.view:is_valid() then
		dirty_dirs = {}
		return
	end

	for dir_path in pairs(dirty_dirs) do
		local node = state.tree.nodes[dir_path]
		if node and node.expanded then
			-- refresh() clears expanded + unwatches; expand() re-scans + re-watches.
			state.tree:refresh(dir_path)
			state.tree:expand(node)
		end
	end
	dirty_dirs = {}

	ui.render()
end

--- Schedule a debounced refresh for `dir_path`.
--- Multiple calls within DEBOUNCE_MS are batched into one render pass.
---@param dir_path string
function M._schedule_refresh(dir_path)
	dirty_dirs[dir_path] = true

	if not timer then
		timer = uv.new_timer()
	end

	timer:stop()
	timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(flush))
end

--- Start watching a directory for filesystem changes.
--- No-op if already watching this path.
---@param dir_path string
function M.watch(dir_path)
	-- stylua: ignore
	if state.watchers[dir_path] then return end

	local handle = uv.new_fs_event()
	if not handle then
		return
	end

	local ok = pcall(handle.start, handle, dir_path, {}, function(err)
		-- stylua: ignore
		if err then return end
		M._schedule_refresh(dir_path)
	end)

	if not ok then
		pcall(handle.close, handle)
		return
	end

	state.watchers[dir_path] = handle
end

--- Stop watching a directory.
---@param dir_path string
function M.unwatch(dir_path)
	local handle = state.watchers[dir_path]
	-- stylua: ignore
	if not handle then return end

	pcall(handle.stop, handle)
	pcall(handle.close, handle)
	state.watchers[dir_path] = nil
end

--- Stop all watchers and clear the table.
function M.stop_all()
	for dir_path, handle in pairs(state.watchers) do
		pcall(handle.stop, handle)
		pcall(handle.close, handle)
		state.watchers[dir_path] = nil
	end

	dirty_dirs = {}

	if timer then
		timer:stop()
		timer:close()
		timer = nil
	end
end

return M
