--- Visual-mode helpers shared by hunk actions and preview.
local M = {}

--- Return `(start, end)` line numbers if invoked from a visual-mode mapping,
--- else `nil, nil`. Reads the live selection via `line("v")` / `line(".")` —
--- these stay valid during the keymap's :lua callback because we haven't
--- left visual mode yet. Charwise / linewise / blockwise all collapse to
--- "the buffer-line span the selection touches", which is what hunks care
--- about. Sends `<Esc>` so subsequent commands (cursor moves, autocmds)
--- don't run inside visual.
---@return integer?, integer?
function M.range()
	local mode = vim.fn.mode()
	if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
		return nil, nil
	end
	local s = vim.fn.line("v")
	local e = vim.fn.line(".")
	if s > e then
		s, e = e, s
	end
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
	return s, e
end

return M
