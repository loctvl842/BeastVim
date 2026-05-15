local M = {}

---@param picker table Beast.Finder.Picker
---@param items Beast.Finder.Item[]
function M.open(picker, items)
	local item = items[1]
	-- stylua: ignore
	if not item or not item.file then return end
	local win = picker.main_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("edit " .. vim.fn.fnameescape(item.file))
	if item.pos then
		pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, item.pos[1]), item.pos[2] or 0 })
	end
end

---@param picker table Beast.Finder.Picker
---@param items Beast.Finder.Item[]
function M.open_split(picker, items)
	local item = items[1]
	-- stylua: ignore
	if not item or not item.file then return end
	local win = picker.main_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("split " .. vim.fn.fnameescape(item.file))
end

---@param picker table Beast.Finder.Picker
---@param items Beast.Finder.Item[]
function M.open_vsplit(picker, items)
	local item = items[1]
	-- stylua: ignore
	if not item or not item.file then return end
	local win = picker.main_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.cmd("vsplit " .. vim.fn.fnameescape(item.file))
end

---@param _picker table
---@param items Beast.Finder.Item[]
function M.copy_path(_picker, items)
	local item = items[1]
	-- stylua: ignore
	if not item or not item.file then return end
	vim.fn.setreg("+", item.file)
	vim.notify("Copied: " .. item.file, vim.log.levels.INFO)
end

---@param _picker table
---@param items Beast.Finder.Item[]
function M.open_buf(picker, items)
	local item = items[1]
	-- stylua: ignore
	if not item or not item.buf then return end
	local win = picker.main_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	vim.api.nvim_set_current_buf(item.buf)
end

---@param picker table Beast.Finder.Picker
---@param items Beast.Finder.Item[]
function M.open_help(picker, items)
	local item = items[1]
	-- stylua: ignore
	if not item or not item.help_tag then return end
	local win = picker.main_win
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_set_current_win(win)
	end
	if item.is_readme then
		vim.cmd("vsplit " .. vim.fn.fnameescape(item.file))
	else
		vim.cmd("vertical help " .. vim.fn.fnameescape(item.help_tag))
	end
end

return M
