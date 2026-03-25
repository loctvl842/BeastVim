---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")
local config = require("beast.libs.explorer.config")
local ui = require("beast.libs.explorer.ui")

local ns = vim.api.nvim_create_namespace("BeastExplorerConfirm")

local M = setmetatable({}, {
	__call = function(t, ...)
		return t.run(...)
	end,
})

---@class Beast.Explorer.ConfirmOpts
---@field default? '"yes"'|'"no"'

---@param label string
---@param width integer
---@return string
local function button(label, width)
	local pad = width - #label
	local left = math.floor(pad / 2)
	local right = pad - left
	return string.rep(" ", left) .. label .. string.rep(" ", right)
end

---@param target string  display name of the thing to delete
---@param opts? Beast.Explorer.ConfirmOpts
---@param cb fun(ok: boolean)
local function open_confirm_popup(target, opts, cb)
	opts = opts or {}

	local message = string.format('Are you sure you want to delete "%s"?', target)
	local selected = opts.default == "yes" and 1 or 2 -- 1 = yes, 2 = no

	local btn_width = 12
	local yes_btn = button("Remove", btn_width)
	local no_btn = button("Cancel", btn_width)
	local gap = "  "
	local buttons = yes_btn .. gap .. no_btn

	local content_width = math.max(#message, #buttons)
	local width = math.min(math.max(content_width + 4, 60), 80)
	local height = 3

	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false

	local backdrop_buf = vim.api.nvim_create_buf(false, true)
	vim.bo[backdrop_buf].buftype = "nofile"
	vim.bo[backdrop_buf].bufhidden = "wipe"
	vim.bo[backdrop_buf].swapfile = false

	local backdrop_win = vim.api.nvim_open_win(backdrop_buf, false, {
		relative = "editor",
		row = 0,
		col = 0,
		width = vim.o.columns,
		height = vim.o.lines,
		style = "minimal",
		focusable = false,
		zindex = 10,
	})

	vim.wo[backdrop_win].winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat"
	vim.wo[backdrop_win].winblend = 30

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		zindex = 11,
	})

	vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
	vim.wo[win].cursorline = false
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"

	local closed = false

	local function close(ok)
    -- stylua: ignore
    if closed then return end
		closed = true
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_win_is_valid(backdrop_win) then
			vim.api.nvim_win_close(backdrop_win, true)
		end
		if cb then
			cb(ok)
		end
	end

	local function render()
		local inner_width = width - 2
		local button_col = math.floor((inner_width - #buttons) / 2)
		if button_col < 0 then
			button_col = 0
		end

		local line1 = " " .. message .. string.rep(" ", math.max(0, inner_width - 1 - #message))
		local line2 = string.rep(" ", inner_width)
		local line3 = string.rep(" ", button_col) .. buttons
		line3 = line3 .. string.rep(" ", math.max(0, inner_width - #line3))

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
			line1,
			line2,
			line3,
		})

		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

		-- filename: bold only
		local quoted = string.format('"%s"', target)
		local fs, fe = line1:find(quoted, 1, true)
		if fs and fe then
			vim.api.nvim_buf_set_extmark(buf, ns, 0, fs - 1, {
				end_col = fe,
				hl_group = "Bold",
			})
		end

		local yes_start = button_col
		local yes_end = yes_start + #yes_btn
		local no_start = yes_end + #gap
		local no_end = no_start + #no_btn

		vim.api.nvim_buf_set_extmark(buf, ns, 2, yes_start, {
			end_col = yes_end,
			hl_group = selected == 1 and "PmenuSel" or "Normal",
		})

		vim.api.nvim_buf_set_extmark(buf, ns, 2, no_start, {
			end_col = no_end,
			hl_group = selected == 2 and "PmenuSel" or "Normal",
		})
	end

	local map_opts = { buffer = buf, nowait = true, silent = true }

	local function select_yes()
		print("yes")
		selected = 1
		render()
	end

	local function select_no()
		print("no")
		selected = 2
		render()
	end

	local function toggle()
		selected = selected == 1 and 2 or 1
		render()
	end

	vim.keymap.set("n", "<Left>", select_yes, map_opts)
	vim.keymap.set("n", "<Down>", select_yes, map_opts)
	vim.keymap.set("n", "h", select_yes, map_opts)
	vim.keymap.set("n", "j", select_yes, map_opts)
	vim.keymap.set("n", "<Right>", select_no, map_opts)
	vim.keymap.set("n", "<Up>", select_no, map_opts)
	vim.keymap.set("n", "l", select_no, map_opts)
	vim.keymap.set("n", "k", select_no, map_opts)
	vim.keymap.set("n", "<Tab>", toggle, map_opts)
	vim.keymap.set("n", "<S-Tab>", toggle, map_opts)
	vim.keymap.set("n", "<CR>", function()
		print("CR", selected)
		close(selected ~= 1)
	end, map_opts)
	vim.keymap.set("n", "<Esc>", function()
		close(true)
	end, map_opts)
	vim.keymap.set("n", "q", function()
		close(true)
	end, map_opts)

	render()
end

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
end

function M.run()
	local node = state.current_node({ show_hidden = config.show_hidden })
  -- stylua: ignore
  if not node then return end

  -- cannot delete root
  -- stylua: ignore
  if node.depth == -1 then return end
	open_confirm_popup(node.name, { default = "no" }, function(ok)
		if ok then
			-- Return focus to the explorer
			if state.view and state.view:is_valid() then
				pcall(vim.api.nvim_set_current_win, state.view.win)
			end
			return
		end

		local path = node.path
		local parent_path = node.parent
		local target_buf = vim.fn.bufnr(path)

		-- If the file is currently shown anywhere, move those windows away first.
		if target_buf > 0 and vim.api.nvim_buf_is_valid(target_buf) then
			fallback_from_deleted_buffer(target_buf)
		end

		-- Delete from filesystem
		local ret = vim.fn.delete(path, "rf")
		if ret ~= 0 then
			vim.notify("Failed to delete: " .. node.name, vim.log.levels.ERROR)
			return
		end

		-- Refresh the parent in the tree and re-render
		if parent_path then
			state.tree:refresh(parent_path)
		end

		ui.render(function()
			if state.view and state.view:is_valid() then
				pcall(vim.api.nvim_set_current_win, state.view.win)
			end
		end)
	end)
end

return M
