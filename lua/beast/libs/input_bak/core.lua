local ui = require("beastvim.libs.input_bak.ui")
local History = require("beastvim.libs.input_bak.history").History

-- Cached at module level; nvim_create_namespace is idempotent for the same name.
local ns = vim.api.nvim_create_namespace("beastvim.input")

---@class Beast.Input.Ctx
---@field opts? Beast.Input.Opts
---@field win?  Beast.Input.UI.View
local ctx = {}

local M = {}

---@alias Beast.Input.Highlight {[1]: number, [2]: number, [3]: string}

---@class Beast.Input.Opts
---@field prompt?     string
---@field default?    string
---@field completion? string
---@field highlight?  fun(text: string): Beast.Input.Highlight[]
---@field icon?       string
---@field icon_pos?   "left"|"title"|false
---@field icon_hl?    string
---@field prompt_pos? "left"|"title"|false
---@field expand?     boolean
---@field min_width?  integer
---@field border?     string
---@field row?        integer
---@field zindex?     integer

local defaults = {
	icon = " ",
	icon_hl = "BeastInputIcon",
	icon_pos = "left",
	prompt_pos = "title",
	expand = true,
	min_width = 60,
	border = "rounded",
	row = 2,
	zindex = 51,
}

---@param opts? Beast.Input.Opts
---@param on_confirm fun(value?: string)
function M.input(opts, on_confirm)
	assert(type(on_confirm) == "function", "`on_confirm` must be a function")

	local parent_win = vim.api.nvim_get_current_win()
	local mode = vim.fn.mode()

	opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	opts.prompt = vim.trim(opts.prompt or "Input")
	if opts.prompt_pos == "title" then
		opts.prompt = opts.prompt:gsub(":$", "")
	end

	local history = History:new({
		filter = function(v)
			return v ~= ""
		end,
	})

	-- closed guards against double-invocation (confirm vs BufLeave cancel)
	local closed = false

	-- Forward-declare so the on_close callback and keymaps both share the same reference.
	---@type fun(value?: string)
	local do_confirm

	-- Open the floating window.  The on_close callback fires on BufLeave (user
	-- navigated away without confirming).
	local view = ui.open(opts, function()
		do_confirm(nil) -- cancel
	end, ns)

	-- Now that view exists, define do_confirm properly.
	do_confirm = function(value)
		if closed then
			return
		end
		closed = true
		history:record(value or "")
		ctx = {}
		-- Delete BufLeave handler before closing the window so that the
		-- handler does not fire again and re-enter this function.
		if view.augroup then
			pcall(vim.api.nvim_del_augroup_by_id, view.augroup)
			view.augroup = nil
		end
		view:close()
		vim.cmd.stopinsert()
		vim.schedule(function()
			if vim.api.nvim_win_is_valid(parent_win) then
				vim.api.nvim_set_current_win(parent_win)
				if mode == "i" then
					vim.cmd("startinsert")
				end
			end
			on_confirm(value)
		end)
	end

	ctx = { opts = opts, win = view }

	-- Completion (accessed via v:lua from vimscript)
	vim.bo[view.buf].completefunc = "v:lua.require'beastvim.libs.input_bak.core'.complete"
	vim.bo[view.buf].omnifunc = "v:lua.require'beastvim.libs.input_bak.core'.complete"

	-- Highlight extmarks for the current text
	local function highlight()
		if type(opts.highlight) ~= "function" then
			return
		end
		local text = view:text()
		vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)
		for _, hl in ipairs(opts.highlight(text)) do
			vim.api.nvim_buf_set_extmark(view.buf, ns, 0, hl[1], {
				end_col = hl[2],
				hl_group = hl[3],
				strict = false,
			})
		end
	end

	-- Dynamic width resize when expand = true
	local function update_layout()
		view:update_layout({
			min_width = opts.min_width,
			expand = opts.expand,
			row = opts.row,
		})
		vim.api.nvim_win_call(view.win, function()
			vim.fn.winrestview({ leftcol = 0 })
		end)
	end

	-- Buffer-local keymaps
	local ko = { buffer = view.buf, silent = true, nowait = true }

	vim.keymap.set({ "i", "n" }, "<CR>", function()
		if vim.fn.pumvisible() == 1 then
			return vim.api.nvim_replace_termcodes("<C-y>", true, false, true)
		end
		do_confirm(view:text())
	end, vim.tbl_extend("force", ko, { expr = true }))

	vim.keymap.set("i", "<Esc>", function()
		if vim.fn.pumvisible() == 1 then
			return vim.api.nvim_replace_termcodes("<C-e>", true, false, true)
		end
		vim.schedule(function()
			vim.cmd("stopinsert")
		end)
	end, vim.tbl_extend("force", ko, { expr = true }))

	vim.keymap.set("n", "<Esc>", function()
		do_confirm(nil)
	end, ko)

	vim.keymap.set({ "i", "n" }, "<C-c>", function()
		do_confirm(nil)
	end, ko)

	vim.keymap.set({ "i", "n" }, "<Up>", function()
		view:set_text(history:prev(view:text()))
	end, ko)

	vim.keymap.set({ "i", "n" }, "<Down>", function()
		view:set_text(history:next())
	end, ko)

	vim.keymap.set("i", "<Tab>", function()
		if vim.fn.pumvisible() == 1 then
			return vim.api.nvim_replace_termcodes("<C-n>", true, false, true)
		end
		return vim.api.nvim_replace_termcodes("<C-x><C-u>", true, false, true)
	end, vim.tbl_extend("force", ko, { expr = true }))

	-- TextChanged autocmd for highlight + expand
	local change_augroup =
		vim.api.nvim_create_augroup("BeastInputChange_" .. tostring(vim.loop.hrtime()), { clear = true })
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		group = change_augroup,
		buffer = view.buf,
		callback = function()
			if not view:is_valid() then
				return
			end
			highlight()
			vim.bo[view.buf].modified = false
			if opts.expand then
				update_layout()
			end
		end,
	})

	-- Wrap view:close so it also cleans up the change augroup
	local orig_close = view.close
	view.close = function(self)
		pcall(vim.api.nvim_del_augroup_by_id, change_augroup)
		orig_close(self)
	end

	-- Apply default text and initial highlight
	if opts.default then
		view:set_text(opts.default)
	end
	highlight()

	-- Start insert mode at end of line
	vim.api.nvim_win_call(view.win, function()
		vim.cmd("startinsert!")
	end)
end

---Completion callback invoked by Neovim via completefunc/omnifunc.
---Must be module-level so `v:lua.require'...'.complete` can reference it.
---@param findstart integer
---@param base string
---@return integer|string[]
function M.complete(findstart, base)
	if findstart == 1 then
		return 0
	end
	local completion = ctx.opts and ctx.opts.completion
	if not completion then
		return {}
	end
	local ok, results = pcall(vim.fn.getcompletion, base, completion)
	return ok and results or {}
end

return M
