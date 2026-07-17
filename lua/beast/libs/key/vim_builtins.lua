-- =============================================================================
-- Vim built-in motion / operator / textobject vocabulary
-- =============================================================================
-- Registers label-only entries (rhs = nil) into `Key.managed` so the hint
-- popup can surface vim core verbs for discoverability.
--
-- These are NOT real keymaps — `safe_set` with nil rhs only writes to the
-- registry. Pressing the sequence still resolves through Neovim's normal
-- keymap/operator path via the hint's verbatim feed.
--
-- Why hardcoded (and not derived):
--   Neovim exposes NO API for built-in motions/operators. They live in C as
--   keymap handlers — never registered, never queryable. Which-key, vim-which-key,
--   and every similar plugin hardcodes the same vocabulary. There is no
--   alternative.
--
-- Conflict handling:
--   If a Beast keymap (or user keymap registered via safe_set) already owns the
--   same lhs+mode, the registry entry is kept and we skip — Beast keymaps win.
-- =============================================================================

local core = require("beast.libs.key.core")

local M = {}

---@class Beast.Key.VimBuiltin
---@field [1] string                -- lhs
---@field [2] string?               -- desc (omit for intermediate prefix labels)
---@field mode? string|string[]     -- defaults to {"n","x","o"}
---@field group? string             -- e.g. "+inside" for prefix nodes

local OP = { "n", "x" }
local MOTION = { "n", "x", "o" }
local NORMAL = { "n" }

---@type Beast.Key.VimBuiltin[]
local entries = {
	-- ── Change operator ────────────────────────────────────────────────────
	{ "cc", "change line", mode = NORMAL },
	{ "cw", "change word", mode = NORMAL },
	{ "ce", "change to word end", mode = NORMAL },
	{ "C", "change to EOL", mode = OP },
	{ "s", "subst char", mode = OP },
	{ "S", "subst line", mode = OP },
	{ "ci", nil, mode = NORMAL, group = "+inside" },
	{ "ca", nil, mode = NORMAL, group = "+around" },
	{ "ciw", "change inner word", mode = NORMAL },
	{ "ciW", "change inner WORD", mode = NORMAL },
	{ "caw", "change a word", mode = NORMAL },
	{ "caW", "change a WORD", mode = NORMAL },
	{ "cit", "change inner tag", mode = NORMAL },
	{ "cat", "change a tag", mode = NORMAL },
	{ "cip", "change inner paragraph", mode = NORMAL },
	{ "cap", "change a paragraph", mode = NORMAL },
	{ 'ci"', 'change inside "', mode = NORMAL },
	{ 'ca"', 'change around "', mode = NORMAL },
	{ "ci'", "change inside '", mode = NORMAL },
	{ "ca'", "change around '", mode = NORMAL },
	{ "ci`", "change inside `", mode = NORMAL },
	{ "ci(", "change inside ()", mode = NORMAL },
	{ "ci{", "change inside {}", mode = NORMAL },
	{ "ci[", "change inside []", mode = NORMAL },
	{ "ci<", "change inside <>", mode = NORMAL },

	-- ── Delete operator ────────────────────────────────────────────────────
	{ "dd", "delete line", mode = NORMAL },
	{ "dw", "delete word", mode = NORMAL },
	{ "de", "delete to word end", mode = NORMAL },
	{ "D", "delete to EOL", mode = OP },
	{ "x", "delete char", mode = OP },
	{ "X", "delete char before", mode = OP },
	{ "di", nil, mode = NORMAL, group = "+inside" },
	{ "da", nil, mode = NORMAL, group = "+around" },
	{ "diw", "delete inner word", mode = NORMAL },
	{ "daw", "delete a word", mode = NORMAL },
	{ "dit", "delete inner tag", mode = NORMAL },
	{ "dip", "delete inner paragraph", mode = NORMAL },
	{ 'di"', 'delete inside "', mode = NORMAL },
	{ "di'", "delete inside '", mode = NORMAL },
	{ "di(", "delete inside ()", mode = NORMAL },
	{ "di{", "delete inside {}", mode = NORMAL },
	{ "di[", "delete inside []", mode = NORMAL },

	-- ── Yank ───────────────────────────────────────────────────────────────
	{ "yy", "yank line", mode = NORMAL },
	{ "yw", "yank word", mode = NORMAL },
	{ "Y", "yank to EOL", mode = OP },
	{ "yi", nil, mode = NORMAL, group = "+inside" },
	{ "ya", nil, mode = NORMAL, group = "+around" },
	{ "yiw", "yank inner word", mode = NORMAL },
	{ "yip", "yank inner paragraph", mode = NORMAL },

	-- ── Paste / clipboard ──────────────────────────────────────────────────
	{ "p", "paste after", mode = OP },
	{ "P", "paste before", mode = OP },
	{ "gp", "paste, cursor after", mode = OP },
	{ "gP", "paste before, cursor after", mode = OP },

	-- ── Indent ─────────────────────────────────────────────────────────────
	{ ">>", "indent line right", mode = NORMAL },
	{ "<<", "indent line left", mode = NORMAL },
	{ "==", "auto indent line", mode = NORMAL },

	-- ── g family ───────────────────────────────────────────────────────────
	{ "gg", "first line", mode = MOTION },
	{ "G", "last line", mode = MOTION },
	{ "ge", "back to word end", mode = MOTION },
	{ "gE", "back to WORD end", mode = MOTION },
	{ "gd", "goto definition (local)", mode = NORMAL },
	{ "gD", "goto definition (global)", mode = NORMAL },
	{ "gf", "go to file under cursor", mode = NORMAL },
	{ "gi", "go to last insert", mode = NORMAL },
	{ "gn", "search forwards and select", mode = NORMAL },
	{ "gN", "search backwards and select", mode = NORMAL },
	{ "gt", "go to next tab page", mode = NORMAL },
	{ "gT", "go to previous tab page", mode = NORMAL },
	{ "gv", "last visual selection", mode = NORMAL },
	{ "gx", "open file with system app", mode = NORMAL },
	{ "gu", "lowercase (motion)", mode = NORMAL },
	{ "gU", "uppercase (motion)", mode = NORMAL },
	{ "g~", "swap case (motion)", mode = NORMAL },
	{ "gq", "format (motion)", mode = NORMAL },
	{ "gw", "format (keep cursor)", mode = NORMAL },
	{ "g0", "first char of screen line", mode = MOTION },
	{ "g$", "last char of screen line", mode = MOTION },
	{ "g_", "last non-blank char", mode = MOTION },
	{ "g%", "cycle backwards through results", mode = NORMAL },
	{ "g,", "go to [count] newer position in change list", mode = NORMAL },
	{ "g;", "go to [count] older position in change list", mode = NORMAL },
	{ "g&", "repeat last :s on all lines", mode = NORMAL },
	{ "ga", "show char info", mode = NORMAL },
	{ "gJ", "join lines (no spaces)", mode = NORMAL },
	{ "gc", nil, mode = { "n", "x" }, group = "comment" },
	{ "gcc", "toggle comment line", mode = NORMAL },
	{ "gco", "add comment below", mode = NORMAL },
	{ "gcO", "add comment above", mode = NORMAL },
	{ "gcA", "add comment at end of line", mode = NORMAL },

	-- ── z family (folds + scroll) ──────────────────────────────────────────
	{ "zz", "center cursor line", mode = OP },
	{ "zt", "cursor line at top", mode = OP },
	{ "zb", "cursor line at bottom", mode = OP },
	{ "za", "toggle fold", mode = OP },
	{ "zA", "toggle fold recursive", mode = OP },
	{ "zo", "open fold", mode = OP },
	{ "zO", "open fold recursive", mode = OP },
	{ "zc", "close fold", mode = OP },
	{ "zC", "close fold recursive", mode = OP },
	{ "zR", "open all folds", mode = OP },
	{ "zM", "close all folds", mode = OP },
	{ "zf", "create fold (motion)", mode = NORMAL },
	{ "zd", "delete fold", mode = NORMAL },
	{ "zE", "delete all folds", mode = NORMAL },

	-- ── [ / ] family ───────────────────────────────────────────────────────
	{ "[{", "prev unmatched {", mode = MOTION },
	{ "]}", "next unmatched }", mode = MOTION },
	{ "[(", "prev unmatched (", mode = MOTION },
	{ "])", "next unmatched )", mode = MOTION },
	{ "[m", "prev method start", mode = MOTION },
	{ "]m", "next method start", mode = MOTION },
	{ "[M", "prev method end", mode = MOTION },
	{ "]M", "next method end", mode = MOTION },
	{ "[[", "prev section start", mode = MOTION },
	{ "]]", "next section start", mode = MOTION },

	-- ── <C-w> windows ──────────────────────────────────────────────────────
	{ "<C-w>h", "go left window", mode = NORMAL },
	{ "<C-w>j", "go down window", mode = NORMAL },
	{ "<C-w>k", "go up window", mode = NORMAL },
	{ "<C-w>l", "go right window", mode = NORMAL },
	{ "<C-w>w", "next window", mode = NORMAL },
	{ "<C-w>p", "previous window", mode = NORMAL },
	{ "<C-w>s", "split horizontal", mode = NORMAL },
	{ "<C-w>v", "split vertical", mode = NORMAL },
	{ "<C-w>q", "close window", mode = NORMAL },
	{ "<C-w>o", "only this window", mode = NORMAL },
	{ "<C-w>=", "equalize sizes", mode = NORMAL },
	{ "<C-w>_", "max height", mode = NORMAL },
	{ "<C-w>|", "max width", mode = NORMAL },
	{ "<C-w>x", "swap with next", mode = NORMAL },
	{ "<C-w>T", "move to new tab", mode = NORMAL },

	-- ── Marks / registers / macros (intermediate labels) ───────────────────
	{ "q", nil, mode = NORMAL, group = "+record macro" },
	{ "@", nil, mode = OP, group = "+run macro" },
	{ "m", nil, mode = NORMAL, group = "+set mark" },
	{ "'", nil, mode = MOTION, group = "+jump to mark line" },
	{ "`", nil, mode = MOTION, group = "+jump to mark pos" },
	{ '"', nil, mode = OP, group = "+register" },
}

---Register all built-in entries into the keymap registry.
---Skips any lhs+mode pair that is already managed (user keymaps win).
function M.register()
	for _, e in ipairs(entries) do
		local lhs = e[1]
		local desc = e[2]
		local modes = e.mode or MOTION
		if type(modes) == "string" then
			modes = { modes }
		end
		for _, mode in ipairs(modes) do
			local id = vim.api.nvim_replace_termcodes(lhs, true, true, true) .. " (" .. mode .. ")"
			if core.managed[id] == nil then
				core.safe_set(mode, lhs, nil, { desc = desc or "", group = e.group })
			end
		end
	end
end

return M
