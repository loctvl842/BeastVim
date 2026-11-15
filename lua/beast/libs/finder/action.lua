local M = {}

--- What Enter does: whatever the item's source says.
---@param session Beast.Finder.Session
---@param item Beast.Finder.Item
function M.open(session, item)
	return session.level.query.source.open(session, item)
end

--- The default for a source that does not declare `open`: the item's web address, else its file.
---@param session Beast.Finder.Session
---@param item Beast.Finder.Item
function M.open_default(session, item)
	if item.url then
		return M.open_url(item)
	end
	M.open_file(session.main_win, item)
end

--- Open an item's web address in the default browser.
---@param item Beast.Finder.Item
function M.open_url(item)
	local _, err = vim.ui.open(item.url)
	if err then
		Toast("Could not open " .. item.url .. ": " .. err, vim.log.levels.ERROR)
	end
end

---@param win? integer window to focus before opening; falls back to the current window
---@param item Beast.Finder.Item
function M.open_help(win, item)
	-- stylua: ignore
	if not item or not item.help_tag then return end
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	if item.is_readme then
		vim.cmd("botright vsplit " .. vim.fn.fnameescape(item.file))
	else
		vim.cmd({ cmd = "help", args = { item.help_tag }, mods = { vertical = true, split = "botright" } })
	end
	if item.pos then
		pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, item.pos[1]), item.pos[2] or 0 })
	end
end

---@param win? integer window to focus before opening; falls back to the current window
---@param item Beast.Finder.Item
function M.open_file(win, item)
    -- stylua: ignore
    if not item or not item.file then return end
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end

	local same_file = vim.fn.fnamemodify(item.file, ":p") == vim.api.nvim_buf_get_name(0)

	-- Record the pre-jump position in the jumplist so <C-o> returns here,
	-- like vim.lsp.util.show_document does before an LSP jump. `:edit` on a
	-- different file records it too (consecutive same-position entries are
	-- deduped); a same-file jump moves the cursor directly, which would
	-- otherwise leave the jumplist untouched and send <C-o> to a stale entry.
	if item.pos or not same_file then
		vim.cmd("normal! m'")
	end

	-- `:edit` on the buffer already shown means "reload from disk": with unsaved
	-- changes that fails (E37) or, with 'confirm', pops the native save prompt.
	if not same_file then
		vim.cmd("edit " .. vim.fn.fnameescape(item.file))
	end

	if item.pos then
		pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, item.pos[1]), item.pos[2] or 0 })
	end
end

--- Show the diff of a changed file of a pull request in a read-only scratch buffer.
---@param win? integer window to show it in; falls back to the current window
---@param item Beast.Finder.Gh.FileItem
function M.open_diff(win, item)
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	local lines = item.patch and vim.split(item.patch, "\n", { plain = true }) or { "(diff too large or binary)" }
	local buf = vim.api.nvim_create_buf(true, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	-- A second diff of the same file would collide on the name: the old buffer goes first.
	local name = item.commit and ("%s@%s: %s"):format(item.pr.repo, item.commit.short, item.file)
		or ("%s#%d: %s"):format(item.pr.repo, item.pr.number, item.file)
	local existing = vim.fn.bufnr("^" .. vim.fn.escape(name, "\\[].*~") .. "$")
	if existing ~= -1 then
		pcall(vim.api.nvim_buf_delete, existing, { force = true })
	end
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "diff"
	vim.cmd("normal! m'")
	vim.api.nvim_win_set_buf(0, buf)
	for lnum, line in ipairs(lines) do
		if line:sub(1, 2) == "@@" then
			vim.api.nvim_win_set_cursor(0, { lnum, 0 })
			break
		end
	end
end

--- Show a commit of a pull request (message and diffs) in a read-only scratch buffer. The commit's files
--- may still have to be fetched (the picker is already closed), so the buffer opens when they arrive.
---@param win? integer window to show it in; falls back to the current window
---@param item Beast.Finder.Item a commit item
function M.open_commit(win, item)
	local commit_preview = require("beast.libs.finder.source.gh.commit_preview")
	commit_preview.detail(item, function(result)
		if result.error then
			Toast("Could not load the commit: " .. result.error.message, vim.log.levels.WARN)
			return
		end
		if win and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
		end
		local buf = vim.api.nvim_create_buf(true, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		local name = ("%s@%s"):format(item.pr.repo, item.short)
		local existing = vim.fn.bufnr("^" .. vim.fn.escape(name, "\\[].*~") .. "$")
		if existing ~= -1 then
			pcall(vim.api.nvim_buf_delete, existing, { force = true })
		end
		vim.api.nvim_buf_set_name(buf, name)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, commit_preview.build(item, result.detail))
		vim.bo[buf].modifiable = false
		vim.bo[buf].filetype = "diff"
		vim.cmd("normal! m'")
		vim.api.nvim_win_set_buf(0, buf)
	end)
end

---@param win? integer window to focus before opening; falls back to the current window
---@param item Beast.Finder.Item
function M.open_split(win, item)
	-- stylua: ignore
	if not item or not item.file then return end
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("split " .. vim.fn.fnameescape(item.file))
end

---@param win? integer window to focus before opening; falls back to the current window
---@param item Beast.Finder.Item
function M.open_vsplit(win, item)
	-- stylua: ignore
	if not item or not item.file then return end
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("vsplit " .. vim.fn.fnameescape(item.file))
end

---@param item Beast.Finder.Item
function M.copy_path(item)
	local target = item and (item.url or item.file)
	-- stylua: ignore
	if not target then return end
	vim.fn.setreg("+", target)
	Toast("Copied: " .. target, vim.log.levels.INFO)
end

return M
