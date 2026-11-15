local M = {}

---@param state Beast.Finder.State
---@param item Beast.Finder.Item
function M.open(state, item)
	if item.url then
		return M.open_url(item)
	elseif state.query.source.name == "help_tags" then
		return M.open_help(state.main_win, item)
	elseif state.query.source.name == "colorschemes" then
		-- Live preview has usually applied it already; re-applying would repaint the editor again.
		if vim.g.colors_name ~= item.text then
			pcall(vim.cmd.colorscheme, item.text)
		end
		return
	end
	M.open_file(state.main_win, item)
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
