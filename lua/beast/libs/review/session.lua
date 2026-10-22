-- One review of one proposal against one buffer. Owns hunk decisions, the
-- save-on-finish rule, and the per-buffer queue. Knows nothing about
-- transports: callers hand it contents and a completion callback.

local api = vim.api

local config = require("beast.libs.review.config")
local hunks = require("beast.libs.review.hunks")
local render = require("beast.libs.review.render")

local M = {}

---@alias Beast.Review.Outcome "saved"|"rejected"|"cancelled"|"error"

---@class Beast.Review.Stats
---@field accepted integer
---@field rejected integer
---@field user_edits boolean  buffer had unsaved edits that were saved along with the review
---@field message? string     failure detail when outcome is "error"

---@class Beast.Review.Item
---@field hunk Beast.Review.Hunk
---@field marks Beast.Review.Marks
---@field decided boolean

---@class Beast.Review.Session
---@field buf integer
---@field items Beast.Review.Item[]
---@field on_done fun(outcome: Beast.Review.Outcome, stats: Beast.Review.Stats)
---@field accepted integer
---@field rejected integer
---@field was_empty boolean   buffer was a single blank line (new/empty file)
---@field user_edits boolean
---@field finished boolean
local Session = {}
Session.__index = Session

---@type table<integer, Beast.Review.Session>
local active = {}
---@class Beast.Review.Request
---@field text string
---@field on_done fun(outcome: Beast.Review.Outcome, stats: Beast.Review.Stats)
---@field session? Beast.Review.Session  set once the request is being reviewed

---@type table<integer, Beast.Review.Request[]>
local queued = {}

local function title()
	return require("beast.libs.review").meta.name
end

---@param msg string
---@param level? integer
local function notify(msg, level)
	vim.notify(msg, level or vim.log.levels.INFO, { title = title() })
end

---@param buf integer
---@return string
local function short_name(buf)
	return vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
end

--- Make sure `buf` is visible; focus its window when configured.
---@param buf integer
---@return integer? win
local function show(buf)
	local win = vim.fn.bufwinid(buf)
	if win == -1 then
		win = require("beast.libs.view").win.find_normal()
		if win then
			api.nvim_win_set_buf(win, buf)
		end
	end
	if win and config.focus then
		api.nvim_set_current_win(win)
	end
	return win
end

---@param self Beast.Review.Session
---@return integer
local function cursor_row(self)
	local win = vim.fn.bufwinid(self.buf)
	return win == -1 and 0 or api.nvim_win_get_cursor(win)[1] - 1
end

---@param self Beast.Review.Session
---@return Beast.Review.Item[]
local function pending(self)
	return vim.tbl_filter(function(item)
		return not item.decided
	end, self.items)
end

--- Pending hunk whose rows are closest to the cursor.
---@param self Beast.Review.Session
---@return Beast.Review.Item?
local function nearest(self)
	local cur, best, best_dist = cursor_row(self), nil, math.huge
	for _, item in ipairs(pending(self)) do
		local row, count = render.locate(self.buf, item.marks)
		if row then
			local last = row + math.max(count, 1) - 1
			local dist = cur < row and row - cur or (cur > last and cur - last or 0)
			if dist < best_dist then
				best, best_dist = item, dist
			end
		end
	end
	-- Hunks whose lines the user deleted can't be located; still let them be
	-- decided (accept degrades to a skip) so the review can finish.
	return best or pending(self)[1]
end

---@param self Beast.Review.Session
---@param item Beast.Review.Item
local function goto_item(self, item)
	local win = vim.fn.bufwinid(self.buf)
	local row = render.locate(self.buf, item.marks)
	if win == -1 or not row then
		return
	end
	row = math.min(row, api.nvim_buf_line_count(self.buf) - 1)
	api.nvim_win_set_cursor(win, { row + 1, 0 })
	api.nvim_win_call(win, function()
		vim.cmd("normal! zz")
	end)
end

---@param self Beast.Review.Session
---@param dir 1|-1
function Session:step(dir)
	local cur, list = cursor_row(self), {}
	for _, item in ipairs(pending(self)) do
		local row = render.locate(self.buf, item.marks)
		if row then
			list[#list + 1] = { item = item, row = row }
		end
	end
	if #list == 0 then
		return
	end
	table.sort(list, function(a, b)
		return a.row < b.row
	end)
	local pick
	if dir == 1 then
		pick = vim.iter(list):find(function(e)
			return e.row > cur
		end) or list[1]
	else
		pick = vim.iter(list):rfind(function(e)
			return e.row < cur
		end) or list[#list]
	end
	goto_item(self, pick.item)
end

---@param on_done fun(outcome: Beast.Review.Outcome, stats: Beast.Review.Stats)
---@param outcome Beast.Review.Outcome
---@param stats Beast.Review.Stats
local function complete(on_done, outcome, stats)
	-- A throwing callback must not strand the queue behind it.
	local ok, err = pcall(on_done, outcome, stats)
	if not ok then
		notify("on_done callback failed: " .. tostring(err), vim.log.levels.ERROR)
	end
end

--- Start the next queued proposal for `buf`. A proposal that completes
--- without a session (identical content, unloaded buffer) drains onward.
---@param buf integer
local function drain(buf)
	local q = queued[buf]
	local nxt = q and table.remove(q, 1)
	if q and #q == 0 then
		queued[buf] = nil
	end
	if not nxt then
		return
	end
	if api.nvim_buf_is_loaded(buf) then
		M._run(buf, nxt)
	else
		-- Buffer was closed: nothing to review against.
		complete(nxt.on_done, "rejected", { accepted = 0, rejected = 0, user_edits = false })
		drain(buf)
	end
end

---@param self Beast.Review.Session
---@return boolean ok, string? err
local function save(self)
	local name = api.nvim_buf_get_name(self.buf)
	vim.fn.mkdir(vim.fn.fnamemodify(name, ":h"), "p")
	local ok, err = pcall(api.nvim_buf_call, self.buf, function()
		vim.cmd("silent write")
	end)
	return ok, ok and nil or tostring(err)
end

---@param self Beast.Review.Session
---@param outcome Beast.Review.Outcome
---@param unloading? boolean  buffer is going away: touch nothing in it
local function finish(self, outcome, unloading)
	if self.finished then
		return
	end
	self.finished = true
	active[self.buf] = nil
	pcall(api.nvim_del_augroup_by_name, "beast_review_" .. self.buf)

	if not unloading then
		render.clear_all(self.buf)
	end

	local stats = { accepted = self.accepted, rejected = self.rejected, user_edits = self.user_edits }
	local name = short_name(self.buf)

	if outcome == "saved" then
		local ok, err = save(self)
		if ok then
			local extra = self.user_edits and " (includes your unsaved edits)" or ""
			local rejected = self.rejected > 0 and (", " .. self.rejected .. " rejected") or ""
			notify(("saved %s - %d accepted%s%s"):format(name, self.accepted, rejected, extra))
		else
			outcome, stats.message = "error", err
			notify(("could not save %s: %s"):format(name, err), vim.log.levels.ERROR)
		end
	elseif outcome == "rejected" then
		notify("rejected " .. name)
	elseif outcome == "cancelled" then
		notify(("review of %s cancelled by Claude Code"):format(name), vim.log.levels.WARN)
	end

	complete(self.on_done, outcome, stats)
	local buf = self.buf
	vim.schedule(function()
		drain(buf)
	end)
end

---@param self Beast.Review.Session
local function maybe_finish(self)
	if #pending(self) == 0 then
		finish(self, self.accepted > 0 and "saved" or "rejected")
	end
end

---@param item Beast.Review.Item
---@param accept boolean
function Session:decide(item, accept)
	if item.decided or self.finished then
		return
	end
	item.decided = true
	local row, count = render.locate(self.buf, item.marks)
	render.clear(self.buf, item.marks)

	if accept and not row then
		notify("a hunk moved out of reach and was skipped", vim.log.levels.WARN)
		accept = false
	end
	if accept then
		-- An empty buffer is one blank line; the proposal replaces it.
		count = self.was_empty and 1 or count
		api.nvim_buf_set_lines(self.buf, row, row + count, false, item.hunk.new)
		self.accepted = self.accepted + 1
	else
		self.rejected = self.rejected + 1
	end
end

---@param accept boolean
function Session:decide_nearest(accept)
	local item = nearest(self)
	if not item then
		return
	end
	self:decide(item, accept)
	maybe_finish(self)
	local nxt = not self.finished and nearest(self)
	if nxt then
		goto_item(self, nxt)
	end
end

---@param accept boolean
function Session:decide_all(accept)
	for _, item in ipairs(self.items) do
		self:decide(item, accept)
	end
	maybe_finish(self)
end

--- Abort without writing anything (Claude cancelled or disconnected).
function Session:cancel()
	for _, item in ipairs(self.items) do
		item.decided = true
	end
	finish(self, "cancelled")
end

---@param buf integer
---@param req Beast.Review.Request
local function start(buf, req)
	local text, on_done = req.text, req.on_done
	local proposal = hunks.split(text)
	local current = api.nvim_buf_get_lines(buf, 0, -1, false)
	local was_empty = #current == 1 and current[1] == ""
	if was_empty then
		current = {}
	end

	local list = hunks.compute(current, proposal.lines)
	local user_edits = vim.bo[buf].modified
	if #list == 0 then
		complete(on_done, "saved", { accepted = 0, rejected = 0, user_edits = false })
		drain(buf)
		return
	end

	---@type Beast.Review.Session
	local self = setmetatable({
		buf = buf,
		items = {},
		on_done = on_done,
		accepted = 0,
		rejected = 0,
		was_empty = was_empty,
		user_edits = user_edits,
		finished = false,
	}, Session)
	active[buf] = self
	req.session = self

	show(buf)
	for i, h in ipairs(list) do
		self.items[i] = { hunk = h, marks = render.paint(buf, h, i, #list), decided = false }
	end

	-- Closing the buffer mid-review counts as reject-all.
	api.nvim_create_autocmd("BufUnload", {
		group = api.nvim_create_augroup("beast_review_" .. buf, { clear = true }),
		buffer = buf,
		once = true,
		callback = function()
			for _, item in ipairs(self.items) do
				if not item.decided then
					item.decided = true
					self.rejected = self.rejected + 1
				end
			end
			finish(self, "rejected", true)
		end,
	})

	notify(("Claude proposes %d change%s in %s"):format(#list, #list == 1 and "" or "s", short_name(buf)))
	goto_item(self, self.items[1])
end

---@param buf integer
---@param req Beast.Review.Request
function M._run(buf, req)
	if active[buf] then
		queued[buf] = queued[buf] or {}
		table.insert(queued[buf], req)
		return
	end
	start(buf, req)
end

--- Start reviewing `text` against `buf`, or queue it behind a review that is
--- already pending on the same buffer. Returns a function that abandons this
--- request (pending or queued); a no-op once it has completed.
---@param buf integer
---@param text string
---@param on_done fun(outcome: Beast.Review.Outcome, stats: Beast.Review.Stats)
---@return fun() cancel
function M.submit(buf, text, on_done)
	---@type Beast.Review.Request
	local req = { text = text, on_done = on_done }
	M._run(buf, req)
	return function()
		if req.session then
			req.session:cancel() -- no-op if already finished
			return
		end
		-- Identity match: vim.fn.index would round-trip the table through Vimscript.
		for i, queued_req in ipairs(queued[buf] or {}) do
			if queued_req == req then
				table.remove(queued[buf], i)
				if #queued[buf] == 0 then
					queued[buf] = nil
				end
				complete(on_done, "cancelled", { accepted = 0, rejected = 0, user_edits = false })
				return
			end
		end
	end
end

---@param buf integer
---@return Beast.Review.Session?
function M.get(buf)
	return active[buf]
end

return M
