-- Extmark sign placement for hunk markers.
--
-- Two namespaces (both classified as "git" by statuscolumn):
--   `beast_git_signs_unstaged` — base (index) vs buffer (priority 6)
--   `beast_git_signs_staged`   — head vs base       (priority 5)
--
-- Unstaged wins on overlap because its priority is higher: while the user
-- is editing on top of a staged region, the live edit colour takes over.
--
-- Two namespaces (not one) lets us clear and re-place each tier
-- independently — staged signs only change on stage/unstage/commit, not on
-- every keystroke.
--
-- ── Contract with statuscolumn ───────────────────────────────────────────
-- Each extmark carries:
--   sign_text      = "•"   (placeholder; see below)
--   sign_hl_group  = `BeastGit<Type>` for unstaged,
--                    `BeastGitStaged<Type>` for staged
--                    (Add | Change | Delete | TopDelete | Changedelete)
--
-- IMPORTANT — `BeastGit*` and `BeastGitStaged*` exist ONLY as routing tags
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
--   :hi BeastStcGitStagedAdd guifg=...   (desaturated variant)

local api = vim.api

local M = {}

local NS_UNSTAGED = api.nvim_create_namespace("beast_git_signs_unstaged")
local NS_STAGED = api.nvim_create_namespace("beast_git_signs_staged")

M.namespaces = { unstaged = NS_UNSTAGED, staged = NS_STAGED }

local PLACEHOLDER = "•"
local PRIORITY_UNSTAGED = 6
local PRIORITY_STAGED = 5

---@type table<string, string>
local HL_UNSTAGED = {
	add = "BeastGitAdd",
	change = "BeastGitChange",
	delete = "BeastGitDelete",
	topdelete = "BeastGitTopDelete",
	changedelete = "BeastGitChangedelete",
}

---@type table<string, string>
local HL_STAGED = {
	add = "BeastGitStagedAdd",
	change = "BeastGitStagedChange",
	delete = "BeastGitStagedDelete",
	topdelete = "BeastGitStagedTopDelete",
	changedelete = "BeastGitStagedChangedelete",
}

---@param buf integer
---@param ns integer
---@param hl_by_type table<string, string>
---@param priority integer
---@param line_signs table<integer, { type: string }>
local function place_tier(buf, ns, hl_by_type, priority, line_signs)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for lnum, info in pairs(line_signs) do
		local hl = hl_by_type[info.type]
		if hl then
			pcall(api.nvim_buf_set_extmark, buf, ns, lnum - 1, 0, {
				sign_text = PLACEHOLDER,
				sign_hl_group = hl,
				priority = priority,
			})
		end
	end
end

---@param buf integer
---@param line_signs table<integer, { type: string }>
function M.place_unstaged(buf, line_signs)
	place_tier(buf, NS_UNSTAGED, HL_UNSTAGED, PRIORITY_UNSTAGED, line_signs)
end

---@param buf integer
---@param line_signs table<integer, { type: string }>
function M.place_staged(buf, line_signs)
	place_tier(buf, NS_STAGED, HL_STAGED, PRIORITY_STAGED, line_signs)
end

---@param buf integer
function M.clear(buf)
	if api.nvim_buf_is_valid(buf) then
		api.nvim_buf_clear_namespace(buf, NS_UNSTAGED, 0, -1)
		api.nvim_buf_clear_namespace(buf, NS_STAGED, 0, -1)
	end
end

return M
