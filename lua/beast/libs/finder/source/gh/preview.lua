--- Preview pane for the GitHub sources: what the list already knows is drawn at once,
--- description and conversation fill in when `gh pr|issue view` answers.
local View = require("beast.libs.view")
local api = require("beast.libs.finder.source.gh.api")
local format = require("beast.libs.finder.format")

---@class Beast.Finder.Gh.Preview
local M = {}

local NS = vim.api.nvim_create_namespace("beast-finder-gh-preview")
local LABEL_WIDTH = 11
local RULE = ("─"):rep(48)

---@class Beast.Finder.Gh.Span
---@field row integer 0-based
---@field col integer 0-based byte column
---@field end_col integer
---@field hl string

---@class Beast.Finder.Gh.PreviewState
---@field key? string url of the item shown (late answers for other items are dropped)
---@field proc? Beast.Finder.Gh.Handle detail fetch in flight
---@field req? table identity of the latest fetch; a callback from any other one is stale
---@field cache table<string, Beast.Finder.Gh.Detail>
---@type table<Beast.Finder.PreviewView, Beast.Finder.Gh.PreviewState>
local states = setmetatable({}, { __mode = "k" })

-- ---------------------------------------------------------------------------
-- Pure content
-- ---------------------------------------------------------------------------

--- Seconds since the epoch for an ISO-8601 UTC timestamp ("2026-08-08T10:29:43Z").
---@param iso string
---@return integer?
local function epoch(iso)
	local y, mo, d, h, mi, s = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	y, mo, d = tonumber(y), tonumber(mo), tonumber(d)
	-- days from civil (Howard Hinnant), so the result does not depend on the local timezone
	y = mo <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (mo + (mo > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
end

--- "2 weeks ago" style age of a timestamp.
---@param iso? string
---@param now? integer
---@return string
function M.reltime(iso, now)
	local t = iso and epoch(iso)
	if not t then
		return ""
	end
	local secs = math.max(0, (now or os.time()) - t)
	local units = { { 31536000, "year" }, { 2592000, "month" }, { 604800, "week" }, { 86400, "day" }, { 3600, "hour" }, { 60, "minute" } }
	for _, u in ipairs(units) do
		local n = math.floor(secs / u[1])
		if n >= 1 then
			return ("%d %s%s ago"):format(n, u[2], n == 1 and "" or "s")
		end
	end
	return "just now"
end

local STATUS_WORD = { open = "Open", draft = "Draft", merged = "Merged", closed = "Closed", not_planned = "Closed (not planned)" }
local MERGEABLE = { MERGEABLE = "✓", CONFLICTING = "✗ conflicts" }

---@param checks Beast.Finder.Gh.Checks
---@return string
local function checks_text(checks)
	local parts = {}
	if checks.passed > 0 then
		parts[#parts + 1] = "✓ " .. checks.passed
	end
	if checks.failed > 0 then
		parts[#parts + 1] = "✗ " .. checks.failed
	end
	if checks.pending > 0 then
		parts[#parts + 1] = "● " .. checks.pending
	end
	return table.concat(parts, "  ")
end

---@param text string
---@return string[]
local function split_lines(text)
	local out = {}
	for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = line
	end
	while #out > 0 and out[#out] == "" do
		out[#out] = nil
	end
	return out
end

--- Everything the pane shows, as lines plus highlight spans. `detail` is nil until the fetch answers;
--- `failure` replaces the "Loading" line when it did not.
---@param item Beast.Finder.Gh.Item
---@param detail? Beast.Finder.Gh.Detail
---@param failure? string
---@param now? integer
---@return string[] lines
---@return Beast.Finder.Gh.Span[] spans
function M.build(item, detail, failure, now)
	local lines, spans = {}, {}

	---@param text string
	---@param hl? string
	local function add(text, hl)
		lines[#lines + 1] = text
		if hl then
			spans[#spans + 1] = { row = #lines - 1, col = 0, end_col = #text, hl = hl }
		end
	end

	--- "Label:     value", label dimmed, optional highlight for the value.
	---@param label string
	---@param value string
	---@param hl? string
	local function field(label, value, hl)
		local head = ("%-" .. LABEL_WIDTH .. "s"):format(label .. ":")
		lines[#lines + 1] = head .. value
		local row = #lines - 1
		spans[#spans + 1] = { row = row, col = 0, end_col = #head, hl = "BeastFinderGhNumber" }
		if hl then
			spans[#spans + 1] = { row = row, col = #head, end_col = #head + #value, hl = hl }
		end
	end

	add(("%s  #%d"):format(item.title, item.number), "BeastFinderPreviewTitle")
	add("")

	local icon, icon_hl = format.gh_state(item)
	local status = icon .. " " .. STATUS_WORD[item.state]
	if item.kind == "pr" and detail and detail.base then
		status = ("%s   %s <- %s"):format(status, detail.base, detail.head)
	end
	field("Status", status)
	-- colour just the icon + word, like the list row
	spans[#spans + 1] = { row = #lines - 1, col = LABEL_WIDTH, end_col = LABEL_WIDTH + #icon + 1 + #STATUS_WORD[item.state], hl = icon_hl }
	field("Repo", item.repo)
	if item.author then
		field("Author", item.author, "BeastFinderGhAuthor")
	end
	if #item.labels > 0 then
		local names = {}
		for _, label in ipairs(item.labels) do
			names[#names + 1] = label.name
		end
		field("Labels", table.concat(names, ", "))
	end
	field("Created", M.reltime(item.created, now))
	field("Updated", M.reltime(item.updated, now))
	if detail and detail.merged then
		field("Merged", M.reltime(detail.merged, now))
	elseif detail and detail.closed then
		field("Closed", M.reltime(detail.closed, now))
	end
	if item.kind == "pr" and detail then
		local checks = checks_text(detail.checks)
		if checks ~= "" then
			field("Checks", checks)
		end
		if MERGEABLE[detail.mergeable or ""] then
			field("Mergeable", MERGEABLE[detail.mergeable])
		end
		field("Changes", ("%d files  +%d -%d"):format(detail.files, detail.additions, detail.deletions))
	elseif item.kind == "issue" then
		field("Comments", tostring(item.comments))
	end

	add("")
	add(RULE, "BeastFinderGhNumber")
	add("")

	if failure then
		add("Could not load details: " .. failure, "BeastFinderGhError")
	elseif not detail then
		add("Loading...", "BeastFinderGhMessage")
	else
		local body = split_lines(detail.body or "")
		if #body == 0 then
			add("(no description)", "BeastFinderGhMessage")
		end
		vim.list_extend(lines, body)
		if #detail.conversation > 0 then
			add("")
			add("## Conversation")
			for _, entry in ipairs(detail.conversation) do
				add("")
				local who = "@" .. (entry.author or "ghost")
				local head = who .. (entry.state and ("  " .. entry.state:lower():gsub("_", " ")) or "") .. "  " .. M.reltime(entry.created, now)
				add(head)
				spans[#spans + 1] = { row = #lines - 1, col = 0, end_col = #who, hl = "BeastFinderGhAuthor" }
				-- a blank line keeps a body that starts with `---` or `===` from turning the head into a heading
				add("")
				vim.list_extend(lines, split_lines(entry.body or ""))
			end
		end
	end

	return lines, spans
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

---@param view Beast.Finder.PreviewView
---@return Beast.Finder.Gh.PreviewState
local function state_of(view)
	if not states[view] then
		states[view] = { cache = {} }
	end
	return states[view]
end

---@param view Beast.Finder.PreviewView
---@param item Beast.Finder.Gh.Item
---@param detail? Beast.Finder.Gh.Detail
---@param failure? string
local function draw(view, item, detail, failure)
	-- stylua: ignore
	if not view:is_valid() then return end
	local lines, spans = M.build(item, detail, failure)

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false
	if vim.bo[view.buf].filetype ~= "markdown" then
		vim.bo[view.buf].filetype = "markdown"
	end

	vim.api.nvim_buf_clear_namespace(view.buf, NS, 0, -1)
	for _, span in ipairs(spans) do
		vim.api.nvim_buf_set_extmark(view.buf, NS, span.row, span.col, { end_col = span.end_col, hl_group = span.hl, priority = 200 })
	end
end

---@param view Beast.Finder.PreviewView
local function clear(view)
	local st = state_of(view)
	st.key = nil
	st.req = nil
	if st.proc then
		st.proc.kill()
		st.proc = nil
	end
	-- stylua: ignore
	if not view:is_valid() then return end
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, {})
	vim.bo[view.buf].modifiable = false
	pcall(vim.api.nvim_win_set_config, view.win, { title = "", title_pos = "center" })
end

--- `source.preview` hook: draw `item` in the preview pane.
---@param view Beast.Finder.PreviewView
---@param item? Beast.Finder.Item nil when the list is empty
function M.show(view, item)
	-- stylua: ignore
	if not view:is_valid() then return end
	if not item or item.message then
		return clear(view)
	end
	---@cast item Beast.Finder.Gh.Item

	local st = state_of(view)
	-- stylua: ignore
	if st.key == item.url then return end
	st.key = item.url
	if st.proc then
		st.proc.kill()
		st.proc = nil
	end

	View.win.wo(view.win, "number", false)
	View.win.wo(view.win, "wrap", true)
	View.win.wo(view.win, "linebreak", true)
	pcall(vim.api.nvim_win_set_config, view.win, {
		title = (" %s #%d "):format(item.kind == "pr" and "PR" or "Issue", item.number),
		title_pos = "center",
	})

	local cached = st.cache[item.url]
	draw(view, item, cached)
	vim.api.nvim_win_set_cursor(view.win, { 1, 0 })
	-- stylua: ignore
	if cached then return end

	local req = {}
	st.req = req
	st.proc = api.detail(item, function(result)
		-- stylua: ignore
		if st.req ~= req or not view:is_valid() then return end
		st.proc = nil
		if result.error then
			draw(view, item, nil, result.error)
			return
		end
		st.cache[item.url] = result.detail
		draw(view, item, result.detail)
		pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
	end)
end

return M
