local config = require("beast.libs.indent.config")
local guide = require("beast.libs.indent.guide")

---@class Beast.Indent.Scope
---@field buf integer
---@field from integer 1-indexed top line
---@field to integer 1-indexed bottom line
---@field indent integer body indent column (0-based), used for drawing

---Per-window cached scopes (array of contiguous segments).
---@type table<integer, Beast.Indent.Scope[]?>
local active = {}

local debounce_timer = assert((vim.uv or vim.loop).new_timer())

local MIN_SIZE = 1

local M = {}

-- ── Detection helpers ──────────────────────────────────────────────

---@param line integer 1-indexed
---@return integer? indent, integer line
local function get_indent(line)
	local ret = vim.fn.indent(line)
	return ret == -1 and nil or ret, line
end

---Expand from a line up or down, skipping blanks, until indent drops below reference.
---@param line integer 1-indexed starting line
---@param indent integer reference indent level
---@param up boolean true = expand upward
---@return integer edge_line
local function expand(line, indent, up)
	local next = up and vim.fn.prevnonblank or vim.fn.nextnonblank
	while line do
		local i, l = get_indent(next(line + (up and -1 or 1)))
		if (i or 0) == 0 or i < indent or l == 0 then
			return line
		end
		line = l
	end
	return line
end

---Find the indent scope around a position.
---@param buf integer
---@param pos {[1]: integer, [2]: integer} 1-indexed line, 0-indexed col
---@return Beast.Indent.Scope[]?
function M.find(buf, pos)
	local line = pos[1]
	local indent, resolved_line = get_indent(line)
	local is_blank = vim.fn.prevnonblank(line) ~= line

	if is_blank then
		local prev_i = get_indent(vim.fn.prevnonblank(line - 1)) or 0
		local next_i = get_indent(vim.fn.nextnonblank(line + 1)) or 0
		indent = math.min(prev_i, next_i)
		-- stylua: ignore
		if indent <= 0 then return nil end
		if prev_i <= next_i then
			resolved_line = vim.fn.prevnonblank(line - 1)
		else
			resolved_line = vim.fn.nextnonblank(line + 1)
		end
	end

	-- stylua: ignore
	if not indent or resolved_line == 0 then return nil end

	-- Edge adjustment: only for non-blank lines.
	if not is_blank then
		if indent == 0 then
			-- Top-level: step in if the immediate next or previous line is deeper (no gap).
			local next_indent = vim.fn.indent(line + 1)
			local prev_indent = vim.fn.indent(line - 1)
			if next_indent > 0 then
				resolved_line = line + 1
				indent = next_indent
			elseif prev_indent > 0 then
				resolved_line = line - 1
				indent = prev_indent
			end
		else
			-- Indented: step into deeper block when on an edge line.
			local prev_i = get_indent(vim.fn.prevnonblank(resolved_line - 1))
			local next_i, next_l = get_indent(vim.fn.nextnonblank(resolved_line + 1))
			if (prev_i or 0) <= indent and (next_i or 0) > indent then
				-- Opening edge: next is deeper
				resolved_line = next_l
				indent = next_i
			elseif (next_i or 0) <= indent and (prev_i or 0) > indent then
				-- Closing edge: prev is deeper
				resolved_line = vim.fn.prevnonblank(resolved_line - 1)
				indent = prev_i
			end
		end
	end

	-- stylua: ignore
	if not indent or indent <= 0 then return nil end

	local scope = {
		buf = buf,
		from = expand(resolved_line, indent, true),
		to = expand(resolved_line, indent, false),
		indent = indent,
	}

	-- stylua: ignore
	if (scope.to - scope.from + 1) < MIN_SIZE then return nil end

	return { scope }
end

function M.debug()
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local pos = vim.api.nvim_win_get_cursor(win)
	---@type Beast.Indent.Scope[]?
	local scopes = vim.api.nvim_buf_call(buf, function()
		return M.find(buf, pos)
	end)
	print(vim.inspect(scopes))
end

-- ── Update helpers ──────────────────────────────────────────────────

---Compare two scope arrays for equality.
---@param a Beast.Indent.Scope[]?
---@param b Beast.Indent.Scope[]?
---@return boolean
local function scopes_eq(a, b)
	if not a or not b then return a == b end
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i].from ~= b[i].from or a[i].to ~= b[i].to or a[i].indent ~= b[i].indent then
			return false
		end
	end
	return true
end

---Get the full redraw range for a scope array (0-indexed, for nvim__redraw).
---@param scopes Beast.Indent.Scope[]
---@return integer from_0, integer to_1
local function redraw_range(scopes)
	local from = scopes[1].from
	local to = scopes[#scopes].to
	return math.max(0, from - 2), to
end

-- ── Update (debounced, called from autocmds) ───────────────────────

---@param is_excluded fun(buf: integer): boolean
function M.update(is_excluded)
	debounce_timer:stop()
	debounce_timer:start(
		config.scope.debounce,
		0,
		vim.schedule_wrap(function()
			local win = vim.api.nvim_get_current_win()
			local buf = vim.api.nvim_get_current_buf()

			if is_excluded(buf) then
				active[win] = nil
				return
			end

			local pos = vim.api.nvim_win_get_cursor(win)
			---@type Beast.Indent.Scope[]?
			local new_scopes = vim.api.nvim_buf_call(buf, function()
				return M.find(buf, pos)
			end)

			local prev = active[win]
			-- stylua: ignore
			if scopes_eq(prev, new_scopes) then return end

			active[win] = new_scopes

			if new_scopes then
				local f, t = redraw_range(new_scopes)
				vim.api.nvim__redraw({ win = win, range = { f, t }, flush = false })
			end
			if prev then
				local f, t = redraw_range(prev)
				vim.api.nvim__redraw({ win = win, range = { f, t }, flush = false })
			end
			vim.api.nvim__redraw({ flush = true })
		end)
	)
end

-- ── Draw (called from decoration provider) ─────────────────────────

---Draw the scope indicator for visible lines.
---@param buf integer
---@param ns integer namespace
---@param win integer
---@param top integer 1-indexed
---@param bottom integer 1-indexed
---@param leftcol integer
---@param sw integer
function M.draw(buf, ns, win, top, bottom, leftcol, sw)
	-- stylua: ignore
	if not config.scope.enabled then return end

	local scopes = active[win]
	-- stylua: ignore
	if not scopes then return end

	for _, scope in ipairs(scopes) do
		-- stylua: ignore
		if scope.buf ~= buf then goto continue end

		local col = scope.indent - sw - leftcol
		-- stylua: ignore
		if col < 0 then goto continue end

		local from = math.max(scope.from, top)
		local to = math.min(scope.to, bottom)
		local virt_text = { { config.scope.symbol, "BeastIndentScope" } }

		-- Underline on the line above the scope (the border/declaration line)
		local underline_line = scope.from - 1
		if config.scope.underline and underline_line >= top and underline_line <= bottom then
			local text = vim.api.nvim_buf_get_lines(buf, underline_line - 1, underline_line, false)[1]
			if text then
				local text_start = text:find("%S")
				if text_start then
					pcall(vim.api.nvim_buf_set_extmark, buf, ns, underline_line - 1, text_start - 1, {
						end_col = #text,
						hl_group = "BeastIndentScopeUnderline",
						hl_mode = "combine",
						priority = config.scope.priority + 1,
						strict = false,
						ephemeral = true,
					})
				end
			end
		end

		for line = from, to do
			local line_indent = guide.get_indent(buf, line, sw)
			if line_indent > col + leftcol then
				vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
					virt_text = virt_text,
					virt_text_pos = "overlay",
					virt_text_win_col = col,
					hl_mode = "combine",
					priority = config.scope.priority,
					ephemeral = true,
				})
			end
		end

		::continue::
	end
end

-- ── Cleanup ────────────────────────────────────────────────────────

function M.cleanup_win()
	for win in pairs(active) do
		if not vim.api.nvim_win_is_valid(win) then
			active[win] = nil
		end
	end
end

return M
