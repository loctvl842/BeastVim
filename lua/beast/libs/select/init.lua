local config = require("beast.libs.select.config")
local ui = require("beast.libs.select.ui")

-- Captured at module load time, before setup() ever reassigns vim.ui.select,
-- so the `disabled`/headless paths can still fall back to Neovim's own
-- default implementation.
local native_select = vim.ui.select

---@class Beast.Select.Opts
---@field prompt? string
---@field format_item? fun(item: any): string
---@field kind? string
---@field format_tag? fun(item: any): string? BeastVim extension: optional right-aligned dim tag per item.
---@field footer_hints? { key: string, label: string }[] BeastVim extension: extra footer hints alongside Confirm/Cancel.

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "select", description = "Themed floating replacement for vim.ui.select" }

--- Drop-in replacement for vim.ui.select with the same signature and
--- callback contract: on_choice is called with (item, idx), or (nil, nil)
--- if the user aborted.
---@generic T
---@param items T[]
---@param opts? Beast.Select.Opts
---@param on_choice fun(item: T?, idx: integer?)
function M.run(items, opts, on_choice)
	if config.disabled or not vim.api.nvim_list_uis()[1] then
		return native_select(items, opts, on_choice)
	end

	opts = opts or {}
	ui.open(items, {
		prompt = opts.prompt or "Select one of:",
		format_item = opts.format_item or tostring,
		kind = opts.kind,
		format_tag = opts.format_tag,
		footer_hints = opts.footer_hints,
	}, on_choice)
end

---@param opts? Beast.Select.Config
function M.setup(opts)
	require("beast").apply_highlights("beast.libs.select.highlights")
	config.setup(opts)
	vim.ui.select = M.run
end

return M
