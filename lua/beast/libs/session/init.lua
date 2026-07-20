local Config = require("beast.libs.session.config")

local uv = vim.uv or vim.loop

local M = {}
local replay_group
local retry_active = false
local retry_budget = 0
local RETRY_MAX = 100
local RETRY_MS = 120
local REPLAY_WAIT_MS = 4000
local REPLAY_WAIT_STEP_MS = 50

---@type table<string, integer[]>
local pending_folds_by_file = {}

---@type Beast.Lib.Meta
M.meta = { name = "session", description = "Auto-saves and restores the editor session per project directory and git branch" }

---@param s string
---@return string
local function encode(s)
	return (s:gsub("[\\/:]+", "%%"))
end

---@return string
local function plain_path()
	return Config.dir .. encode(vim.fn.getcwd()) .. ".vim"
end

--- Current git branch, or nil if not in a git repo, on main/master, or
--- branch detection fails.
---@return string?
local function branch_name()
	if not uv.fs_stat(".git") then
		return nil
	end
	local branch = vim.fn.systemlist("git branch --show-current")[1]
	if vim.v.shell_error ~= 0 or not branch or branch == "" then
		return nil
	end
	if branch == "main" or branch == "master" then
		return nil
	end
	return branch
end

---@return string?
local function branch_path()
	local branch = branch_name()
	if not branch then
		return nil
	end
	return Config.dir .. encode(vim.fn.getcwd()) .. "%%" .. encode(branch) .. ".vim"
end

---@return boolean
local function has_real_buffer()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
			return true
		end
	end
	return false
end

local function save()
	if not has_real_buffer() then
		return
	end
	local path = branch_path() or plain_path()
	vim.cmd("mksession! " .. vim.fn.fnameescape(path))
end

---@param path string
---@return string
local function normalize_path(path)
	if path == "" then
		return ""
	end
	local expanded = vim.fn.expand(path)
	if expanded == "" then
		return ""
	end
	return vim.fn.fnamemodify(expanded, ":p"):gsub("/$", "")
end

---@param buf integer
---@return boolean
local function try_apply_closed_folds(buf)
	if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
		return false
	end
	local file = normalize_path(vim.api.nvim_buf_get_name(buf))
	if file == "" then
		return false
	end
	local closed_lines = pending_folds_by_file[file]
	if not closed_lines or #closed_lines == 0 then
		return false
	end

	local applied_any = false
	local max_line = vim.api.nvim_buf_line_count(buf)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
			vim.api.nvim_win_call(win, function()
				local view = vim.fn.winsaveview()
				vim.cmd("silent! normal! zx")
				for _, lnum in ipairs(closed_lines) do
					if lnum >= 1 and lnum <= max_line then
						vim.api.nvim_win_set_cursor(win, { lnum, 0 })
						vim.cmd("silent! normal! zc")
						if vim.fn.foldclosed(lnum) ~= -1 then
							applied_any = true
						end
					end
				end
				pcall(vim.fn.winrestview, view)
			end)
		end
	end

	if applied_any then
		pending_folds_by_file[file] = nil
	end
	return applied_any
end

local function has_pending_folds()
	return next(pending_folds_by_file) ~= nil
end

local function replay_all_pending()
	if not has_pending_folds() then
		return
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		try_apply_closed_folds(buf)
	end
end

local function schedule_retry()
	if retry_active then
		return
	end
	retry_active = true
	retry_budget = RETRY_MAX
	local function tick()
		if not has_pending_folds() then
			retry_active = false
			return
		end
		replay_all_pending()
		retry_budget = retry_budget - 1
		if retry_budget <= 0 or not has_pending_folds() then
			retry_active = false
			return
		end
		vim.defer_fn(tick, RETRY_MS)
	end
	vim.defer_fn(tick, RETRY_MS)
end

local function ensure_replay_autocmds()
	if replay_group then
		return
	end
	replay_group = vim.api.nvim_create_augroup("BeastSessionFoldReplay", { clear = true })
	local function replay(args)
		if not has_pending_folds() then
			return
		end
		vim.schedule(function()
			if not has_pending_folds() then
				return
			end
			if args.buf and args.buf > 0 then
				try_apply_closed_folds(args.buf)
			end
			if has_pending_folds() then
				schedule_retry()
			end
		end)
	end
	vim.api.nvim_create_autocmd("BufWinEnter", { group = replay_group, callback = replay })
	vim.api.nvim_create_autocmd("LspAttach", { group = replay_group, callback = replay })
end

---@param session_file string
local function collect_pending_closed_folds(session_file)
	pending_folds_by_file = {}
	local ok, lines = pcall(vim.fn.readfile, session_file)
	if not ok or type(lines) ~= "table" then
		return
	end

	local current_file = ""
	for i = 1, #lines - 1 do
		local line = lines[i]
		local edit = line:match("^edit%s+(.+)$")
		if edit then
			current_file = normalize_path(edit)
		end
		local lnum = tonumber(line)
		if lnum and current_file ~= "" and lines[i + 1] == "sil! normal! zc" then
			local list = pending_folds_by_file[current_file]
			if not list then
				list = {}
				pending_folds_by_file[current_file] = list
			end
			list[#list + 1] = lnum
		end
	end
end

---@param opts? Beast.Session.Config
function M.setup(opts)
	Config.setup(opts)
	vim.fn.mkdir(Config.dir, "p")
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("BeastSession", { clear = true }),
		callback = save,
	})
end

--- Load the session for the current directory + git branch, falling back to
--- the plain directory session if no branch-specific one exists. No-op if
--- neither exists.
function M.load()
	local bp = branch_path()
	local file = (bp and vim.fn.filereadable(bp) == 1) and bp or plain_path()
	if vim.fn.filereadable(file) == 1 then
		vim.cmd("silent! source " .. vim.fn.fnameescape(file))
		collect_pending_closed_folds(file)
		if has_pending_folds() then
			replay_all_pending()
			if has_pending_folds() then
				ensure_replay_autocmds()
				schedule_retry()
				vim.wait(REPLAY_WAIT_MS, function()
					replay_all_pending()
					return not has_pending_folds()
				end, REPLAY_WAIT_STEP_MS)
			end
		end
	end
end

--- Whether a session exists for the current directory + git branch (or the
--- plain directory session, as a fallback).
---@return boolean
function M.exists()
	local bp = branch_path()
	if bp and vim.fn.filereadable(bp) == 1 then
		return true
	end
	return vim.fn.filereadable(plain_path()) == 1
end

return M
