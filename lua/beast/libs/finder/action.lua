local M = {}

---@param state Beast.Finder.State
---@param item Beast.Finder.Item
function M.open(state, item)
	if state.query.source.name == "help_tags" then
		return M.open_help(state.main_win, item)
	elseif state.query.source.name == "colorschemes" then
		pcall(vim.cmd.colorscheme, item.text)
		return
	end
	M.open_file(state.main_win, item)
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
	vim.cmd("edit " .. vim.fn.fnameescape(item.file))

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
	-- stylua: ignore
	if not item or not item.file then return end
	vim.fn.setreg("+", item.file)
	vim.notify("Copied: " .. item.file, vim.log.levels.INFO)
end

return M
