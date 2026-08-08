local config = require("beast.libs.input.config")
local ui = require("beast.libs.input.ui")

-- Captured at module load time, before setup() ever reassigns vim.ui.input,
-- so the `disabled`/headless paths can still fall back to Neovim's own
-- default implementation.
local native_input = vim.ui.input

---@class Beast.Input.Opts
---@field prompt? string
---@field default? string
---@field completion? string
---@field highlight? fun(text: string): {[1]: integer, [2]: integer, [3]: string}[]

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "input", description = "Cursor-aware floating replacement for vim.ui.input" }

--- Drop-in replacement for vim.ui.input with the same signature and callback
--- contract: on_confirm is called with the entered text, or nil on cancel.
---@param opts? Beast.Input.Opts
---@param on_confirm fun(text: string?)
function M.run(opts, on_confirm)
	if config.disabled or not vim.api.nvim_list_uis()[1] then
		return native_input(opts, on_confirm)
	end

	ui.open_centered(opts or {}, on_confirm)
end

---@param opts? Beast.Input.Config
function M.setup(opts)
	require("beast").apply_highlights("beast.libs.input.highlights")
	config.setup(opts)
	vim.ui.input = M.run
end

return M
