--- Git status decorations for the explorer.
---
--- Runs `git status --porcelain=v2 --ignored -z` asynchronously via `vim.system`,
--- parses output into per-file badges, then stamps every tree node with either
--- the direct file status or a per-directory aggregate (highest-priority badge
--- among any descendant). Single linear pass — no sort, no propagate stage.
---
--- Other modules read `node.git_status` during rendering — this module never
--- touches highlights or extmarks directly.

local state = require("beast.libs.explorer.state")

local M = {}

-- Internal state (was on state.lua; private to this module now).
---@type vim.SystemObj|nil
local git_job = nil
---@type uv.uv_timer_t|nil
local git_timer = nil
---@type string|nil  cached porcelain output for change detection
local git_output_cache = nil

--- Invalidate the porcelain output cache so the next refresh re-applies
--- status even if git's output hasn't changed. Used on explorer reopen
--- when the tree was rebuilt and nodes lost their badges.
function M.invalidate_cache()
	git_output_cache = nil
end

---@alias Beast.Explorer.GitStatusKind
---              ┌ When                                          ┌ Source
---| "conflict"  │ Merge in progress, this path needs resolution │ v2 record type u (any XY: UU/AA/DU/UD/…)
---| "deleted"   │ File removed                                  │ XY contains D (D., .D, MD, AD)
---| "added"     │ New file tracked by git                       │ XY contains A (A., AM, AD)
---| "renamed"   │ Path moved via git mv or detected rename      │ v2 type 2 with R
---| "copied"    │ New file detected as copy of another          │ v2 type 2 with C
---| "modified"  │ Content changed                               │ XY contains M (M., .M, MM)
---| "untracked" │ File not in index                             │ v2 record type ?
---| "ignored"   │ Excluded by .gitignore/exclude rules          │ v2 record type !

-- Kind priority (lower = higher priority).
-- Used by build_dir_status() to pick the "most urgent" descendant kind.
local KIND_PRIORITY = {
	conflict = 1,
	deleted = 2,
	added = 3,
	renamed = 4,
	copied = 5,
	modified = 6,
	untracked = 7,
	-- "ignored" intentionally omitted — it does NOT propagate
}

---@alias Beast.Explorer.GitStatusPhase
---              ┌ Meaning                             ┌ XY Pattern
---| "conflict"  │ Any 'u' record                      │ Unresolved merge
---| "both"      │ X≠. AND Y≠. (MM, AM, MD, AD, RM, …) │ Staged and further-changed in worktree
---| "unstaged"  │ Worktree differs from index         │ Worktree differs from index
---| "staged"    │ X≠., Y=. (M., A., D., R., C.)       │ Index differs from HEAD, worktree matches index
---| "untracked" │ ? record                            │ Not in index
---| "ignored"   │ ! record                            │ Excluded by gitignore

-- Phase priority (lower = higher priority). Used when aggregating dir phase
-- via merge_phase() — pure pairwise max, with one special rule: staged +
-- unstaged → both (regardless of priority).
local PHASE_PRIORITY = {
	conflict = 1,
	both = 2,
	unstaged = 3,
	staged = 4,
	untracked = 5,
	ignored = 6,
}

--- Map a single porcelain XY column letter to a `kind`.
---@param c string
---@return string?
local function letter_to_kind(c)
	-- stylua: ignore
	if c == "M" or c == "T" then return "modified" end
	-- stylua: ignore
	if c == "A" then return "added" end
	-- stylua: ignore
	if c == "D" then return "deleted" end
	-- stylua: ignore
	if c == "R" then return "renamed" end
	-- stylua: ignore
	if c == "C" then return "copied" end
	return nil
end

--- Decode an XY pair (from a v2 type-1 or type-2 record) into a kind+phase.
--- `kind` = highest-priority of the two columns' implied kinds.
--- `phase` = staged (only x non-dot) | unstaged (only y non-dot) | both.
---@param xy string
---@return Beast.Explorer.GitStatusKind?
---@return Beast.Explorer.GitStatusPhase?
local function xy_to_kind_phase(xy)
	-- stylua: ignore
	if #xy < 2 then return nil end
	local kx = letter_to_kind(xy:sub(1, 1))
	local ky = letter_to_kind(xy:sub(2, 2))

	local kind
	if kx and ky then
		kind = (KIND_PRIORITY[kx] <= KIND_PRIORITY[ky]) and kx or ky
	else
		kind = kx or ky
	end
	-- stylua: ignore
	if not kind then return nil end

	local phase
	if kx and ky then
		phase = "both"
	elseif kx then
		phase = "staged"
	else
		phase = "unstaged"
	end
	return kind, phase
end

---@class Beast.Explorer.GitStatus
---@field kind Beast.Explorer.GitStatusKind
---@field phase? Beast.Explorer.GitStatusPhase

--- Merge two phase values. Pairwise max-by-priority, with a special rule:
--- staged + unstaged → both. Used when aggregating directory phase from
--- multiple descendants.
---@param a string?
---@param b string?
---@return string?
local function merge_phase(a, b)
	-- stylua: ignore
	if not a then return b end
	-- stylua: ignore
	if not b then return a end
	if (a == "staged" and b == "unstaged") or (a == "unstaged" and b == "staged") then
		return "both"
	end
	return (PHASE_PRIORITY[a] <= PHASE_PRIORITY[b]) and a or b
end

--- Merge two `{kind, phase}` records (commutative, associative). Higher-priority
--- kind wins; phase merges via merge_phase. Used both by the parser (when the
--- same path appears in multiple porcelain records) and by build_dir_status.
---@param cur Beast.Explorer.GitStatus?
---@param new Beast.Explorer.GitStatus
---@return Beast.Explorer.GitStatus
local function merge_status(cur, new)
	-- stylua: ignore
	if not cur then return new end
	local kind = (KIND_PRIORITY[new.kind] < KIND_PRIORITY[cur.kind]) and new.kind or cur.kind
	return { kind = kind, phase = merge_phase(cur.phase, new.phase) }
end

--- Parse `git status --porcelain=v2 --ignored -z` output into a path → {kind, phase} table.
--- The `-z` flag makes records NUL-terminated and disables path quoting.
--- Rename/copy records (type `2`) consume two NUL-terminated tokens (new + orig path).
---@param output string  Raw stdout from git status (NUL-separated)
---@param git_root string  Absolute path to the git repository root
---@return table<string, Beast.Explorer.GitStatus>
function M.parse(output, git_root)
	local result = {} ---@type table<string, Beast.Explorer.GitStatus>
	local tokens = vim.split(output, "\0", { plain = true })

	local i = 1
	while i <= #tokens do
		local tok = tokens[i]
		i = i + 1

		-- stylua: ignore
		if tok == "" then goto continue end

		local kind_char = tok:sub(1, 1)
		---@type string, Beast.Explorer.GitStatusKind?, Beast.Explorer.GitStatusPhase?
		local path, kind, phase

		if kind_char == "1" then
			-- "1 XY sub mH mI mW hH hI <path>"
			local xy = tok:sub(3, 4)
			path = tok:match("^1 %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.+)$")
			kind, phase = xy_to_kind_phase(xy)
		elseif kind_char == "2" then
			-- "2 XY sub mH mI mW hH hI Xscore <path>" + separate <origPath> token
			local xy = tok:sub(3, 4)
			path = tok:match("^2 %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.+)$")
			kind, phase = xy_to_kind_phase(xy)
			i = i + 1 -- consume origPath token
		elseif kind_char == "u" then
			-- "u XY sub m1 m2 m3 mW h1 h2 h3 <path>"
			path = tok:match("^u %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ %S+ (.+)$")
			kind, phase = "conflict", "conflict"
		elseif kind_char == "?" then
			path = tok:sub(3)
			kind, phase = "untracked", "untracked"
		elseif kind_char == "!" then
			path = tok:sub(3)
			kind, phase = "ignored", "ignored"
		end
		-- "#" branch headers and any other kinds: silently skipped

		if path and kind then
			path = path:gsub("/$", "") -- strip trailing slash from untracked dirs
			local abs_path = git_root .. "/" .. path
			result[abs_path] = merge_status(result[abs_path], { kind = kind, phase = phase })
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
	git_output_cache = nil
	state.git.status = nil
	state.git.dir_status = nil
end

--- Build the directory-aggregate map: for every ancestor of every file in
--- `status`, record the merged {kind, phase} of all descendants. Kind takes
--- the highest-priority of any descendant; phase merges (staged + unstaged →
--- both, conflict beats all). Ignored does NOT propagate; untracked does.
--- Each ancestor walk short-circuits as soon as the current dir already
--- absorbs the new contribution (no kind upgrade AND no phase change).
---@param status table<string, Beast.Explorer.GitStatus>
---@return table<string, Beast.Explorer.GitStatus>
local function build_dir_status(status)
	local dir_status = {} ---@type table<string, Beast.Explorer.GitStatus>
	for abs_path, st in pairs(status) do
		-- stylua: ignore
		if not KIND_PRIORITY[st.kind] then goto continue end -- ignored doesn't propagate

		local dir = vim.fn.fnamemodify(abs_path, ":h")
		while dir and #dir > 0 do
			local cur = dir_status[dir]
			local merged = merge_status(cur, st)
			if cur and cur.kind == merged.kind and cur.phase == merged.phase then
				break -- this dir (and its ancestors) already absorb our contribution
			end
			dir_status[dir] = merged

			local parent = vim.fn.fnamemodify(dir, ":h")
			-- stylua: ignore
			if parent == dir then break end
			dir = parent
		end
		::continue::
	end
	return dir_status
end

--- Stamp `node.git_status` on every tree node from a direct status lookup,
--- falling back to the directory-aggregate map for ancestors of dirty files.
--- No sort, no per-node parent walk, no separate clear pass.
---@param status table<string, Beast.Explorer.GitStatus>
function M.apply(status)
	-- stylua: ignore
	if not state.tree then return end

	local dir_status = build_dir_status(status)
	state.git.dir_status = dir_status

	for path, node in pairs(state.tree.nodes) do
		node.git_status = status[path] or dir_status[path]
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

-- Pending hints accumulated across the debounce window. When schedule_refresh
-- is called multiple times before the timer fires:
--   * if any caller requested a full refresh (no `file` opt, or a gitignore/
--     gitattributes save) → pending_full wins and we do a full refresh.
--   * if exactly one unique file accumulated → partial refresh for that file.
--   * if >1 unique files → escalate to full refresh.
local pending_full = false
local pending_files = {} ---@type table<string, true>
local pending_on_done = nil ---@type fun()|nil

--- Refresh a single file's git status (much cheaper than a full repo scan).
--- Used by BufWritePost where only the saved file's status can have changed.
---@param file string  absolute path of the saved file
---@param on_done? fun()
local function refresh_file(file, on_done)
	-- stylua: ignore
	if not state.tree or not state.view or not state.view:is_valid() then
		if on_done then on_done() end
		return
	end

	local root = resolve_git_root()
	if not root then
		-- stylua: ignore
		if on_done then on_done() end
		return
	end

	-- File must live inside the repo
	if file:sub(1, #root + 1) ~= root .. "/" then
		-- stylua: ignore
		if on_done then on_done() end
		return
	end

	vim.system(
		{ "git", "-C", root, "status", "--porcelain=v2", "--ignored", "-z", "--", file },
		{ text = true },
		function(result)
			vim.schedule(function()
				-- stylua: ignore
				if not state.tree or not state.view or not state.view:is_valid() then
					if on_done then on_done() end
					return
				end
				-- stylua: ignore
				if result.code ~= 0 then
					if on_done then on_done() end
					return
				end

				local single = M.parse(result.stdout or "", root)
				local new_st = single[file] -- nil if file is now clean
				local old_st = state.git.status and state.git.status[file]

				-- Fast path: no change → nothing to do.
				local same = (new_st == nil and old_st == nil)
					or (new_st and old_st and new_st.kind == old_st.kind and new_st.phase == old_st.phase)
				if same then
					-- stylua: ignore
					if on_done then on_done() end
					return
				end

				-- Merge the single-file delta into the persisted status map,
				-- then re-stamp the tree. apply() rebuilds dir_status from
				-- the merged map, so ancestor decorations stay consistent.
				state.git.status = state.git.status or {}
				state.git.status[file] = new_st
				M.apply(state.git.status)

				-- Invalidate full-output cache so the next full refresh can't
				-- short-circuit and miss this single-file change.
				git_output_cache = nil

				-- stylua: ignore
				if on_done then on_done() end
			end)
		end
	)
end

--- Normalize the polymorphic refresh argument.
---@param opts? Beast.Explorer.GitRefreshOpts|fun()
---@return Beast.Explorer.GitRefreshOpts
local function normalize_opts(opts)
	if type(opts) == "function" then
		return { on_done = opts }
	end
	return opts or {}
end

--- Return true if the saved file requires a full refresh (its content affects
--- the git status of other files in the repo).
---@param file string  absolute path
---@return boolean
local function affects_other_files(file)
	local name = vim.fn.fnamemodify(file, ":t")
	return name == ".gitignore" or name == ".gitattributes"
end

---@class Beast.Explorer.GitRefreshOpts
---@field file? string   when set (and not .gitignore/.gitattributes), refresh only this path
---@field on_done? fun()

--- Refresh git status asynchronously. Cancels any in-flight full-refresh job.
--- Single-file refreshes do NOT cancel each other (they're independent).
---@param opts? Beast.Explorer.GitRefreshOpts|fun()  function form is shorthand for { on_done = fn }
function M.refresh(opts)
	opts = normalize_opts(opts)
	local on_done = opts.on_done or function() end

	if opts.file and not affects_other_files(opts.file) then
		refresh_file(opts.file, on_done)
		return
	end

	-- Full refresh path
	if not state.tree or not state.view or not state.view:is_valid() then
		on_done()
		return
	end

	-- Cancel in-flight full-refresh job
	if git_job then
		pcall(function()
			git_job:kill("sigterm")
		end)
		git_job = nil
	end

	local root = resolve_git_root()
	if not root then
		M.clear()
		on_done()
		return
	end
	git_job = vim.system(
		{ "git", "-C", root, "status", "--porcelain=v2", "--ignored", "-z" },
		{ text = true },
		function(result)
			git_job = nil
			vim.schedule(function()
				if not state.tree or not state.view or not state.view:is_valid() then
					on_done()
					return
				end

				if result.code ~= 0 then
					M.clear()
					git_output_cache = nil
					on_done()
					return
				end

				local output = result.stdout or ""
				-- Cache: skip parse+apply when output hasn't changed
				if output == git_output_cache then
					on_done()
					return
				end
				git_output_cache = output

				local status = M.parse(output, root)
				state.git.status = status
				M.apply(status)

				on_done()
			end)
		end
	)
end

--- Debounced refresh — collapses rapid triggers into one effective run.
--- Multiple distinct files saved within the debounce window escalate to a
--- full refresh; a single file stays partial.
---@param opts? Beast.Explorer.GitRefreshOpts|fun()
function M.schedule_refresh(opts)
	opts = normalize_opts(opts)

	if opts.file and not affects_other_files(opts.file) then
		pending_files[opts.file] = true
	else
		pending_full = true
	end
	if opts.on_done then
		pending_on_done = opts.on_done
	end

	if not git_timer then
		git_timer = assert((vim.uv or vim.loop).new_timer(), "failed to create timer")
	end

	git_timer:stop()
	git_timer:start(
		DEBOUNCE_MS,
		0,
		vim.schedule_wrap(function()
			local full = pending_full
			local files = pending_files
			local on_done = pending_on_done
			pending_full = false
			pending_files = {}
			pending_on_done = nil

			if full then
				M.refresh({ on_done = on_done })
				return
			end

			local only_file = nil
			local count = 0
			for f in pairs(files) do
				count = count + 1
				only_file = f
				if count > 1 then
					break
				end
			end

			if count == 1 then
				M.refresh({ file = only_file, on_done = on_done })
			elseif count > 1 then
				-- Multiple files saved in the debounce window — escalate to full
				M.refresh({ on_done = on_done })
			else
				-- No hints accumulated (shouldn't really happen) — full refresh
				M.refresh({ on_done = on_done })
			end
		end)
	)
end

--- Stop debounce timer and cancel in-flight job. Called on explorer close.
function M.stop()
	if git_timer then
		git_timer:stop()
		git_timer:close()
		git_timer = nil
	end
	if git_job then
		pcall(function()
			git_job:kill("sigterm")
		end)
		git_job = nil
	end
	pending_full = false
	pending_files = {}
	pending_on_done = nil
end

return M
