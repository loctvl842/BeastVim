--- Search the text (title and description) of the issues of the list this picker was opened from.
--- Nothing is fetched: the issues are the ones the issue list already holds, and the prompt text is
--- looked up in them as a plain string (smart case: any capital makes it case-sensitive).
local format = require("beast.libs.finder.format")

---@class Beast.Finder.Source.GhIssueGrep: Beast.Finder.ASource
local M = {}

M.live = true
M.async = true
M.auto_select = false
M.format = format.live_grep
M.header = format.gh_issue_grep_header

-- Keeps one broad word from turning into tens of thousands of rows.
local RESULT_LIMIT = 5000

--- The issue a row was found in is what it groups under.
---@param item Beast.Finder.Item
---@return string
function M.group(item)
	return item.url
end

---@param filter Beast.Finder.Filter
---@return string?
function M.placeholder(filter)
	return ("(type to search the text of the %d issues)"):format(#filter.ctx.issues)
end

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil)
function M.get(filter, cb)
	local needle = filter.pattern
	local sensitive = needle:find("%u") ~= nil
	if not sensitive then
		needle = needle:lower()
	end
	local count = 0
	for _, issue in ipairs(filter.ctx.issues) do
		local lnum = 0
		for line in (issue.title .. "\n" .. (issue.body or "")):gmatch("([^\n]*)\n?") do
			lnum = lnum + 1
			line = line:gsub("\r$", "")
			local at = (sensitive and line or line:lower()):find(needle, 1, true)
			if at and count < RESULT_LIMIT then
				count = count + 1
				cb({
					idx = count,
					score = 1,
					text = ("#%d:%d: %s"):format(issue.number, lnum, line),
					url = issue.url,
					issue = issue,
					pos = { lnum, at - 1 },
					grep_text = line,
					match_text = line:sub(at, at + #needle - 1),
				})
			end
		end
	end
	vim.schedule(function()
		cb(nil)
	end)
end

--- The issue itself, as the issue list previews it.
---@param view Beast.Finder.PreviewView
---@param item? Beast.Finder.Item
function M.preview(view, item)
	require("beast.libs.finder.source.gh.preview").show(view, item and item.issue)
end

return M
