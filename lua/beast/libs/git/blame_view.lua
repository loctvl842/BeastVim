-- Full-file blame side window.
--
-- `open(source_winid, opts)` opens a left-side vertical split aligned
-- line-for-line with the source buffer. Each row shows
-- `<sha8> <author> <relative-date>`. Scroll is synced via Neovim's
-- native `scrollbind`.
--
-- Keymaps inside the blame buffer:
--   <CR>     show full commit diff in a float (git show <sha>)
--   r        reblame parent (<sha>^) of the commit under cursor
--   R        reset revision to HEAD
--   q / <Esc> close
--
-- Singleton: only one blame view at a time, like `preview.lua`. Calling
-- `open` again closes the existing one first.
--
-- Lifecycle: a per-instance autocmd group closes the view when either the
-- source window goes away or the source buffer is wiped.

local api = vim.api

local View = require("beast.libs.view")
local blame_mod = require("beast.libs.git.blame")
local current_line_blame = require("beast.libs.git.current_line_blame")

local M = {}

local NS = api.nvim_create_namespace("beast_git_blame_view")

---@class Beast.Git.BlameView : Beast.View
---@field source_buf integer
---@field source_win integer
---@field revision string? Currently displayed revision (nil = HEAD)
---@field augroup integer
---@field source_scrollbind_prev boolean Captured at open so close can restore it
---@field blame table<integer, Beast.Git.BlameInfo>?
local BlameView = View:extend()

---@type Beast.Git.BlameView?
local current

-- =========================================================================
-- Rendering
-- =========================================================================

---@param blame table<integer, Beast.Git.BlameInfo>
---@param total_lines integer
---@return string[] body
---@return { sha: integer, author: integer, date: integer }[] hl_cols  per-row column ranges
---@return integer width
local function render(blame, total_lines)
	local author_max = 0
	for i = 1, total_lines do
		local info = blame[i]
		if info then
			local a = info.commit.author or ""
			local w = vim.fn.strdisplaywidth(a)
			if w > author_max then
				author_max = w
			end
		end
	end
	author_max = math.min(author_max, 20)

	local body = {}
	local hl_cols = {}
	for i = 1, total_lines do
		local info = blame[i]
		if not info then
			body[i] = ""
			hl_cols[i] = { sha = 0, author = 0, date = 0 }
		else
			local c = info.commit
			local sha = c.abbrev_sha or ""
			-- Char-aware slice + display-width padding so multibyte author
			-- names (e.g. "Tomáš") render cleanly and the column stays aligned.
			local author = vim.fn.strcharpart(c.author or "", 0, author_max)
			local author_w = vim.fn.strdisplaywidth(author)
			local author_pad = author .. string.rep(" ", math.max(0, author_max - author_w))
			local date
			if c.sha == blame_mod._NOT_COMMITTED_SHA then
				date = "uncommitted"
			else
				date = current_line_blame._relative_time(c.author_time)
			end
			body[i] = string.format("%s %s  %s", sha, author_pad, date)
			-- Byte offsets (extmarks are byte-indexed) — the leading SHA is
			-- 8 ASCII chars, then a space, then `author_max` bytes of
			-- author (truncated at byte boundary above), then two spaces.
			local sha_end = #sha
			local author_start = sha_end + 1
			local author_end = author_start + #author_pad
			local date_start = author_end + 2
			local date_end = date_start + #date
			hl_cols[i] = {
				sha = { 0, sha_end },
				author = { author_start, author_end },
				date = { date_start, date_end },
			}
		end
	end

	-- 8 (sha) + 1 + author_max + 2 + ~12 relative-date typical
	local width = 8 + 1 + author_max + 2 + 14
	return body, hl_cols, width
end

---@param buf integer
---@param hl_cols table[]
local function paint_hls(buf, hl_cols)
	api.nvim_buf_clear_namespace(buf, NS, 0, -1)
	for i, cols in ipairs(hl_cols) do
		if cols.sha and type(cols.sha) == "table" then
			api.nvim_buf_set_extmark(buf, NS, i - 1, cols.sha[1], { end_col = cols.sha[2], hl_group = "BeastGitBlameViewSha" })
			api.nvim_buf_set_extmark(buf, NS, i - 1, cols.author[1], { end_col = cols.author[2], hl_group = "BeastGitBlameViewAuthor" })
			api.nvim_buf_set_extmark(buf, NS, i - 1, cols.date[1], { end_col = cols.date[2], hl_group = "BeastGitBlameViewDate" })
		end
	end
end

-- =========================================================================
-- BlameView instance
-- =========================================================================

---@param self Beast.Git.BlameView
---@param blame table<integer, Beast.Git.BlameInfo>
local function fill_buffer(self, blame)
	self.blame = blame
	local total = api.nvim_buf_line_count(self.source_buf)
	local body, hl_cols, width = render(blame, total)
	vim.bo[self.buf].modifiable = true
	api.nvim_buf_set_lines(self.buf, 0, -1, false, body)
	vim.bo[self.buf].modifiable = false
	paint_hls(self.buf, hl_cols)
	if api.nvim_win_is_valid(self.win) then
		api.nvim_win_set_width(self.win, width)
	end
end

---@param self Beast.Git.BlameView
local function fetch_and_fill(self)
	local repo = require("beast.libs.git.repo")
	repo.resolve(self.source_buf, function(ctx)
		if not ctx then
			vim.notify("beast.libs.git.blame_view: not in a git repo", vim.log.levels.WARN)
			self:close()
			return
		end
		local modified = vim.bo[self.source_buf].modified
		local contents = modified and self.revision == nil and api.nvim_buf_get_lines(self.source_buf, 0, -1, false) or nil
		blame_mod.run(ctx, {
			revision = self.revision,
			contents = contents,
		}, function(blame, _)
			if not blame then
				vim.notify("beast.libs.git.blame_view: blame failed", vim.log.levels.WARN)
				self:close()
				return
			end
			if not api.nvim_buf_is_valid(self.buf) or not api.nvim_win_is_valid(self.win) then
				return
			end
			fill_buffer(self, blame)
		end)
	end)
end

---@param self Beast.Git.BlameView
local function get_sha_under_cursor(self)
	local lnum = api.nvim_win_get_cursor(self.win)[1]
	local info = self.blame and self.blame[lnum]
	return info and info.commit.sha or nil
end

---@param self Beast.Git.BlameView
local function show_commit(self)
	local sha = get_sha_under_cursor(self)
	if not sha or sha == blame_mod._NOT_COMMITTED_SHA then
		return
	end
	local repo = require("beast.libs.git.repo")
	repo.resolve(self.source_buf, function(ctx)
		if not ctx then
			return
		end
		vim.system({ "git", "-C", ctx.toplevel, "show", "--stat", "--patch", sha }, { text = true }, function(result)
			vim.schedule(function()
				if result.code ~= 0 then
					vim.notify("git show failed: " .. (result.stderr or ""), vim.log.levels.WARN)
					return
				end
				local lines = vim.split(result.stdout or "", "\n", { plain = true })
				local buf = api.nvim_create_buf(false, true)
				api.nvim_buf_set_lines(buf, 0, -1, false, lines)
				vim.bo[buf].filetype = "git"
				vim.bo[buf].modifiable = false
				local height = math.min(#lines, math.floor(vim.o.lines * 0.7))
				local width = math.min(120, math.floor(vim.o.columns * 0.8))
				local win = api.nvim_open_win(buf, true, {
					relative = "editor",
					row = math.floor((vim.o.lines - height) / 2),
					col = math.floor((vim.o.columns - width) / 2),
					width = width,
					height = height,
					border = "rounded",
					title = " " .. sha:sub(1, 8) .. " ",
					title_pos = "center",
				})
				vim.keymap.set("n", "q", function()
					if api.nvim_win_is_valid(win) then
						api.nvim_win_close(win, true)
					end
				end, { buffer = buf, nowait = true })
				vim.keymap.set("n", "<Esc>", function()
					if api.nvim_win_is_valid(win) then
						api.nvim_win_close(win, true)
					end
				end, { buffer = buf, nowait = true })
			end)
		end)
	end)
end

---@param self Beast.Git.BlameView
local function reblame_parent(self)
	local sha = get_sha_under_cursor(self)
	if not sha or sha == blame_mod._NOT_COMMITTED_SHA then
		return
	end
	self.revision = sha .. "^"
	fetch_and_fill(self)
end

---@param self Beast.Git.BlameView
local function reset_revision(self)
	self.revision = nil
	fetch_and_fill(self)
end

---@param self Beast.Git.BlameView
local function setup_keymaps(self)
	local opts = { buffer = self.buf, nowait = true, silent = true }
	vim.keymap.set("n", "<CR>", function()
		show_commit(self)
	end, opts)
	vim.keymap.set("n", "r", function()
		reblame_parent(self)
	end, opts)
	vim.keymap.set("n", "R", function()
		reset_revision(self)
	end, opts)
	vim.keymap.set("n", "q", function()
		self:close()
	end, opts)
	vim.keymap.set("n", "<Esc>", function()
		self:close()
	end, opts)
end

---@param self Beast.Git.BlameView
local function setup_lifecycle(self)
	self.augroup = api.nvim_create_augroup("BeastGitBlameView_" .. self.buf, { clear = true })
	-- Close when either window goes away or the source buffer is wiped.
	api.nvim_create_autocmd("WinClosed", {
		group = self.augroup,
		callback = function(args)
			local closed = tonumber(args.match)
			if closed == self.source_win or closed == self.win then
				vim.schedule(function()
					self:close()
				end)
			end
		end,
	})
	api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
		group = self.augroup,
		buffer = self.source_buf,
		callback = function()
			vim.schedule(function()
				self:close()
			end)
		end,
	})
end

function BlameView:close()
	if self.augroup then
		pcall(api.nvim_del_augroup_by_id, self.augroup)
		self.augroup = nil
	end
	if self.source_win and api.nvim_win_is_valid(self.source_win) then
		vim.wo[self.source_win].scrollbind = self.source_scrollbind_prev or false
	end
	-- Defer to base close (clears buf/win).
	View.close(self)
	if current == self then
		current = nil
	end
end

---@param source_win integer
---@param opts? { revision?: string }
function M.open(source_win, opts)
	opts = opts or {}
	-- Singleton: close any existing view first.
	if current then
		current:close()
	end

	if not api.nvim_win_is_valid(source_win) then
		return
	end
	local source_buf = api.nvim_win_get_buf(source_win)
	if not api.nvim_buf_is_valid(source_buf) then
		return
	end

	local git = require("beast.libs.git")
	if not git._get_state(source_buf) then
		vim.notify("beast.libs.git.blame_view: buffer not attached", vim.log.levels.WARN)
		return
	end

	-- Create the blame buffer and open a left-side vertical split for it.
	local blame_buf = api.nvim_create_buf(false, true)
	vim.bo[blame_buf].buftype = "nofile"
	vim.bo[blame_buf].bufhidden = "wipe"
	vim.bo[blame_buf].swapfile = false
	vim.bo[blame_buf].filetype = "BeastGitBlameView"
	vim.bo[blame_buf].modifiable = false

	api.nvim_set_current_win(source_win)
	vim.cmd("leftabove vsplit")
	local blame_win = api.nvim_get_current_win()
	api.nvim_win_set_buf(blame_win, blame_buf)
	vim.wo[blame_win].wrap = false
	vim.wo[blame_win].number = false
	vim.wo[blame_win].relativenumber = false
	vim.wo[blame_win].signcolumn = "no"
	vim.wo[blame_win].foldcolumn = "0"
	vim.wo[blame_win].cursorline = true
	vim.wo[blame_win].winfixwidth = true

	-- Scroll-bind both windows. Capture the source's prior value so close
	-- restores it (a user might have had scrollbind set for some other reason).
	local self = BlameView:new(blame_buf, blame_win)
	self.source_buf = source_buf
	self.source_win = source_win
	self.revision = opts.revision
	self.source_scrollbind_prev = vim.wo[source_win].scrollbind
	vim.wo[source_win].scrollbind = true
	vim.wo[blame_win].scrollbind = true
	-- Sync scroll position immediately.
	api.nvim_set_current_win(source_win)
	vim.cmd("syncbind")

	setup_keymaps(self)
	setup_lifecycle(self)

	current = self
	fetch_and_fill(self)
end

---@return Beast.Git.BlameView?
function M._current()
	return current
end

return M
