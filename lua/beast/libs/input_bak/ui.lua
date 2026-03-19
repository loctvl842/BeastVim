---@class Beast.Input.UI.View
---@field buf integer
---@field win integer
---@field ns  integer
---@field augroup integer
local View = {}
View.__index = View

---@param buf integer
---@param win integer
---@param ns integer
---@param augroup integer
---@return Beast.Input.UI.View
function View:new(buf, win, ns, augroup)
	return setmetatable({
		buf = buf,
		win = win,
		ns = ns,
		augroup = augroup,
	}, self)
end

---@return boolean
function View:is_valid()
	return self.buf ~= nil
		and self.win ~= nil
		and vim.api.nvim_buf_is_valid(self.buf)
		and vim.api.nvim_win_is_valid(self.win)
end

---@return string
function View:text()
	if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
		return ""
	end
	return vim.api.nvim_buf_get_lines(self.buf, 0, 1, false)[1] or ""
end

---@param text string
function View:set_text(text)
	if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
		return
	end
	vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, { text })
	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_set_cursor(self.win, { 1, #text })
	end
end

---@param layout_cfg { min_width: integer, expand: boolean, row: integer }
function View:update_layout(layout_cfg)
	if not self:is_valid() then
		return
	end
	local min_w = layout_cfg.min_width or 60
	local width = min_w
	if layout_cfg.expand then
		local text = self:text()
		width = math.max(min_w, vim.api.nvim_strwidth(text) + 5)
	end
	local col = math.floor((vim.o.columns - width) / 2)
	vim.api.nvim_win_set_config(self.win, {
		relative = "editor",
		row = layout_cfg.row or 2,
		col = col,
		width = width,
	})
end

function View:close()
	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_close(self.win, true)
		self.win = nil
	end
	if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
		pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
		self.buf = nil
	end
end

-- =============================================================================

local M = {}

---@class Beast.Input.UI.OpenOpts
---@field icon?       string
---@field icon_pos?   "left"|"title"|false
---@field icon_hl?    string
---@field prompt?     string
---@field prompt_pos? "left"|"title"|false
---@field expand?     boolean
---@field min_width?  integer
---@field border?     string
---@field row?        integer
---@field zindex?     integer

---@param opts Beast.Input.UI.OpenOpts
---@param on_close fun()
---@param ns integer
---@return Beast.Input.UI.View
function M.open(opts, on_close, ns)
	-- Create scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = ""
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "beastvim_input"
	vim.bo[buf].modifiable = true

	-- Build title chunks and statuscolumn segments from icon/prompt config
	local title = {} ---@type {[1]: string, [2]: string}[]
	local statuscol = {} ---@type string[]

	local function add(text, hl, pos)
		if pos == "title" then
			table.insert(title, { " " .. text, hl })
		elseif pos == "left" then
			table.insert(statuscol, "%#" .. hl .. "#" .. text)
		end
	end

	if opts.icon_pos and (opts.icon or "") ~= "" then
		add(opts.icon, opts.icon_hl or "BeastInputIcon", opts.icon_pos)
	end
	if opts.prompt and opts.prompt ~= "" then
		add(opts.prompt, "BeastInputPrompt", opts.prompt_pos or "title")
	end

	if next(title) then
		table.insert(title, { " ", "BeastInputTitle" })
	end

	-- Geometry
	local min_width = opts.min_width or 60
	local width = min_width
	local row = opts.row or 2
	local col = math.floor((vim.o.columns - width) / 2)

	-- Open window
	local win_config = {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = 1,
		style = "minimal",
		border = opts.border or "rounded",
		zindex = opts.zindex or 51,
	}
	if next(title) then
		win_config.title = title
		win_config.title_pos = "center"
	end

	local win = vim.api.nvim_open_win(buf, true, win_config)

	-- Apply window-local options
	local winhl = "NormalFloat:BeastInputNormal,FloatBorder:BeastInputBorder,FloatTitle:BeastInputTitle"
	Util.wo(win, "winhighlight", winhl)
	Util.wo(win, "cursorline", false)
	Util.wo(win, "number", false)
	Util.wo(win, "relativenumber", false)
	Util.wo(win, "signcolumn", "no")
	Util.wo(win, "wrap", false)

	if next(statuscol) then
		Util.wo(win, "statuscolumn", " " .. table.concat(statuscol, " ") .. " ")
	end

	-- Register BufLeave autocmd — fires when user navigates away from the input
	local augroup =
		vim.api.nvim_create_augroup("BeastInput_" .. tostring(vim.loop.hrtime()), { clear = true })
	vim.api.nvim_create_autocmd("BufLeave", {
		group = augroup,
		buffer = buf,
		once = true,
		callback = function()
			on_close()
		end,
	})

	return View:new(buf, win, ns, augroup)
end

return M
