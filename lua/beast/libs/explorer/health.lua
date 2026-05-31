local M = {}

local uv = vim.uv or vim.loop

local function file_exists(path)
	return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

function M.check()
	local health = vim.health

	-- ===========================================================================
	-- Environment
	-- ===========================================================================
	health.start("beast.libs.explorer")

	if vim.fn.has("nvim-0.10") == 1 then
		health.ok("Neovim >= 0.10")
	else
		health.error("Neovim 0.10+ required")
		return
	end

	if uv and type(uv.new_fs_event) == "function" then
		health.ok("vim.uv (libuv) available — fs_event supported")
	else
		health.error("vim.uv unavailable — explorer requires fs_event for live updates")
		return
	end

	-- ===========================================================================
	-- Module loadability
	-- ===========================================================================
	health.start("beast.libs.explorer — modules")

	local submods = {
		"config", "state", "tree", "ui", "render", "git", "watch",
		"sticky", "autocmds", "keymaps", "prompt", "highlights",
	}
	local actions = {
		"open", "split_open", "system_open", "create", "delete", "trash",
		"rename", "navigate_up", "set_root", "show_hidden",
		"copy_to_clipboard", "cut_to_clipboard", "paste_from_clipboard",
		"_trash_cmd",
	}

	local function check_require(name)
		local ok, err = pcall(require, name)
		if ok then
			health.ok(name)
		else
			health.error(name .. " failed to load: " .. tostring(err))
		end
		return ok
	end

	for _, m in ipairs(submods) do
		check_require("beast.libs.explorer." .. m)
	end
	for _, a in ipairs(actions) do
		check_require("beast.libs.explorer.actions." .. a)
	end

	-- ===========================================================================
	-- External deps
	-- ===========================================================================
	health.start("beast.libs.explorer — external deps")

	if vim.fn.executable("git") == 1 then
		health.ok("`git` executable found")
	else
		health.warn("`git` not found — status badges will be disabled")
	end

	local trash_cmds = { "trash", "gio", "rmtrash", "gvfs-trash" }
	local found_trash
	for _, cmd in ipairs(trash_cmds) do
		if vim.fn.executable(cmd) == 1 then
			found_trash = cmd
			break
		end
	end
	if found_trash then
		health.ok("Trash command found: `" .. found_trash .. "`")
	else
		health.warn("No trash command found (tried: " .. table.concat(trash_cmds, ", ") .. ") — `d` (trash) action will fail")
	end

	-- ===========================================================================
	-- Optional icon providers
	-- ===========================================================================
	health.start("beast.libs.explorer — icon providers (optional)")

	local has_mini = pcall(require, "mini.icons")
	if has_mini then
		health.ok("mini.icons installed — directory icons available")
	else
		health.warn("mini.icons not installed — directory icons fall back to plain glyphs (optional, but recommended for better visuals)")
	end

	local has_devicons = pcall(require, "nvim-web-devicons")
	if has_devicons then
		health.ok("nvim-web-devicons installed — file icons available")
	else
		health.warn("nvim-web-devicons not installed — file icons fall back to a single glyph (optional, but recommended for better visuals)")
	end

	if not has_mini and not has_devicons then
		health.warn("Neither mini.icons nor nvim-web-devicons installed — explorer will render without per-filetype icons")
	end

	-- ===========================================================================
	-- Highlight groups
	-- ===========================================================================
	health.start("beast.libs.explorer — highlights")

	local required_hls = {
		"BeastExplorerNormal", "BeastExplorerTitle", "BeastExplorerDir",
		"BeastExplorerFile", "BeastExplorerIndent", "BeastExplorerComment",
		"BeastExplorerClip",
		"BeastExplorerGitConflict", "BeastExplorerGitBoth",
		"BeastExplorerGitUnstaged", "BeastExplorerGitStaged",
		"BeastExplorerGitUntracked", "BeastExplorerGitIgnored",
	}
	local missing_hls = {}
	for _, hl_name in ipairs(required_hls) do
		local hl = vim.api.nvim_get_hl(0, { name = hl_name })
		if vim.tbl_isempty(hl) then
			missing_hls[#missing_hls + 1] = hl_name
		end
	end
	if #missing_hls == 0 then
		health.ok(string.format("All %d highlight groups defined", #required_hls))
	else
		health.warn("Missing highlight groups: " .. table.concat(missing_hls, ", "))
	end

	-- ===========================================================================
	-- Config & keymap sanity
	-- ===========================================================================
	health.start("beast.libs.explorer — configuration")

	local ok_cfg, config = pcall(require, "beast.libs.explorer.config")
	if not ok_cfg then
		health.error("config failed to load: " .. tostring(config))
		return
	end

	health.info(string.format("style = %s", tostring(config.style)))
	health.info(string.format("width = %s, side = %s", tostring(config.width), tostring(config.side)))
	health.info(string.format("show_hidden = %s, icons = %s, sticky = %s",
		tostring(config.show_hidden), tostring(config.icons), tostring(config.sticky)))

	local mappings = config.mappings or {}
	local count, seen, dupes = 0, {}, {}
	for lhs, action in pairs(mappings) do
		count = count + 1
		if seen[lhs] then
			dupes[#dupes + 1] = lhs
		end
		seen[lhs] = action
	end
	if #dupes == 0 then
		health.ok(string.format("%d keymaps configured, no duplicates", count))
	else
		health.warn("Duplicate keymap LHS: " .. table.concat(dupes, ", "))
	end

	-- Verify every mapped action resolves to an action module
	local missing_actions = {}
	for _, action in pairs(mappings) do
		local action_mod = "beast.libs.explorer.actions." .. action
		if not pcall(require, action_mod) then
			missing_actions[#missing_actions + 1] = action
		end
	end
	if #missing_actions == 0 then
		health.ok("All mapped actions resolve to modules")
	else
		health.error("Mapped actions with no module: " .. table.concat(missing_actions, ", "))
	end

	-- ===========================================================================
	-- Tree + Render dry-run (uses tmp dir, no UI)
	-- ===========================================================================
	health.start("beast.libs.explorer — tree & render dry-run")

	local tmp_root = vim.fn.tempname()
	vim.fn.mkdir(tmp_root, "p")
	vim.fn.mkdir(tmp_root .. "/sub", "p")
	vim.fn.writefile({ "hello" }, tmp_root .. "/a.txt")
	vim.fn.writefile({ "world" }, tmp_root .. "/sub/b.txt")

	local watch_mod = require("beast.libs.explorer.watch")
	local function cleanup_tmp()
		-- Unwatch anything the tree expansion installed under tmp_root
		local state = require("beast.libs.explorer.state")
		for path, _ in pairs(state.watchers) do
			if path == tmp_root or path:sub(1, #tmp_root + 1) == tmp_root .. "/" then
				watch_mod.unwatch(path)
			end
		end
		vim.fn.delete(tmp_root, "rf")
	end

	local ok_tree, tree_or_err = pcall(function()
		local Tree = require("beast.libs.explorer.tree")
		local t = Tree(tmp_root)
		t:expand(t.root)
		return t
	end)

	if not ok_tree then
		health.error("Tree build failed: " .. tostring(tree_or_err))
		cleanup_tmp()
	else
		local tree = tree_or_err
		if tree.root and tree.root.path and next(tree.root.children) ~= nil then
			local child_count = vim.tbl_count(tree.root.children)
			health.ok(string.format("Tree built on tmp dir, root has %d children", child_count))
		else
			health.error("Tree built but root.children is empty (expected `sub/` and `a.txt`)")
		end

		local ok_flat, flat_or_err = pcall(tree.flat, tree, { show_hidden = true })
		if ok_flat and type(flat_or_err) == "table" then
			health.ok(string.format("tree:flat() returned %d nodes", #flat_or_err))

			-- render.build reads state.tree directly; install ours temporarily.
			local state = require("beast.libs.explorer.state")
			local saved_tree, saved_clip = state.tree, state.clipboard
			state.tree = tree
			state.clipboard = nil

			local ok_render, lines, hls, badges = pcall(function()
				local render = require("beast.libs.explorer.render")
				return render.build(flat_or_err)
			end)

			state.tree, state.clipboard = saved_tree, saved_clip

			if not ok_render then
				health.error("render.build() raised: " .. tostring(lines))
			elseif type(lines) ~= "table" or #lines == 0 then
				health.error("render.build() returned no lines")
			elseif type(hls) ~= "table" then
				health.error("render.build() returned non-table highlights")
			else
				health.ok(string.format("render.build() returned %d lines, %d highlights, %d badges",
					#lines, #hls, badges and #badges or 0))
			end
		else
			health.error("tree:flat() failed: " .. tostring(flat_or_err))
		end

		cleanup_tmp()
	end

	-- ===========================================================================
	-- Watch dry-run (raw uv.fs_event, no state pollution)
	-- ===========================================================================
	health.start("beast.libs.explorer — watch dry-run")

	local watch_tmp = vim.fn.tempname()
	local mkdir_ok = vim.fn.mkdir(watch_tmp, "p") == 1 and vim.fn.isdirectory(watch_tmp) == 1

	if not mkdir_ok then
		health.error("Could not create tmp dir for watcher test: " .. watch_tmp)
	else
		local handle = uv.new_fs_event()
		if not handle then
			health.error("uv.new_fs_event() returned nil — cannot test watcher")
			vim.fn.delete(watch_tmp, "rf")
		else
			local fired = false
			local start_ok = pcall(handle.start, handle, watch_tmp, {}, function()
				fired = true
			end)

			if not start_ok then
				health.error("handle:start() failed on tmp dir")
				pcall(handle.close, handle)
				vim.fn.delete(watch_tmp, "rf")
			else
				-- Trigger events via a libuv timer. Re-check the dir each tick
				-- in case something nuked it, and write multiple times because
				-- macOS FSEvents may need a brief settling period after start.
				local probe_path = watch_tmp .. "/probe.txt"
				local trigger_timer = uv.new_timer()
				local tick = 0
				trigger_timer:start(50, 100, vim.schedule_wrap(function()
					tick = tick + 1
					if vim.fn.isdirectory(watch_tmp) == 1 then
						pcall(vim.fn.writefile, { "trigger" .. tick }, probe_path)
					end
				end))

				local got = vim.wait(1000, function()
					return fired
				end, 20)

				pcall(trigger_timer.stop, trigger_timer)
				pcall(trigger_timer.close, trigger_timer)
				pcall(handle.stop, handle)
				pcall(handle.close, handle)
				vim.fn.delete(watch_tmp, "rf")

				if got then
					health.ok("fs_event fired within 1s of file creation")
				else
					health.warn("fs_event did not fire within 1s — filesystem may not support inotify/FSEvents reliably (live updates may lag)")
				end
			end
		end
	end

	-- ===========================================================================
	-- Git dry-run (exercises the same parse path as git.refresh)
	-- ===========================================================================
	health.start("beast.libs.explorer — git dry-run")

	if vim.fn.executable("git") ~= 1 then
		health.info("Skipped: `git` not installed")
	else
		local cwd = vim.fn.getcwd()
		local git_dir = vim.fs.find(".git", { path = cwd, upward = true })[1]
		if not git_dir then
			health.info(string.format("Skipped: cwd (%s) is not inside a git repo", cwd))
		else
			local root = vim.fn.fnamemodify(git_dir, ":h")
			local done, exit_code, stdout = false, nil, nil

			local ok_sys = pcall(vim.system,
				{ "git", "-C", root, "status", "--porcelain=v2", "--ignored", "-z" },
				{ text = true },
				function(result)
					exit_code = result.code
					stdout = result.stdout or ""
					done = true
				end
			)

			if not ok_sys then
				health.error("vim.system() failed to launch git")
			else
				local finished = vim.wait(1000, function()
					return done
				end, 20)

				if not finished then
					health.warn("git status did not return within 1s — large repo or slow disk")
				elseif exit_code ~= 0 then
					health.error(string.format("git status exited with code %d", exit_code or -1))
				else
					local ok_parse, parsed = pcall(function()
						return require("beast.libs.explorer.git").parse(stdout, root)
					end)
					if not ok_parse then
						health.error("git.parse() raised: " .. tostring(parsed))
					else
						local n = vim.tbl_count(parsed)
						health.ok(string.format("git refresh OK on %s (%d status entries)", root, n))
					end
				end
			end
		end
	end
end

return M
