--- The files a pull request changes: opened from the pull request list (a chain), the prompt filters
--- them by path. Each file previews its diff; Enter shows the diff in a scratch buffer.
local api = require("beast.libs.finder.source.gh.api")
local diff = require("beast.libs.finder.ui.diff")
local format = require("beast.libs.finder.format")

---@class Beast.Finder.Source.GhPrFiles: Beast.Finder.ASource
local M = {}

M.live = false
M.async = true
M.auto_select = false
M.keep_order = true
M.count = format.ratio

---@class Beast.Finder.Gh.FileItem: Beast.Finder.Item
---@field pr Beast.Finder.Gh.Item
---@field status string
---@field previous? string
---@field additions integer
---@field deletions integer
---@field patch? string

---@param text string
---@param is_error? boolean
---@return Beast.Finder.Item
local function message(text, is_error)
	return { idx = 1, score = 1, text = text, message = true, is_error = is_error }
end

---@param filter Beast.Finder.Filter
---@param cb fun(item: Beast.Finder.Item|nil)
function M.get(filter, cb)
	---@type Beast.Finder.Gh.Item
	local pr = filter.ctx.pr
	api.files(pr, function(result)
		if result.error then
			cb(message("GitHub could not list the files:", true))
			cb(message(result.error.message, true))
		elseif #result.files == 0 then
			cb(message("No files changed"))
		else
			filter.ctx.truncated = result.truncated
			for i, file in ipairs(result.files) do
				cb({
					idx = i,
					score = 0,
					text = file.path,
					file = file.path,
					cwd = filter.cwd,
					pr = pr,
					status = file.status,
					previous = file.previous,
					additions = file.additions,
					deletions = file.deletions,
					patch = file.patch,
				})
			end
		end
		cb(nil)
	end)
end

--- "PR <title> › Files Changed (N)", the title shortened with "..." when long; `items` is nil while loading.
---@param filter? Beast.Finder.Filter
---@param items? Beast.Finder.Item[]
---@return string
function M.title(filter, items)
	local pr = filter and filter.ctx and filter.ctx.pr
	if not pr then
		return "Files Changed"
	end
	local out = format.pr_label(pr) .. " › Files Changed"
	if items and #items > 0 and not items[1].message then
		out = out .. (" (%d%s)"):format(#items, filter.ctx.truncated and ", partial" or "")
	end
	return out
end

---@param view Beast.Finder.PreviewView
---@param item? Beast.Finder.Gh.FileItem
function M.preview(view, item)
	-- stylua: ignore
	if not view:is_valid() then return end
	if not item or item.message then
		return require("beast.libs.finder.ui.preview").clear(view)
	end
	local lines = { diff.summary(item) }
	vim.list_extend(lines, diff.raw_lines(item))
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false
	vim.bo[view.buf].filetype = "diff"
	-- The preview shows the diff, not a file of the working tree.
	view.loaded_file = nil
	pcall(vim.api.nvim_win_set_config, view.win, { title = " " .. item.file .. " ", title_pos = "center" })
	pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
end

function M.open(session, item)
	require("beast.libs.finder.action").open_diff(session.main_win, item)
end

return M
