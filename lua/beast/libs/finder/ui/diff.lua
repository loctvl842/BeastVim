--- A changed file's diff, as the finder shows it. One place knows a file's patch, its one-line summary and
--- what to say when there is no patch (binary, or too large for GitHub to return).
---@class Beast.Finder.UI.Diff
local M = {}

---@class Beast.Finder.Diff.File
---@field status string added|removed|modified|renamed|...
---@field previous? string path before a rename
---@field additions integer
---@field deletions integer
---@field patch? string unified diff; absent for binary or very large diffs

local NO_DIFF = "(diff too large or binary)"

--- "modified  +5 -6", then the `path` when given, then "(was <old path>)" for a rename.
---@param file Beast.Finder.Diff.File
---@param path? string
---@return string
function M.summary(file, path)
	local text = ("%-9s +%d -%d"):format(file.status, file.additions, file.deletions)
	if path then
		text = text .. "  " .. path
	end
	return file.previous and (text .. "  (was " .. file.previous .. ")") or text
end

--- The patch of a file as lines, or the one line saying there is none.
---@param file Beast.Finder.Diff.File
---@return string[]
function M.raw_lines(file)
	return file.patch and vim.split(file.patch, "\n", { plain = true }) or { NO_DIFF }
end

return M
