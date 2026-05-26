--- Git status decorations for the explorer.
---
--- Runs `git status --porcelain=v1 --ignored` asynchronously via `vim.system`,
--- parses output into per-file badges, stamps `node.git_status` on tree nodes,
--- and propagates status upward to parent directories.
---
--- Other modules read `node.git_status` during rendering — this module never
--- touches highlights or extmarks directly.

local config = require("beast.libs.explorer.config")
local state = require("beast.libs.explorer.state")

local M = {}

-- Badge priority (lower = higher priority).
-- Used by propagate() to pick the "most urgent" child status for a directory.
local PRIORITY = {
	C = 1, -- conflict
	M = 2, -- modified
	R = 3, -- renamed
	D = 4, -- deleted
	A = 5, -- added
	U = 6, -- untracked
	-- "!" (ignored) intentionally omitted — it does NOT propagate
}

--- Map git porcelain XY codes to a single-character badge.
---@param xy string  Two-character status from `git status --porcelain`
---@return string? badge  Single char: M, A, D, R, U, C, !, or nil
local function xy_to_badge(xy)
	-- stylua: ignore
	if #xy < 2 then return nil end

	local x, y = xy:sub(1, 1), xy:sub(2, 2)

	-- Conflicts (both sides changed)
	if (x == "U" or y == "U") or (x == "A" and y == "A") or (x == "D" and y == "D") then
		return "C"
	end

	-- Untracked / ignored
	-- stylua: ignore
	if xy == "??" then return "U" end
	-- stylua: ignore
	if xy == "!!" then return "!" end

	-- Renamed (index)
	-- stylua: ignore
	if x == "R" then return "R" end

	-- Deleted
	-- stylua: ignore
	if x == "D" or y == "D" then return "D" end

	-- Added (new file in index)
	-- stylua: ignore
	if x == "A" then return "A" end

	-- Modified (index or worktree)
	if x == "M" or y == "M" or x == "T" or y == "T" then
		return "M"
	end

	return nil
end

--- Parse `git status --porcelain=v1` output into a path→badge table.
---@param output string  Raw stdout from git status
---@param git_root string  Absolute path to the git repository root
---@return table<string, string>  abs_path → badge
function M.parse(output, git_root)
	local result = {} ---@type table<string, string>

	for line in output:gmatch("[^\n]+") do
		-- stylua: ignore
		if #line < 4 then goto continue end

		local xy = line:sub(1, 2)
		local path_part = line:sub(4)

		-- Renames: "R  old -> new" — use the new path
		if xy:sub(1, 1) == "R" then
			local arrow = path_part:find(" %-> ")
			if arrow then
				path_part = path_part:sub(arrow + 4)
			end
		end

		-- Strip trailing slash from directories
		path_part = path_part:gsub("/$", "")

		local badge = xy_to_badge(xy)
		if badge then
			local abs_path = git_root .. "/" .. path_part
			-- If a file already has a higher-priority badge, keep it
			local existing = result[abs_path]
			if not existing or (PRIORITY[badge] and (not PRIORITY[existing] or PRIORITY[badge] < PRIORITY[existing])) then
				result[abs_path] = badge
			end
		end

		::continue::
	end

	return result
end

--- Clear git_status from all tree nodes.
function M.clear()
	-- stylua: ignore
	if not state.tree then return end

	for _, node in pairs(state.tree.nodes) do
		node.git_status = nil
	end
	state.git_root = nil
	state.git_output_cache = nil
	state.git_statuses = nil
end

--- Clear only the git_status field on every node (without touching git_root).
local function clear_statuses()
	-- stylua: ignore
	if not state.tree then return end

	for _, node in pairs(state.tree.nodes) do
		node.git_status = nil
	end
end

--- Apply parsed git statuses to tree nodes.
--- When a file's node doesn't exist in the tree (its parent directory is
--- collapsed), walk up the path components to find the nearest ancestor
--- node and stamp the badge on it — this makes collapsed directories show
--- the highest-priority badge of their hidden children, matching VS Code.
---@param statuses table<string, string>  abs_path → badge
function M.apply(statuses)
	-- stylua: ignore
	if not state.tree then return end

	clear_statuses()

	for abs_path, badge in pairs(statuses) do
		local node = state.tree.nodes[abs_path]
		if node then
			node.git_status = badge
		else
			-- File not in tree — bubble badge to nearest existing ancestor
			-- stylua: ignore
			if not PRIORITY[badge] then goto continue end
			local dir = vim.fn.fnamemodify(abs_path, ":h")
			while dir and #dir > 0 do
				local ancestor = state.tree.nodes[dir]
				if ancestor then
					local existing = ancestor.git_status
					if not existing or not PRIORITY[existing] or PRIORITY[badge] < PRIORITY[existing] then
						ancestor.git_status = badge
					end
					break
				end
				local parent = vim.fn.fnamemodify(dir, ":h")
				-- stylua: ignore
				if parent == dir then break end
				dir = parent
			end
		end
		::continue::
	end
end

--- Propagate git status from files upward to parent directories.
--- Walks ALL nodes (not just visible/expanded ones) so collapsed directories
--- with dirty children still propagate status to their ancestors.
--- Ignored status does NOT propagate (VS Code behavior).
function M.propagate()
	-- stylua: ignore
	if not state.tree then return end

	-- Collect all non-root nodes and sort by depth descending (deepest first)
	local all_nodes = {} ---@type Beast.Explorer.Node[]
	for _, node in pairs(state.tree.nodes) do
		if node.depth >= 0 then
			all_nodes[#all_nodes + 1] = node
		end
	end
	table.sort(all_nodes, function(a, b)
		return a.depth > b.depth
	end)

	for _, node in ipairs(all_nodes) do
		local badge = node.git_status

		-- Skip if no status or ignored (ignored doesn't propagate)
		-- stylua: ignore
		if not badge or badge == "!" or not PRIORITY[badge] then goto continue end

		-- Walk up the parent chain
		local parent = state.tree.nodes[node.parent]
		while parent do
			local parent_badge = parent.git_status
			if parent_badge and PRIORITY[parent_badge] and PRIORITY[parent_badge] <= PRIORITY[badge] then
				break -- parent already has equal or higher priority
			end
			parent.git_status = badge
			parent = state.tree.nodes[parent.parent]
		end

		::continue::
	end
end

--- Resolve the git repository root for the current explorer tree.
---@return string? git_root  Absolute path, or nil if not in a git repo
local function resolve_git_root()
	-- stylua: ignore
	if not state.tree then return nil end

	local root_path = state.tree.root.path
	local git_dir = vim.fs.find(".git", { path = root_path, upward = true })[1]
	if not git_dir then
		return nil
	end
	return vim.fn.fnamemodify(git_dir, ":h")
end

local DEBOUNCE_MS = 200

--- Refresh git statuses asynchronously.
--- Cancels any in-flight job, runs `git status`, applies results, then calls on_done.
---@param on_done? fun()  Called after statuses are applied and propagated
function M.refresh(on_done)
	-- Gate: git must be enabled
	if not config.git or not config.git.enable then
		-- stylua: ignore
		if on_done then on_done() end
		return
	end

	-- stylua: ignore
	if not state.tree or not state.view or not state.view:is_valid() then
		if on_done then on_done() end
		return
	end

	-- Cancel in-flight job
	if state.git_job then
		pcall(function()
			state.git_job:kill("sigterm")
		end)
		state.git_job = nil
	end

	local git_root = resolve_git_root()
	if not git_root then
		M.clear()
		-- stylua: ignore
		if on_done then on_done() end
		return
	end
	state.git_root = git_root

	state.git_job = vim.system({ "git", "-C", git_root, "status", "--porcelain=v1", "--ignored" }, { text = true }, function(result)
		state.git_job = nil
		vim.schedule(function()
				-- stylua: ignore
				if not state.tree or not state.view or not state.view:is_valid() then
					if on_done then on_done() end
					return
				end

			if result.code ~= 0 then
				M.clear()
				state.git_output_cache = nil
					-- stylua: ignore
					if on_done then on_done() end
				return
			end

			local output = result.stdout or ""
			-- Cache: skip parse+apply+propagate when output hasn't changed
			if output == state.git_output_cache then
				-- stylua: ignore
				if on_done then on_done() end
				return
			end
			state.git_output_cache = output

			local statuses = M.parse(output, git_root)
			state.git_statuses = statuses
			M.apply(statuses)
			M.propagate()

				-- stylua: ignore
				if on_done then on_done() end
		end)
	end)
end

--- Debounced refresh — collapses rapid triggers into one git status run.
---@param on_done? fun()
function M.schedule_refresh(on_done)
	if not state.git_timer then
		state.git_timer = assert((vim.uv or vim.loop).new_timer(), "failed to create timer")
	end

	state.git_timer:stop()
	state.git_timer:start(
		DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			M.refresh(on_done)
		end)
	)
end

--- Stop debounce timer and cancel in-flight job. Called on explorer close.
function M.stop()
	if state.git_timer then
		state.git_timer:stop()
		state.git_timer:close()
		state.git_timer = nil
	end
	if state.git_job then
		pcall(function()
			state.git_job:kill("sigterm")
		end)
		state.git_job = nil
	end
end

return M
