--- Smart veto layer for the autopairs engine.
---
--- Each rule is a pure function that inspects the keystroke context and
--- returns whether to suppress the default `open` action. Rules compose via
--- `should_skip()` — first rule that votes "skip" wins.
---
--- Some rules (currently only `markdown`) return an *override* keystroke
--- string instead of just suppressing — this lets us expand `` ``` `` into a
--- full code fence without abandoning the `<expr>` mapping contract.

local M = {}

local KEY_UP = vim.api.nvim_replace_termcodes("<Up>", true, true, true)

-- =============================================================================
-- Individual rules
-- =============================================================================

--- Rule 1 — `skip_next`: bail when the char immediately right of the cursor
--- matches the configured Lua pattern (e.g. alnum, quote, dot, dollar).
---
---@param cfg Beast.Autopairs.Config
---@param ctx { after: string }
---@return boolean
local function skip_next(cfg, ctx)
	if not cfg.skip_next then
		return false
	end
	if ctx.after == "" then
		return false
	end
	return ctx.after:match(cfg.skip_next) ~= nil
end

--- Rule 2 — `skip_ts`: bail when the cursor's treesitter capture (one char
--- *behind* the cursor — that's the byte we're appending after) matches any
--- name in the configured list. `pcall`-wrapped because buffers without an
--- active parser raise.
---
---@param cfg Beast.Autopairs.Config
---@param ctx { row: integer, col: integer }
---@return boolean
local function skip_ts(cfg, ctx)
	if not cfg.skip_ts or #cfg.skip_ts == 0 then
		return false
	end
	local lookup_col = math.max(ctx.col - 1, 0)
	local ok, captures = pcall(vim.treesitter.get_captures_at_pos, 0, ctx.row - 1, lookup_col)
	if not ok then
		return false
	end
	for _, cap in ipairs(captures) do
		for _, name in ipairs(cfg.skip_ts) do
			if cap.capture == name then
				return true
			end
		end
	end
	return false
end

--- Rule 3 — `skip_unbalanced`: when the next char already equals the close
--- char AND open ≠ close (i.e. brackets, not quotes), count opens/closes on
--- the current line. If closers exceed openers, the user is balancing — let
--- the literal char through.
---
---@param cfg Beast.Autopairs.Config
---@param ctx { open: string, close: string, after: string, line: string }
---@return boolean
local function skip_unbalanced(cfg, ctx)
	if not cfg.skip_unbalanced then
		return false
	end
	if ctx.after ~= ctx.close or ctx.close == ctx.open then
		return false
	end
	local _, count_open = ctx.line:gsub(vim.pesc(ctx.open), "")
	local _, count_close = ctx.line:gsub(vim.pesc(ctx.close), "")
	return count_close > count_open
end

--- Rule 4 — `markdown`: when typing `` ` `` in a markdown buffer with two
--- backticks already on the line, expand the third into a full fenced code
--- block and place the cursor inside.
---
--- Returns the override keystroke string when fired.
---
---@param cfg Beast.Autopairs.Config
---@param ctx { open: string, before_full: string }
---@return string?
local function markdown_fence(cfg, ctx)
	if not cfg.markdown or ctx.open ~= "`" then
		return nil
	end
	if vim.bo.filetype ~= "markdown" then
		return nil
	end
	if not ctx.before_full:match("^%s*``$") then
		return nil
	end
	return "`\n```" .. KEY_UP
end

-- =============================================================================
-- Composer
-- =============================================================================

--- Evaluate all skip rules. Returns `(skipped, override)`:
---   * `skipped = true, override = nil`     → emit just the literal `ctx.open`
---   * `skipped = true, override = "..."`   → emit the override keystrokes
---   * `skipped = false`                    → fall through to default pairing
---
---@param cfg Beast.Autopairs.Config
---@param ctx table  built by actions.lua: open, close, line, before, after, before_full, row, col
---@return boolean skipped
---@return string? override
function M.should_skip(cfg, ctx)
	-- Markdown fence runs first — its match is highly specific and it returns
	-- an override that the caller MUST honor exactly.
	local override = markdown_fence(cfg, ctx)
	if override then
		return true, override
	end

	if skip_next(cfg, ctx) then
		return true, nil
	end
	if skip_unbalanced(cfg, ctx) then
		return true, nil
	end
	if skip_ts(cfg, ctx) then
		return true, nil
	end

	return false, nil
end

return M
