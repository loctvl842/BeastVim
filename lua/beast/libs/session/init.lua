local Config = require("beast.libs.session.config")

local uv = vim.uv or vim.loop

local M = {}

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
