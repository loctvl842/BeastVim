local M = {}

---@param query Beast.Finder.Query
---@param item Beast.Finder.Item
function M.open(query, item)
	if query.source.name == "help_tags" then
		return M.open_help(query, item)
	elseif query.source.name == "colorschemes" then
		pcall(vim.cmd.colorscheme, item.text)
		return
	end
	M.open_file(query, item)
end

---@param query Beast.Finder.Query
---@param item Beast.Finder.Item
function M.open_help(query, item)
	-- stylua: ignore
	if not item or not item.help_tag then return end
	local win = query.main_win
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

---@param query Beast.Finder.Query
---@param item Beast.Finder.Item
function M.open_file(query, item)
	-- stylua: ignore
	if not item or not item.file then return end
	local win = query.main_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("edit " .. vim.fn.fnameescape(item.file))

	if item.pos then
		pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, item.pos[1]), item.pos[2] or 0 })
	end
end

---@param query Beast.Finder.Query
---@param item Beast.Finder.Item
function M.open_split(query, item)
	-- stylua: ignore
	if not item or not item.file then return end
	local win = query.main_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("split " .. vim.fn.fnameescape(item.file))
end

---@param query Beast.Finder.Query
---@param item Beast.Finder.Item
function M.open_vsplit(query, item)
	-- stylua: ignore
	if not item or not item.file then return end
	local win = query.main_win
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
