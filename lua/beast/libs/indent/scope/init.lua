local config = require("beast.libs.indent.config")
local guide = require("beast.libs.indent.guide")
local find_by_indent = require("beast.libs.indent.scope.indent").find
local find_by_treesitter = require("beast.libs.indent.scope.treesitter").find

---@class Beast.Indent.Scope
---@field buf integer
---@field from integer 1-indexed top line
---@field to integer 1-indexed bottom line
---@field indent integer body indent column (0-based), used for drawing

---Per-window cached scopes (array of contiguous segments).
---@type table<integer, Beast.Indent.Scope[]?>
local active = {}

local debounce_timer = assert((vim.uv or vim.loop).new_timer())

local M = {}

-- ── Detection dispatcher ───────────────────────────────────────────

---Find scope segments around a position.
---Tries treesitter first, falls back to indent-based detection.
---Must be called inside `nvim_buf_call` for the target buffer.
---@param buf integer
---@param pos {[1]: integer, [2]: integer} 1-indexed line, 0-indexed col
---@return Beast.Indent.Scope[]?
function M.find(buf, pos)
	if config.scope.treesitter.enabled then
		local result = find_by_treesitter(buf, pos)
		if result then return result end
	end
	return find_by_indent(buf, pos)
end

-- Expose strategies for testing
M.find_by_indent = find_by_indent
M.find_by_treesitter = find_by_treesitter

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

	for idx, scope in ipairs(scopes) do
		-- stylua: ignore
		if scope.buf ~= buf then goto continue end

		local col = scope.indent - sw - leftcol
		-- stylua: ignore
		if col < 0 then goto continue end

		local from = math.max(scope.from, top)
		local to = math.min(scope.to, bottom)
		local virt_text = { { config.scope.symbol, "BeastIndentScope" } }

		-- Underline only on the first segment's border (the declaration line)
		if idx == 1 then
			local underline_line = scope.from - 1
			local on_closed_fold = vim.fn.foldclosed(underline_line) ~= -1
			if config.scope.underline and not on_closed_fold and underline_line >= top and underline_line <= bottom then
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
