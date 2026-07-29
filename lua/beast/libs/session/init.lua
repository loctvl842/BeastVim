local Config = require("beast.libs.session.config")

local uv = vim.uv or vim.loop

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "session", description = "Auto-saves and restores the editor session per project directory and git branch" }

local function project_dir()
	local ok, dir = pcall(function()
		return Util.root()
	end)
	if ok and dir then
		return dir
	end
	return vim.fn.getcwd()
end

---@param s string
---@return string
local function encode(s)
	return (s:gsub("[\\/:]+", "%%"))
end

---@return string
local function plain_path()
	return Config.dir .. encode(project_dir()) .. ".vim"
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
	return Config.dir .. encode(project_dir()) .. "%%" .. encode(branch) .. ".vim"
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

---@param vim_path string  path to a `.vim` session file (plain or branch identity)
---@return string
local function explorer_sidecar_path(vim_path)
	return (vim_path:gsub("%.vim$", ".explorer.json"))
end

--- Snapshot the explorer's root, expanded folders, and focus, then close its
--- window so `:mksession` never has to capture the synthetic explorer buffer.
--- Returns nil when the explorer wasn't open.
---@return { root: string, open_dirs: string[], focus: "explorer"|"main" }?
local function capture_explorer_state()
	local explorer_state = require("beast.libs.explorer.state")
	if not (explorer_state.view and explorer_state.view:is_valid() and explorer_state.tree) then
		return nil
	end

	local root = explorer_state.tree.root.path
	local open_dirs = {}
	for path, node in pairs(explorer_state.tree.nodes) do
		if node.dir and node.open and path ~= root then
			open_dirs[#open_dirs + 1] = path
		end
	end
	table.sort(open_dirs)

	local focus = (vim.api.nvim_get_current_win() == explorer_state.view.win) and "explorer" or "main"

	require("beast.libs.explorer").close()

	return { root = root, open_dirs = open_dirs, focus = focus }
end

local function save()
	if not has_real_buffer() then
		return
	end
	local target = branch_path() or plain_path()
	local explorer_snapshot = capture_explorer_state()
	vim.cmd("mksession! " .. vim.fn.fnameescape(target))
	local sidecar = explorer_sidecar_path(target)
	if explorer_snapshot then
		vim.fn.writefile({ vim.json.encode(explorer_snapshot) }, sidecar)
	else
		vim.fn.delete(sidecar)
	end
end

M.save = save

---@param opts? Beast.Session.Config
function M.setup(opts)
	Config.setup(opts)
	vim.fn.mkdir(Config.dir, "p")
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("BeastSession", { clear = true }),
		callback = save,
	})
end

--- Reopen the explorer from a `.explorer.json` sidecar (if any) written by a
--- prior save(): same root, same expanded folders, same focus. Silently does
--- nothing when there's no sidecar, it fails to decode, or its root no
--- longer exists on disk.
---@param vim_path string  the `.vim` session file that was just sourced
local function restore_explorer_state(vim_path)
	local sidecar = explorer_sidecar_path(vim_path)
	if vim.fn.filereadable(sidecar) ~= 1 then
		return
	end

	local ok, snapshot = pcall(vim.json.decode, vim.fn.readfile(sidecar)[1])
	if not ok or type(snapshot) ~= "table" or vim.fn.isdirectory(snapshot.root) ~= 1 then
		return
	end

	-- The rest of the session already restored fine by this point; an
	-- unexpected error rebuilding the explorer should degrade to "explorer
	-- didn't come back" rather than surface as an uncaught error.
	pcall(function()
		require("beast.libs.explorer").open(snapshot.root, { restore = true })

		local explorer_state = require("beast.libs.explorer.state")
		for _, dir in ipairs(snapshot.open_dirs or {}) do
			if vim.fn.isdirectory(dir) == 1 then
				explorer_state.tree:open(dir)
			end
		end
		require("beast.libs.explorer.ui").render()

		if snapshot.focus == "main" and explorer_state.source_win then
			pcall(vim.api.nvim_set_current_win, explorer_state.source_win)
		end
	end)
end

--- Load the session for the current directory + git branch, falling back to
--- the plain directory session if no branch-specific one exists. No-op if
--- neither exists.
function M.load()
	local bp = branch_path()
	local file = (bp and vim.fn.filereadable(bp) == 1) and bp or plain_path()
	if vim.fn.filereadable(file) == 1 then
		vim.cmd("silent! source " .. vim.fn.fnameescape(file))
		restore_explorer_state(file)
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
