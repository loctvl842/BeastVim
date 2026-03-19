---@class Beast.Input.Config
---@field icon?       string
---@field icon_hl?    string
---@field icon_pos?   "left"|"title"|false
---@field prompt_pos? "left"|"title"|false
---@field expand?     boolean

local defaults = {
	icon = " ",
	icon_hl = "BeastInputIcon",
	icon_pos = "left",
	prompt_pos = "title",
	expand = true,
}

---@type Beast.Input.Config
local cfg = vim.deepcopy(defaults)

local _orig_vim_ui_input = vim.ui.input

local M = {}

---@param opts? Beast.Input.Config
function M.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	require("beastvim.libs.input_bak.highlights").setup()
end

function M.enable()
	vim.ui.input = require("beastvim.libs.input_bak.core").input
end

function M.disable()
	vim.ui.input = _orig_vim_ui_input
end

return M
