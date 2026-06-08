--- Action functions for the autopairs engine.
---
--- Each action takes a `ctx` table assembled by `keymap.lua` and returns the
--- keystroke string that the `<expr>` mapping will replay. Returning a string
--- (rather than calling `nvim_feedkeys` ourselves) is what lets the actions
--- participate in undo, dot-repeat, and macros transparently.
---
--- All functions are pure with respect to module state. Side effects (cursor
--- moves, text insertion) happen via Neovim's keystroke replay of the
--- returned string.

local config = require("beast.libs.autopairs.config")
local pairs_mod = require("beast.libs.autopairs.pairs")
local skip = require("beast.libs.autopairs.skip")

local M = {}

-- Pre-decode the termcodes we hand back so we don't pay the cost per keystroke.
local KEY_LEFT = vim.api.nvim_replace_termcodes("<Left>", true, true, true)
local KEY_RIGHT = vim.api.nvim_replace_termcodes("<Right>", true, true, true)
local KEY_BS = vim.api.nvim_replace_termcodes("<BS>", true, true, true)
local KEY_BS_DEL = vim.api.nvim_replace_termcodes("<BS><Del>", true, true, true)
local KEY_CR = vim.api.nvim_replace_termcodes("<CR>", true, true, true)
local KEY_CR_INSIDE = vim.api.nvim_replace_termcodes("<CR><C-o>O", true, true, true)

--- Check both buffer-local and global disable flags.
---@return boolean
local function is_disabled()
	return vim.b.beast_autopairs_disable == true or vim.g.beast_autopairs_disable == true
end

--- Open action — insert the literal opener, then `<close><Left>` if and only
--- if (a) no skip rule vetoes and (b) the neighborhood pattern matches. A
--- skip rule may also return an override keystroke string (used by the
--- markdown fence rule).
---
---@param ctx { open: string, close: string, neigh_pattern: string, before: string, after: string, line: string, before_full: string, row: integer, col: integer }
---@return string keystrokes
function M.open(ctx)
	if is_disabled() then
		return ctx.open
	end
	local skipped, override = skip.should_skip(config.get(), ctx)
	if override then
		return override
	end
	if skipped then
		return ctx.open
	end
	if pairs_mod.neigh_matches(ctx.neigh_pattern, ctx.before, ctx.after) then
		return ctx.open .. ctx.close .. KEY_LEFT
	end
	return ctx.open
end

--- Close action — jump over an existing closer, else insert it literally.
---
---@param ctx { close: string, after: string }
---@return string keystrokes
function M.close(ctx)
	if is_disabled() then
		return ctx.close
	end
	if ctx.after == ctx.close then
		return KEY_RIGHT
	end
	return ctx.close
end

--- Closeopen action (symmetric pairs only) — jump over if next char equals
--- the close, otherwise delegate to `open`.
---
---@param ctx { open: string, close: string, neigh_pattern: string, before: string, after: string }
---@return string keystrokes
function M.closeopen(ctx)
	if is_disabled() then
		return ctx.open
	end
	if ctx.after == ctx.close then
		return KEY_RIGHT
	end
	return M.open(ctx)
end

--- Backspace action — delete the whole pair if the cursor sits between an
--- `open`/`close` from any registered pair; otherwise behave as plain `<BS>`.
---
---@param ctx { before: string, after: string, cfg: Beast.Autopairs.Config }
---@return string keystrokes
function M.bs(ctx)
	if is_disabled() then
		return KEY_BS
	end
	for open_char, spec in pairs_mod.iter_active(ctx.cfg) do
		if ctx.before == open_char and ctx.after == spec.close then
			return KEY_BS_DEL
		end
	end
	return KEY_BS
end

--- Carriage-return action — when between an `open`/`close`, split into three
--- lines with the cursor on the indented middle line. Otherwise plain `<CR>`.
---
--- Implementation: `<CR><C-o>O` inserts a newline (cursor on a blank line),
--- then `<C-o>O` opens a new line above in normal mode — Neovim handles
--- indentation per the active 'indentexpr'/'cindent' rules.
---
---@param ctx { before: string, after: string, cfg: Beast.Autopairs.Config }
---@return string keystrokes
function M.cr(ctx)
	if is_disabled() then
		return KEY_CR
	end
	for open_char, spec in pairs_mod.iter_active(ctx.cfg) do
		if ctx.before == open_char and ctx.after == spec.close then
			return KEY_CR_INSIDE
		end
	end
	return KEY_CR
end

return M
