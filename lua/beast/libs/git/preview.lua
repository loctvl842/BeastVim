-- Hunk preview float.
--
-- open_for_current_line() finds the hunk under the cursor and opens a
-- floating window showing the diff for that hunk: deleted lines in
-- DiffDelete, added lines in DiffAdd.
--
-- Auto-closes on source-buffer CursorMoved / BufLeave / WinScrolled.
-- Inside the float, `q` and `<Esc>` close manually.

local api = vim.api
local View = require("beast.libs.view")

local M = {}

---@class Beast.Git.PreviewView : Beast.View
local PreviewView = View:extend()

---@type Beast.Git.PreviewView?
local current

-- =========================================================================
-- Hunk helpers
-- =========================================================================

---@param hunk Beast.Git.RawHunk
---@param cursor_line integer
---@return boolean
local function hunk_contains(hunk, cursor_line)
	if hunk.b_count == 0 then
		local anchor = hunk.b_start == 0 and 1 or hunk.b_start
		return cursor_line == anchor
	end
	return cursor_line >= hunk.b_start and cursor_line <= hunk.b_start + hunk.b_count - 1
end

---@param hunks Beast.Git.RawHunk[]
---@param cursor_line integer
---@return Beast.Git.RawHunk?
local function find_hunk(hunks, cursor_line)
	for _, h in ipairs(hunks) do
		if hunk_contains(h, cursor_line) then
			return h
		end
	end
end

---@param base string
---@param hunk Beast.Git.RawHunk
---@return string[]
local function slice_base(base, hunk)
	if hunk.a_count == 0 then
		return {}
	end
	local all = vim.split(base, "\n", { plain = true })
	local out = {}
	for i = hunk.a_start, hunk.a_start + hunk.a_count - 1 do
		out[#out + 1] = all[i] or ""
	end
	return out
end

---@param buf integer
---@param hunk Beast.Git.RawHunk
---@return string[]
local function slice_current(buf, hunk)
	if hunk.b_count == 0 then
		return {}
	end
	return api.nvim_buf_get_lines(buf, hunk.b_start - 1, hunk.b_start + hunk.b_count - 1, false)
end

-- =========================================================================
-- View helpers
-- =========================================================================

---@param removed string[]
---@param added string[]
---@return string[] body, table<integer, string> hls
local function build_body(removed, added)
	local body, hls = {}, {}
	for _, l in ipairs(removed) do
		body[#body + 1] = "- " .. l
		hls[#body] = "DiffDelete"
	end
	for _, l in ipairs(added) do
		body[#body + 1] = "+ " .. l
		hls[#body] = "DiffAdd"
	end
	return body, hls
end

---@param lines string[]
---@return integer
local function max_width(lines)
	local w = 1
	for _, l in ipairs(lines) do
		local lw = vim.fn.strdisplaywidth(l)
		if lw > w then
			w = lw
		end
	end
	return w
end

---@param body string[]
---@param hls table<integer, string>
---@return integer buf, integer win
local function open_float(body, hls)
	local buf = api.nvim_create_buf(false, true)
	api.nvim_buf_set_lines(buf, 0, -1, false, body)
	vim.bo[buf].bufhidden = "wipe"

	local ns = api.nvim_create_namespace("beast_git_preview")
	for row, hl in pairs(hls) do
		api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { line_hl_group = hl })
	end

	local width = math.min(max_width(body) + 2, math.floor(vim.o.columns * 0.8))
	local height = math.min(#body, math.floor(vim.o.lines * 0.4))

	local win = api.nvim_open_win(buf, false, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		focusable = true,
		noautocmd = true,
	})
	vim.api.nvim_set_option_value("winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	return buf, win
end

---@param buf integer  preview buffer
---@param source_buf integer  buffer whose cursor opened the preview
local function wire_close(buf, source_buf)
	vim.keymap.set("n", "q", M.close, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<Esc>", M.close, { buffer = buf, nowait = true, silent = true })

	local group = api.nvim_create_augroup("BeastGitPreview", { clear = true })
	api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "WinScrolled" }, {
		group = group,
		buffer = source_buf,
		once = true,
		callback = M.close,
	})
end

-- =========================================================================
-- Public API
-- =========================================================================

function M.close()
	if current then
		current:close()
		current = nil
	end
end

function M.open_for_current_line()
	local git = require("beast.libs.git")
	local hunks = git.get_hunks()
	if #hunks == 0 then
		vim.notify("No hunks in this buffer", vim.log.levels.INFO, { title = "beast.git" })
		return
	end

	local source_buf = api.nvim_get_current_buf()
	local cursor = api.nvim_win_get_cursor(0)[1]
	local hunk = find_hunk(hunks, cursor)
	if not hunk then
		vim.notify("No hunk under cursor", vim.log.levels.INFO, { title = "beast.git" })
		return
	end

	local st = git._get_state()
	if not st then
		return
	end

	local body, hls = build_body(slice_base(st.base, hunk), slice_current(source_buf, hunk))
	if #body == 0 then
		return
	end

	M.close()
	local buf, win = open_float(body, hls)
	current = PreviewView(buf, win)
	wire_close(buf, source_buf)
end

return M
