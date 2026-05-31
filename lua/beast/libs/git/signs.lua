-- Extmark sign placement for hunk markers.
--
-- Namespace: `beast_git_signs` — distinct from gitsigns.nvim's `gitsigns`
-- namespace so the two can coexist. The statuscolumn library's signs.lua
-- routes our extmarks via a `^beast_git_signs` namespace pattern (one-line
-- addition to its NS_PATTERNS).

local api = vim.api
local icon = require("beast.icon")

local M = {}

local NS = api.nvim_create_namespace("beast_git_signs")
M.namespace = NS

---@type table<string, string>
local HL_BY_TYPE = {
	add = "BeastGitAdd",
	change = "BeastGitChange",
	delete = "BeastGitDelete",
	topdelete = "BeastGitTopDelete",
	changedelete = "BeastGitChangedelete",
}

--- Resolved icon table; refreshed by setup() when user overrides.
---@type table<string, string>
local icons = vim.deepcopy(icon.gitsigns)

---@param overrides? Beast.Git.Icons
function M.set_icons(overrides)
	icons = vim.tbl_extend("force", vim.deepcopy(icon.gitsigns), overrides or {})
end

---@param buf integer
---@param line_signs table<integer, { type: string }>
function M.place(buf, line_signs)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	api.nvim_buf_clear_namespace(buf, NS, 0, -1)
	for lnum, info in pairs(line_signs) do
		local glyph = icons[info.type]
		local hl = HL_BY_TYPE[info.type]
		if glyph and hl then
			pcall(api.nvim_buf_set_extmark, buf, NS, lnum - 1, 0, {
				sign_text = glyph,
				sign_hl_group = hl,
				priority = 6,
			})
		end
	end
end

---@param buf integer
function M.clear(buf)
	if api.nvim_buf_is_valid(buf) then
		api.nvim_buf_clear_namespace(buf, NS, 0, -1)
	end
end

return M
