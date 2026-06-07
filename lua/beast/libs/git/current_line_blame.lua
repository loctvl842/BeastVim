-- Current-line git blame as virt_text.
--
-- One extmark per buffer in namespace `beast_git_blame`, id = 1, replaced
-- on every (debounced) cursor move. Skipped in insert mode, on folded
-- lines, on untracked buffers, and on lines that don't exist in the
-- attached state (race during detach).
--
-- Cursor-race guard: we capture the cursor lnum before the async blame
-- call and recurse if it moved during the round-trip. Without this, a
-- fast `j`-hold paints stale blame for the wrong line.

local api = vim.api

local blame_mod = require("beast.libs.git.blame")
local config = require("beast.libs.git.config")
local repo = require("beast.libs.git.repo")

local M = {}

local NS = api.nvim_create_namespace("beast_git_blame")
local EXTMARK_ID = 1
local AUGROUP = "BeastGitBlame"

---@type table<integer, Beast.Util.Debouncer>
local debouncers = {}
local augroup_id ---@type integer?

-- =========================================================================
-- Formatting
-- =========================================================================

---@param secs integer Seconds in the past
---@return string
local function relative_time(secs)
	local diff = os.time() - secs
	if diff < 0 then
		diff = 0
	end
	if diff < 60 then
		return "just now"
	end
	local minutes = math.floor(diff / 60)
	if minutes < 60 then
		return minutes .. (minutes == 1 and " minute ago" or " minutes ago")
	end
	local hours = math.floor(minutes / 60)
	if hours < 24 then
		return hours .. (hours == 1 and " hour ago" or " hours ago")
	end
	local days = math.floor(hours / 24)
	if days < 7 then
		return days .. (days == 1 and " day ago" or " days ago")
	end
	if days < 30 then
		local weeks = math.floor(days / 7)
		return weeks .. (weeks == 1 and " week ago" or " weeks ago")
	end
	local months = math.floor(days / 30)
	if months < 12 then
		return months .. (months == 1 and " month ago" or " months ago")
	end
	local years = math.floor(days / 365)
	return years .. (years == 1 and " year ago" or " years ago")
end

---@param ts integer Unix seconds
---@param spec string Strftime format, or "%R" for relative time
---@return string
local function format_time(ts, spec)
	if spec == "%R" then
		return relative_time(ts)
	end
	return os.date(spec, ts) --[[@as string]]
end

---@param s string
---@param max integer 0 disables
---@return string
local function truncate(s, max)
	if max <= 0 or vim.fn.strdisplaywidth(s) <= max then
		return s
	end
	return vim.fn.strcharpart(s, 0, max - 1) .. "…"
end

---@param fmt string
---@param info Beast.Git.BlameInfo
---@param username string
---@return string
local function expand(fmt, info, username)
	local commit = info.commit
	local author = commit.author
	if author == username and username ~= "" then
		author = "You"
	end
	local max_summary = config.blame.max_summary_length or 0
	-- Order matters: handle the `<author_time:fmt>` form before the bare
	-- `<author_time>` substitution, else `:%R` would be left orphaned.
	local out = fmt:gsub("<([%w_]+):([^>]+)>", function(key, spec)
		if key == "author_time" then
			return format_time(commit.author_time, spec)
		elseif key == "committer_time" then
			return format_time(commit.committer_time, spec)
		end
		return "<" .. key .. ":" .. spec .. ">"
	end)
	out = out:gsub("<([%w_]+)>", function(key)
		if key == "author" then
			return author
		elseif key == "author_mail" then
			return commit.author_mail or ""
		elseif key == "author_time" then
			return tostring(commit.author_time or "")
		elseif key == "committer" then
			return commit.committer or ""
		elseif key == "summary" then
			return truncate(commit.summary or "", max_summary)
		elseif key == "abbrev_sha" then
			return commit.abbrev_sha or ""
		elseif key == "sha" then
			return commit.sha or ""
		end
		return "<" .. key .. ">"
	end)
	return out
end

-- =========================================================================
-- Paint / clear
-- =========================================================================

---@param buf integer
function M.reset(buf)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	api.nvim_buf_del_extmark(buf, NS, EXTMARK_ID)
	vim.b[buf].beast_git_blame_line = nil
	vim.b[buf].beast_git_blame_line_dict = nil
end

---@param winid integer
---@return integer
local function visible_text_width(winid)
	local info = vim.fn.getwininfo(winid)[1]
	local textoff = info and info.textoff or 0
	return api.nvim_win_get_width(winid) - textoff
end

---@param buf integer
---@param lnum integer 1-based
---@return integer
local function line_width(buf, lnum)
	local line = api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
	return api.nvim_strwidth(line)
end

---@param buf integer
---@param winid integer
---@param lnum integer
---@param text string
local function paint(buf, winid, lnum, text)
	local pos = config.blame.virt_text_pos or "eol"
	if pos == "right_align" then
		local avail = visible_text_width(winid) - line_width(buf, lnum)
		if api.nvim_strwidth(text) > avail then
			pos = "eol"
		end
	end
	api.nvim_buf_set_extmark(buf, NS, lnum - 1, 0, {
		id = EXTMARK_ID,
		virt_text = { { text, "BeastGitCurrentLineBlame" } },
		virt_text_pos = pos,
		hl_mode = "combine",
		priority = 1,
	})
end

-- =========================================================================
-- Update pipeline
-- =========================================================================

---@param buf integer
---@return boolean
local function skip_buffer(buf)
	if not api.nvim_buf_is_valid(buf) then
		return true
	end
	if api.nvim_get_mode().mode:sub(1, 1) == "i" then
		return true
	end
	local winid = api.nvim_get_current_win()
	if api.nvim_win_get_buf(winid) ~= buf then
		return true
	end
	return false
end

---@param buf integer
---@param winid integer
---@param lnum integer
---@return boolean
local function fold_closed(winid, lnum)
	return api.nvim_win_call(winid, function()
		return vim.fn.foldclosed(lnum) ~= -1
	end) --[[@as boolean]]
end

---@param buf integer
local function update(buf)
	if skip_buffer(buf) then
		return
	end
	local git = require("beast.libs.git")
	local st = git._get_state(buf)
	if not st then
		return
	end
	-- Untracked: we don't paint NC blame on every cursor move — it'd
	-- just clutter every line of every new file.
	if not st.path_data then
		return
	end
	local winid = api.nvim_get_current_win()
	local start_lnum = api.nvim_win_get_cursor(winid)[1]
	if fold_closed(winid, start_lnum) then
		return
	end

	local contents = vim.bo[buf].modified and api.nvim_buf_get_lines(buf, 0, -1, false) or nil

	blame_mod.run(st.ctx, {
		lnum = start_lnum,
		contents = contents,
		ignore_whitespace = config.blame.ignore_whitespace,
	}, function(blame, _)
		if not blame or not api.nvim_buf_is_valid(buf) then
			return
		end
		if not api.nvim_win_is_valid(winid) or api.nvim_win_get_buf(winid) ~= buf then
			return
		end
		local cur_lnum = api.nvim_win_get_cursor(winid)[1]
		if cur_lnum ~= start_lnum then
			-- Cursor moved during the round-trip; reblame for the new line.
			return update(buf)
		end
		local info = blame[start_lnum]
		if not info then
			return
		end
		repo.get_username(function(username)
			if not api.nvim_buf_is_valid(buf) then
				return
			end
			if not api.nvim_win_is_valid(winid) or api.nvim_win_get_buf(winid) ~= buf then
				return
			end
			if api.nvim_win_get_cursor(winid)[1] ~= start_lnum then
				return update(buf)
			end
			local nc = info.commit.sha == blame_mod._NOT_COMMITTED_SHA
			local fmt = nc and config.blame.formatter_nc or config.blame.formatter
			local text = expand(fmt, info, username)
			vim.b[buf].beast_git_blame_line = text
			vim.b[buf].beast_git_blame_line_dict = info
			paint(buf, winid, start_lnum, text)
		end)
	end)
end

---@param buf integer
local function ensure_debouncer(buf)
	local d = debouncers[buf]
	if d then
		return d
	end
	d = Util.debounce(config.blame.delay_ms or 500, function()
		update(buf)
	end)
	debouncers[buf] = d
	return d
end

---@param buf integer
local function schedule_update(buf)
	ensure_debouncer(buf):call()
end

---@param buf integer
local function close_debouncer(buf)
	local d = debouncers[buf]
	if d then
		d:close()
		debouncers[buf] = nil
	end
end

-- =========================================================================
-- Lifecycle
-- =========================================================================

function M.setup()
	M.teardown()
	if not config.blame.enabled then
		return
	end
	augroup_id = api.nvim_create_augroup(AUGROUP, { clear = true })

	local update_events = { "BufEnter", "CursorMoved", "CursorMovedI", "WinResized" }
	if config.blame.use_focus then
		update_events[#update_events + 1] = "FocusGained"
	end

	api.nvim_create_autocmd(update_events, {
		group = augroup_id,
		callback = function(args)
			M.reset(args.buf)
			schedule_update(args.buf)
		end,
	})

	api.nvim_create_autocmd({ "InsertEnter", "BufLeave" }, {
		group = augroup_id,
		callback = function(args)
			M.reset(args.buf)
		end,
	})

	api.nvim_create_autocmd("OptionSet", {
		group = augroup_id,
		pattern = { "fileformat", "bomb", "eol" },
		callback = function(args)
			M.reset(args.buf)
		end,
	})

	-- Kick off for the current buffer so the user sees something
	-- immediately after `setup` / a toggle-on.
	schedule_update(api.nvim_get_current_buf())
end

function M.teardown()
	if augroup_id then
		api.nvim_del_augroup_by_id(augroup_id)
		augroup_id = nil
	end
	for buf in pairs(debouncers) do
		close_debouncer(buf)
	end
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(buf) then
			M.reset(buf)
		end
	end
end

--- Called from git.detach to clean up per-buffer state when the buffer
--- itself goes away (separate from teardown, which is global).
---@param buf integer
function M.detach(buf)
	M.reset(buf)
	close_debouncer(buf)
end

M._namespace = NS
M._expand = expand
M._relative_time = relative_time

return M
