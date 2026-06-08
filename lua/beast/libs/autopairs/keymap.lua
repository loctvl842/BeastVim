--- Install / uninstall the autopairs `<expr>` mappings.
---
--- Idempotency: we keep a registry of `{mode, lhs}` we installed; install
--- skips entries already in the registry; uninstall walks the registry and
--- deletes each entry, then empties it.

local Key = require("beast.libs.key")
local actions = require("beast.libs.autopairs.actions")
local pairs_mod = require("beast.libs.autopairs.pairs")

local M = {}

-- =============================================================================
-- Context builders
-- =============================================================================

--- Build the per-keystroke context for insert mode.
---@return { line: string, col: integer, before: string, after: string, before_full: string, row: integer }
local function insert_ctx()
	local line = vim.api.nvim_get_current_line()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	return {
		line = line,
		row = row,
		col = col,
		before = col > 0 and line:sub(col, col) or "",
		after = line:sub(col + 1, col + 1),
		before_full = line:sub(1, col),
	}
end

--- Build the per-keystroke context for cmdline mode.
---@return { line: string, col: integer, before: string, after: string, before_full: string, row: integer }
local function cmdline_ctx()
	local line = vim.fn.getcmdline()
	-- `getcmdpos()` is 1-based and points at the byte the next char will be
	-- inserted at; subtract 1 to align with insert-mode `col` semantics.
	local col = vim.fn.getcmdpos() - 1
	return {
		line = line,
		row = 1,
		col = col,
		before = col > 0 and line:sub(col, col) or "",
		after = line:sub(col + 1, col + 1),
		before_full = line:sub(1, col),
	}
end

---@param mode string  "i" or "c"
local function build_ctx(mode)
	return mode == "c" and cmdline_ctx() or insert_ctx()
end

-- =============================================================================
-- Mode resolution
-- =============================================================================

---@param cfg Beast.Autopairs.Config
---@return string[]  list of Neovim mode short-codes for pair keys
local function pair_modes(cfg)
	local modes = {}
	if cfg.modes.insert then
		modes[#modes + 1] = "i"
	end
	if cfg.modes.command then
		modes[#modes + 1] = "c"
	end
	if cfg.modes.terminal then
		modes[#modes + 1] = "t"
	end
	return modes
end

-- =============================================================================
-- Install / uninstall
-- =============================================================================

local function set_expr(mode, lhs, rhs_fn, desc, registry)
	local key = mode .. ":" .. lhs
	if registry[key] then
		return
	end
	-- replace_keycodes = false: action functions return pre-decoded raw bytes
	-- (via nvim_replace_termcodes), not `<CR>`-style literals.
	--
	-- silent: insert mode only. In cmdline mode, `silent = true` suppresses
	-- the cmdline echo so the typed characters never appear visually — even
	-- though they *are* in the buffer (`:` would show empty but `<CR>` still
	-- runs `()` and reports `E492`).
	Key.safe_set(mode, lhs, rhs_fn, {
		expr = true,
		replace_keycodes = false,
		silent = mode ~= "c",
		noremap = true,
		desc = desc,
		group = "Autopairs",
	})
	registry[key] = { mode = mode, lhs = lhs }
end

--- Install mappings for every configured pair plus the global `<BS>`/`<CR>`
--- handlers (insert mode only). Records each `{mode, lhs}` in `registry` for
--- a later `uninstall(registry)`.
---
---@param cfg Beast.Autopairs.Config
---@param registry table<string, { mode: string, lhs: string }>
function M.install(cfg, registry)
	local modes = pair_modes(cfg)

	for open_char, spec in pairs_mod.iter_active(cfg) do
		local close_char = spec.close
		local neigh = spec.neigh_pattern
		local symmetric = pairs_mod.is_symmetric(spec, open_char)

		for _, mode in ipairs(modes) do
			if symmetric then
				set_expr(mode, open_char, function()
					local c = build_ctx(mode)
					c.open = open_char
					c.close = close_char
					c.neigh_pattern = neigh
					return actions.closeopen(c)
				end, ("Autopair %s%s"):format(open_char, close_char), registry)
			else
				set_expr(mode, open_char, function()
					local c = build_ctx(mode)
					c.open = open_char
					c.close = close_char
					c.neigh_pattern = neigh
					return actions.open(c)
				end, ("Autopair open %s"):format(open_char), registry)

				set_expr(mode, close_char, function()
					local c = build_ctx(mode)
					c.close = close_char
					return actions.close(c)
				end, ("Autopair close %s"):format(close_char), registry)
			end
		end
	end

	-- BS / CR are insert-mode only — they exist to clean up after `open`,
	-- and cmdline already has reasonable defaults for both.
	if cfg.modes.insert then
		set_expr("i", "<BS>", function()
			local c = insert_ctx()
			c.cfg = cfg
			return actions.bs(c)
		end, "Autopair smart <BS>", registry)

		set_expr("i", "<CR>", function()
			local c = insert_ctx()
			c.cfg = cfg
			return actions.cr(c)
		end, "Autopair smart <CR>", registry)
	end
end

--- Remove every mapping recorded in `registry` and empty it. Safe to call
--- when the registry is empty (no-op).
---
---@param registry table<string, { mode: string, lhs: string }>
function M.uninstall(registry)
	for key, entry in pairs(registry) do
		pcall(vim.keymap.del, entry.mode, entry.lhs)
		registry[key] = nil
	end
end

return M
