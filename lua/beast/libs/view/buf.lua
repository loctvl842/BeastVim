local confirm = require("beast.libs.confirm")

---@class Beast.Buf
local M = {}

---@class Beast.Buf.DeleteOpts
---@field buf? integer Buffer to delete (default: current buffer)
---@field force? boolean Force deletion (default: false)

---@param opts? number|Beast.Buf.DeleteOpts
function M.delete(opts)
	opts = opts or {}
	opts = type(opts) == "number" and { buf = opts } or opts

	local buf = opts.buf or 0
	buf = buf == 0 and vim.api.nvim_get_current_buf() or buf

  -- stylua: ignore
  if not vim.api.nvim_buf_is_valid(buf) then return end

	-- Check if the buffer is modified
	if vim.bo[buf].modified and not opts.force then
		local ok, choice = pcall(
			confirm --[[@as fun(msg: string, choices?: string, default?: integer, type?: string): integer]],
			("Save changes to %q?"):format(vim.fn.fnamemodify(vim.fn.bufname(buf), ":t")),
			"&Yes\n&No\n&Cancel"
		)
		if not ok or choice == 0 or choice == 3 then -- 0 for <Esc>/<C-c> and 3 for Cancel
			return
		elseif choice == 1 then -- Save
			vim.api.nvim_buf_call(buf, function()
				vim.cmd("silent write")
				local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
				Toast(fname .. " saved")
			end)
		end
	end

	-- Get the most recently used listed buffer that is not the one being deleted,
	local info = vim.fn.getbufinfo({ buflisted = 1 })
	---@param b vim.fn.getbufinfo.ret.item
	info = vim.tbl_filter(function(b)
		return b.bufnr ~= buf
	end, info)
	table.sort(info, function(a, b)
		return a.lastused > b.lastused
	end)

	local new_buf = info[1] and info[1].bufnr or vim.api.nvim_create_buf(true, false)

	-- replace the buffer in all windows showing it,
	-- trying to use the alternate buffer if possible
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		local win_buf = new_buf
		vim.api.nvim_win_call(win, function() -- Try using alternate buffer
			local alt = vim.fn.bufnr("#")
			win_buf = alt >= 0 and alt ~= buf and vim.bo[alt].buflisted and alt or win_buf
		end)
		vim.api.nvim_win_set_buf(win, win_buf)
	end

	if vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.cmd --[[@as fun(cmd: string, args: string|table):boolean]], "bdelete! " .. buf)
	end
end

---@param filetype string
---@return integer
function M.new(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

return M
