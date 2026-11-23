-- Symbol trail: the chain of symbols containing a window's cursor, from one source.

local lsp = require("beast.libs.breadcrumb.symbols.lsp")
local treesitter = require("beast.libs.breadcrumb.symbols.treesitter")

local M = {}

M.refresh = lsp.refresh
M.clear = lsp.clear

---Register the callback run when a buffer's symbols are replaced.
---@param fn fun(bufnr: integer)
function M.on_change(fn)
	lsp.on_change = fn
end

---Symbols containing the cursor of `winid`, outermost first. Empty when outside every symbol.
---A language server's answer wins; otherwise the syntax tree is used. The two never mix.
---@param bufnr integer
---@param winid integer
---@return Beast.Breadcrumb.Symbol[]
function M.trail(bufnr, winid)
	local cursor = vim.api.nvim_win_get_cursor(winid)
	local row, col = cursor[1] - 1, cursor[2]
	return lsp.trail(bufnr, row, col) or treesitter.trail(bufnr, row, col) or {}
end

return M
