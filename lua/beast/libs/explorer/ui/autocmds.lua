---@type Beast.Explorer.State
local state = require("beast.libs.explorer.state")

local M = {}

--- Mount cursor-hiding autocmds for the explorer window.
--- Safe to call multiple times — skips if already mounted.
function M.mount()
	-- stylua: ignore
	if state.augroup then return end
	-- stylua: ignore
	if not state.view or not state.view.buf or not state.view.win then return end

	state.augroup = vim.api.nvim_create_augroup("BeastExplorerUI_" .. tostring(vim.loop.hrtime()), { clear = true })

	vim.api.nvim_set_hl(0, "BeastExplorerCursor", { blend = 100, nocombine = true })

	---@type string?
	local prev_guicursor = vim.o.guicursor
	vim.o.guicursor = "a:block-BeastExplorerCursor"

	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
		group = state.augroup,
		buffer = state.view.buf,
		callback = function()
			if vim.api.nvim_get_current_win() ~= state.view.win then
				return
			end
			if prev_guicursor == nil then
				prev_guicursor = vim.o.guicursor
			end
			vim.o.guicursor = "a:block-BeastExplorerCursor"
		end,
	})

	vim.api.nvim_create_autocmd("WinLeave", {
		group = state.augroup,
		buffer = state.view.buf,
		callback = function()
			if prev_guicursor ~= nil then
				vim.o.guicursor = prev_guicursor
				prev_guicursor = nil
			end
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = state.augroup,
		pattern = tostring(state.view.win),
		once = true,
		callback = function()
			if prev_guicursor ~= nil then
				vim.o.guicursor = prev_guicursor
				prev_guicursor = nil
			end
			state.augroup = nil
		end,
	})
end

return M
