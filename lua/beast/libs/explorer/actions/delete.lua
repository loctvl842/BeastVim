local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")
local confirm = require("beast.libs.confirm")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

---@param target_buf integer
---@param exclude integer[]
---@return integer?
local function find_fallback_buffer(target_buf, exclude)
	exclude = exclude or {}

	local excluded = {
		[target_buf] = true,
	}
	for _, bufnr in ipairs(exclude) do
		excluded[bufnr] = true
	end

	-- Prefer alternate buffer first.
	local alt = vim.fn.bufnr("#")
	if alt > 0 and not excluded[alt] and vim.fn.buflisted(alt) == 1 and vim.api.nvim_buf_is_valid(alt) then
		return alt
	end

	-- Then most recently used listed buffer.
	local infos = vim.fn.getbufinfo({ buflisted = 1 })
	table.sort(infos, function(a, b)
		return (a.lastused or 0) > (b.lastused or 0)
	end)

	for _, info in ipairs(infos) do
		local bufnr = info.bufnr
		if not excluded[bufnr] and vim.api.nvim_buf_is_valid(bufnr) then
			return bufnr
		end
	end

	return nil
end

---@param target_buf integer
---@return integer? fallback_buf
local function fallback_from_deleted_buffer(target_buf)
	if target_buf <= 0 or not vim.api.nvim_buf_is_valid(target_buf) then
		return
	end

	local wins = vim.api.nvim_list_wins()
	local fallback = find_fallback_buffer(target_buf, {
		state.view and state.view.buf or -1,
	})

	for _, win in ipairs(wins) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == target_buf then
			if fallback and vim.api.nvim_buf_is_valid(fallback) then
				pcall(vim.api.nvim_win_set_buf, win, fallback)
			else
				-- No usable previous buffer: create an empty one in that window.
				local new_buf = vim.api.nvim_create_buf(true, false)
				pcall(vim.api.nvim_win_set_buf, win, new_buf)
			end
		end
	end

	return fallback
end

---@param choice integer -- 1=confirmed, anything else=cancelled
---@param node table
local function on_confirm(choice, node)
	if choice ~= 1 then
		-- Return focus to the explorer
		if state.view and state.view:is_valid() then
			pcall(vim.api.nvim_set_current_win, state.view.win)
		end
		return
	end

	local path = node.path
	local parent_path = node.parent
	local target_buf = vim.fn.bufnr(path)

	-- Resolve fallback before touching any windows (alternate buffer changes after switch).
	local fallback_buf = nil
	if target_buf > 0 and vim.api.nvim_buf_is_valid(target_buf) then
		fallback_buf = fallback_from_deleted_buffer(target_buf)
	end

	-- Delete from filesystem
	local ret = vim.fn.delete(path, "rf")
	if ret ~= 0 then
		vim.notify("Failed to delete: " .. node.name, vim.log.levels.ERROR)
		return
	end

	-- Wipe the buffer so it doesn't linger in memory
	if target_buf > 0 and vim.api.nvim_buf_is_valid(target_buf) then
		pcall(vim.api.nvim_buf_delete, target_buf, { force = true })
	end

	-- Refresh the parent in the tree and re-render
	if parent_path then
		state.tree:refresh(parent_path)
	end

	local fallback_path = fallback_buf and vim.api.nvim_buf_get_name(fallback_buf) or nil

	if fallback_path and fallback_path ~= "" then
		pcall(ui.focus_path, fallback_path)
	end
	ui.render(function()
		if state.view and state.view:is_valid() then
			pcall(vim.api.nvim_set_current_win, state.view.win)
		end
	end)
end

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end

  -- cannot delete root
  -- stylua: ignore
  if node.depth == -1 then return end

	local title = string.format('Are you sure you want to delete "%s"?', node.name)
	confirm.set_opts({ min_width = 50, max_width = 60, button_width = 12 })
	local choice = confirm(title, "&Remove\n&Cancel", 2)
	on_confirm(choice, node)
end

function M.run_visual()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
	local start_line = vim.fn.line("'<")
	local end_line = vim.fn.line("'>")
	local flat = state.tree:flat({ show_hidden = config.show_hidden })
	local selected = {}
	for line = start_line, end_line do
		local idx = line - 1 -- row 1 = header; nodes[1] = line 2
		if idx >= 1 and flat[idx] and flat[idx].depth ~= -1 then
			table.insert(selected, flat[idx])
		end
	end

	-- Filter out nodes whose path falls inside another selected directory.
	-- Deleting the parent already removes all its descendants, so including
	-- them would cause double-delete errors.
	local nodes_to_delete = {}
	for _, node in ipairs(selected) do
		local redundant = false
		for _, other in ipairs(selected) do
			if other ~= node and other.dir and node.path:sub(1, #other.path + 1) == other.path .. "/" then
				redundant = true
				break
			end
		end
		if not redundant then
			table.insert(nodes_to_delete, node)
		end
	end

	local title = string.format('Are you sure you want to delete "%s"?', nodes_to_delete[1].name)
	if #nodes_to_delete > 1 then
		title = string.format(" Are you sure you want to delete the following %d files?\n", #nodes_to_delete)
		for _, node in ipairs(nodes_to_delete) do
			title = title .. "\n   " .. node.name
		end
	end
	confirm.set_opts({ align = #nodes_to_delete > 1 and "left" or "center", min_width = 50, max_width = 60, button_width = 12 })
	local choice = confirm(title, "&Remove\n&Cancel", 2)
	for _, node in ipairs(nodes_to_delete) do
		on_confirm(choice, node)
	end
end

return M
