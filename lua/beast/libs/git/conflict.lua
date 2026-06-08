-- Merge-conflict highlighter (VSCode/JetBrains-style).
--
-- Each side of a conflict is painted as one continuous coloured band — the
-- marker line shares the block's hue at a stronger saturation, the same way
-- IDEs cap a conflict region. A trailing virt_text label on each header
-- makes it obvious which side is which without having to read the ref name.
--
--   <<<<<<< HEAD            ── ConflictOursMarker      + "(Current Change)"
--   ours block …            ── ConflictOurs
--   ||||||| merged common   ── ConflictBaseMarker      + "(Common Ancestor)"
--   base block …            ── ConflictBase            (diff3 only)
--   =======                 ── ConflictSeparator       (neutral)
--   theirs block …          ── ConflictTheirs
--   >>>>>>> branch          ── ConflictTheirsMarker    + "(Incoming Change)"

local api = vim.api

local M = {}

local NS = api.nvim_create_namespace("beast_git_conflict")

M.namespace = NS

local HL_OURS = "BeastGitConflictOurs"
local HL_OURS_MARK = "BeastGitConflictOursMarker"
local HL_BASE = "BeastGitConflictBase"
local HL_BASE_MARK = "BeastGitConflictBaseMarker"
local HL_THEIRS = "BeastGitConflictTheirs"
local HL_THEIRS_MARK = "BeastGitConflictTheirsMarker"
local HL_SEP = "BeastGitConflictSeparator"
local HL_LABEL = "BeastGitConflictLabel"

local LABEL_OURS = "  ← Current Change"
local LABEL_BASE = "  ← Common Ancestor"
local LABEL_THEIRS = "  ← Incoming Change"

---@param buf integer
---@param lnum0 integer    0-based line index of the marker line
---@param hl string        full-line highlight group for the marker
---@param label string?    optional virt_text appended at end of line
local function paint_marker(buf, lnum0, hl, label)
	local opts = {
		line_hl_group = hl,
		priority = 200,
	}
	if label then
		opts.virt_text = { { label, HL_LABEL } }
		opts.virt_text_pos = "eol"
		opts.hl_mode = "combine"
	end
	pcall(api.nvim_buf_set_extmark, buf, NS, lnum0, 0, opts)
end

---@param buf integer
---@param start0 integer  0-based, inclusive
---@param end0 integer    0-based, inclusive
---@param hl string
local function paint_block(buf, start0, end0, hl)
	if end0 < start0 then
		return
	end
	for l = start0, end0 do
		pcall(api.nvim_buf_set_extmark, buf, NS, l, 0, {
			line_hl_group = hl,
			priority = 199,
		})
	end
end

--- Scan `buf` for conflict markers and (re-)paint highlights.
--- Idempotent: clears the namespace first.
---@param buf integer
function M.scan(buf)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	api.nvim_buf_clear_namespace(buf, NS, 0, -1)

	local lines = api.nvim_buf_get_lines(buf, 0, -1, false)

	local ours_start, base_start, theirs_start = nil, nil, nil

	for i, line in ipairs(lines) do
		local lnum0 = i - 1
		if line:match("^<<<<<<<? ") or line == "<<<<<<<" then
			-- Abandon any half-parsed conflict and restart here.
			ours_start = lnum0 + 1
			base_start, theirs_start = nil, nil
			paint_marker(buf, lnum0, HL_OURS_MARK, LABEL_OURS)
		elseif ours_start and (line:match("^|||||||") or line == "|||||||") then
			-- Diff3 common-ancestor header — ours block ends one line above.
			paint_block(buf, ours_start, lnum0 - 1, HL_OURS)
			base_start = lnum0 + 1
			paint_marker(buf, lnum0, HL_BASE_MARK, LABEL_BASE)
		elseif ours_start and (line:match("^=======$") or line == "=======") then
			if base_start then
				paint_block(buf, base_start, lnum0 - 1, HL_BASE)
			else
				paint_block(buf, ours_start, lnum0 - 1, HL_OURS)
			end
			theirs_start = lnum0 + 1
			paint_marker(buf, lnum0, HL_SEP, nil)
		elseif theirs_start and (line:match("^>>>>>>>? ") or line == ">>>>>>>") then
			paint_block(buf, theirs_start, lnum0 - 1, HL_THEIRS)
			paint_marker(buf, lnum0, HL_THEIRS_MARK, LABEL_THEIRS)
			ours_start, base_start, theirs_start = nil, nil, nil
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
