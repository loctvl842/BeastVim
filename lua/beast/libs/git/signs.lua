-- Extmark sign placement for hunk markers.
--
-- Namespace: `beast_git_signs` — distinct from gitsigns.nvim's `gitsigns`
-- namespace so the two can coexist (ADR-024).
--
-- ── Contract with statuscolumn ───────────────────────────────────────────
-- We place an extmark per changed line carrying:
--   namespace      = `beast_git_signs`
--   sign_text      = "•"   (placeholder fallback; see below)
--   sign_hl_group  = `BeastGit<Type>`  (Add | Change | Delete | TopDelete | Changedelete)
--   priority       = 6
--
-- IMPORTANT — `BeastGitAdd` / `BeastGitChange` / `BeastGitDelete` /
-- `BeastGitTopDelete` / `BeastGitChangedelete` exist ONLY as routing tags
-- for the statuscolumn classifier. They are NOT real visual highlight
-- groups and MUST NOT be themed by the user — doing so has no effect on
-- the rendered glyph (statuscolumn rewrites both `sign_text` and
-- `sign_hl_group` from its own config + the `BeastStcGit*` family) and
-- would only confuse the next reader.
--
-- The "•" placeholder is what shows up if `statuscolumn` is not loaded
-- (rare edge case): a single cell so the gutter still hints that the
-- line is changed, with no specific colour.
--
-- Glyph + colour owned by `statuscolumn` — set via:
--   require("beast.libs.statuscolumn").setup({
--     git = { icons = { add = "│", change = "┊", ... } },
--   })
--   :hi BeastStcGitAdd guifg=...

local api = vim.api

local M = {}

local NS = api.nvim_create_namespace("beast_git_signs")
M.namespace = NS

local PLACEHOLDER = "•"

---@type table<string, string>
local HL_BY_TYPE = {
	add = "BeastGitAdd",
	change = "BeastGitChange",
	delete = "BeastGitDelete",
	topdelete = "BeastGitTopDelete",
	changedelete = "BeastGitChangedelete",
}

---@param buf integer
---@param line_signs table<integer, { type: string }>
function M.place(buf, line_signs)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	api.nvim_buf_clear_namespace(buf, NS, 0, -1)
	for lnum, info in pairs(line_signs) do
		local hl = HL_BY_TYPE[info.type]
		if hl then
			pcall(api.nvim_buf_set_extmark, buf, NS, lnum - 1, 0, {
				sign_text = PLACEHOLDER,
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
