--- What a commit looks like in the preview pane and in the buffer Enter opens: its message, the files it
--- changed and their diffs. The commit's files come from `gh api` (one request per commit, kept for the
--- session), so the pane draws the header at once and the rest when the request answers.
local View = require("beast.libs.view")
local api = require("beast.libs.finder.source.gh.api")
local preview = require("beast.libs.finder.source.gh.preview")

---@class Beast.Finder.Gh.CommitPreview
local M = {}

--- Commits already fetched, by "repo@sha" (at most `MAX_CACHED`). A commit never changes, so nothing expires.
---@type table<string, Beast.Finder.Gh.CommitDetail>
local cache = {}
local cached = 0
local MAX_CACHED = 30
local MARK = "gh-commit:"

--- Forget the commits fetched so far (for tests: a commit never changes, so the cache is otherwise kept).
function M.reset()
	cache, cached = {}, 0
end

--- The repository a commit belongs to: its pull request's, else the directory of the local repository.
---@param item Beast.Finder.Item a commit item
---@return string
function M.repo(item)
	return item.pr and item.pr.repo or item.cwd
end

---@param item Beast.Finder.Item a commit item
---@return string
local function key(item)
	return M.repo(item) .. "@" .. item.sha
end

--- The commit's detail: from the cache at once (returns nil), else after a request (returns its handle).
---@param item Beast.Finder.Item a commit item (`sha`, and `pr` for a pull request's commit or `cwd` for a local one)
---@param cb fun(result: Beast.Finder.Gh.CommitDetailResult)
---@return Beast.Finder.Gh.Handle?
function M.detail(item, cb)
	local hit = cache[key(item)]
	if hit then
		cb({ detail = hit })
		return nil
	end
	local function answer(result)
		if result.detail then
			-- Patches can be large: when the cache is full it starts over instead of growing.
			if cached >= MAX_CACHED then
				cache, cached = {}, 0
			end
			cache[key(item)] = result.detail
			cached = cached + 1
		end
		cb(result)
	end
	if item.pr then
		return api.commit(item.pr, item.sha, answer)
	end
	return require("beast.libs.finder.source.git.log").show(item.cwd, item.sha, answer)
end

---@param file Beast.Finder.Gh.File
---@return string
local function file_line(file)
	local line = ("%-9s +%d -%d  %s"):format(file.status, file.additions, file.deletions, file.path)
	return file.previous and (line .. "  (was " .. file.previous .. ")") or line
end

--- The text of a commit: header, message, file list and each file's diff.
--- `detail` is nil while the request is running, `failure` the reason when it failed.
---@param item Beast.Finder.Item a commit item
---@param detail? Beast.Finder.Gh.CommitDetail
---@param failure? string
---@return string[]
function M.build(item, detail, failure)
	local lines = {
		item.sha,
		("%s  %s"):format(item.author, preview.reltime(item.date)),
		"",
	}
	for line in (item.body:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	while lines[#lines] == "" do
		lines[#lines] = nil
	end
	lines[#lines + 1] = ""
	if failure then
		lines[#lines + 1] = "Could not load the files: " .. failure
	elseif not detail then
		lines[#lines + 1] = "Loading the files..."
	elseif #detail.files == 0 then
		lines[#lines + 1] = "(this commit changes no files)"
	else
		lines[#lines + 1] = ("%d files changed%s"):format(#detail.files, detail.truncated and " (partial)" or "")
		for _, file in ipairs(detail.files) do
			lines[#lines + 1] = file_line(file)
		end
		for _, file in ipairs(detail.files) do
			lines[#lines + 1] = ""
			lines[#lines + 1] = "━━ " .. file.path
			if file.patch then
				vim.list_extend(lines, vim.split(file.patch, "\n", { plain = true }))
			else
				lines[#lines + 1] = "(diff too large or binary)"
			end
		end
	end
	return lines
end

---@class Beast.Finder.Gh.CommitPreviewState
---@field key? string commit shown (late answers for another one are dropped)
---@field proc? Beast.Finder.Gh.Handle
---@field req? table identity of the latest request
---@type table<Beast.Finder.PreviewView, Beast.Finder.Gh.CommitPreviewState>
local states = setmetatable({}, { __mode = "k" })

---@param view Beast.Finder.PreviewView
---@param item Beast.Finder.Item
---@param detail? Beast.Finder.Gh.CommitDetail
---@param failure? string
local function draw(view, item, detail, failure)
	-- stylua: ignore
	if not view:is_valid() then return end
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, M.build(item, detail, failure))
	vim.bo[view.buf].modifiable = false
	vim.bo[view.buf].filetype = "diff"
	-- The pane shows a commit, not a file of the working tree; the marker says which one.
	view.loaded_file = MARK .. key(item)
	pcall(vim.api.nvim_win_set_config, view.win, { title = (" %s  %s "):format(item.short, item.subject), title_pos = "center" })
end

--- `source.preview` hook: draw the commit `item` in the preview pane.
---@param view Beast.Finder.PreviewView
---@param item? Beast.Finder.Item nil when the list is empty
function M.show(view, item)
	-- stylua: ignore
	if not view:is_valid() then return end
	local state = states[view] or {}
	states[view] = state
	if not item or item.message then
		state.key, state.req = nil, nil
		if state.proc then
			state.proc.kill()
			state.proc = nil
		end
		return require("beast.libs.finder.ui.preview").clear(view)
	end
	-- The pane may have been used by another level since (a push or pop clears it): it shows this commit only
	-- when it still carries the commit's marker.
	-- stylua: ignore
	if state.key == key(item) and view.loaded_file == MARK .. key(item) then return end
	state.key = key(item)
	if state.proc then
		state.proc.kill()
		state.proc = nil
	end
	View.win.wo(view.win, "wrap", false)

	local req = {}
	state.req = req
	local answered = false
	state.proc = M.detail(item, function(result)
		answered = true
		-- stylua: ignore
		if state.req ~= req or not view:is_valid() then return end
		state.proc = nil
		draw(view, item, result.detail, result.error and result.error.message)
		pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
	end)
	-- Not in the cache: the header and message are known already.
	if not answered then
		draw(view, item)
		pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
	end
end

return M
