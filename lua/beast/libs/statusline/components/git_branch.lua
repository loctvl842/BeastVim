local sep = package.config:sub(1, 1)
local uv = vim.uv or vim.loop

local git_dir_by_dir = {}
local branch_by_git_dir = {}
local watchers = {}

local function read_head(head_path)
	local f = io.open(head_path)
	if not f then
		return nil
	end
	local head = f:read()
	f:close()
	if not head then
		return nil
	end
	local branch = head:match("ref: refs/heads/(.+)$")
	return branch or head:sub(1, 7)
end

---@param start_dir string
---@return string? git_dir
local function resolve_git_dir(start_dir)
	if not start_dir or start_dir == "" then
		return nil
	end
	local cached = git_dir_by_dir[start_dir]
	if cached ~= nil then
		return cached or nil
	end

	local dir = start_dir
	while dir and dir ~= "" do
		if git_dir_by_dir[dir] ~= nil then
			git_dir_by_dir[start_dir] = git_dir_by_dir[dir]
			return git_dir_by_dir[dir] or nil
		end

		local git_path = dir .. sep .. ".git"
		local stat = uv.fs_stat(git_path)
		if stat then
			local git_dir
			if stat.type == "directory" then
				git_dir = git_path
			elseif stat.type == "file" then
				local f = io.open(git_path)
				if f then
					local content = f:read()
					f:close()
					git_dir = content and content:match("gitdir: (.+)$")
					if git_dir and git_dir:sub(1, 1) ~= sep and not git_dir:match("^%a:.*$") then
						git_dir = git_path:match("(.*).git") .. git_dir
					end
				end
			end
			if git_dir and uv.fs_stat(git_dir .. sep .. "HEAD") then
				git_dir_by_dir[dir] = git_dir
				git_dir_by_dir[start_dir] = git_dir
				return git_dir
			end
		end

		local parent = dir:match("(.*)" .. sep .. ".-$")
		if parent == dir or parent == nil or parent == "" then
			break
		end
		dir = parent
	end

	git_dir_by_dir[start_dir] = false
	return nil
end

---@param git_dir string
local function ensure_watcher(git_dir)
	if watchers[git_dir] then
		return
	end
	local handle = uv.new_fs_event()
	if not handle then
		return
	end
	watchers[git_dir] = handle
	handle:start(
		git_dir .. sep .. "HEAD",
		{},
		vim.schedule_wrap(function()
			branch_by_git_dir[git_dir] = nil
			vim.api.nvim_exec_autocmds("User", { pattern = "BeastStatuslineGitChanged" })
		end)
	)
end

---@param bufnr integer
---@param winid integer
---@return string?
local function branch_for_buf(bufnr, winid)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local file_dir
	if name ~= "" then
		file_dir = vim.fn.fnamemodify(name, ":p:h")
	else
		file_dir = vim.fn.getcwd(winid)
	end
	local git_dir = resolve_git_dir(file_dir)
	if not git_dir then
		return nil
	end
	ensure_watcher(git_dir)
	local cached = branch_by_git_dir[git_dir]
	if cached ~= nil then
		return cached
	end
	local branch = read_head(git_dir .. sep .. "HEAD")
	branch_by_git_dir[git_dir] = branch or ""
	return branch
end

---@type Beast.Statusline.ComponentSpec
return {
	update = { "BufEnter", "DirChanged", "User BeastStatuslineGitChanged" },
	scope = "buffer",
	priority = 60,
	provider = function(ctx)
		local branch = branch_for_buf(ctx.bufnr, ctx.winid)
		if not branch or branch == "" then
			branch = "!=vcs"
		end
		return {
			{ text = "   ", hl = { fg = "text" } },
			{ text = branch, hl = { fg = "accent4", bold = true } },
		}
	end,
}
