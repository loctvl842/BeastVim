local config = require("beast.libs.indent.config")

local M = {}

-- ── Scope type lookup ──────────────────────────────────────────────

---@type table<string, boolean>?
local scope_set

---@return table<string, boolean>
local function get_scope_set()
	if scope_set then return scope_set end
	scope_set = {}
	for _, t in ipairs(config.scope.treesitter.scope_types) do
		scope_set[t] = true
	end
	return scope_set
end

--- Invalidate cached scope_set (call after config.setup).
function M.invalidate()
	scope_set = nil
end

-- ── Helpers ────────────────────────────────────────────────────────

---Compute leading indent of a line string (pure Lua, no vim.fn).
---@param s string
---@param sw integer shiftwidth / tabstop for tab expansion
---@return integer
local function str_indent(s, sw)
	local col = 0
	for i = 1, #s do
		local c = s:byte(i)
		if c == 9 then -- tab
			col = col + sw - (col % sw)
		elseif c == 32 then -- space
			col = col + 1
		else
			break
		end
	end
	return col
end

-- ── Detection ──────────────────────────────────────────────────────

---Walk up from node to find the innermost scope-defining ancestor.
---@param node TSNode
---@param root TSNode
---@return TSNode?
local function find_scope_node(node, root)
	local types = get_scope_set()
	local current = node
	while current and current ~= root do
		if types[current:type()] then
			return current
		end
		current = current:parent()
	end
	return nil
end

---Collect contiguous segments from pre-fetched lines (pure Lua, no vim.fn).
---@param buf integer
---@param lines string[] 1-indexed body lines (lines[1] = body_from)
---@param body_from integer 1-indexed first body line
---@param body_indent integer minimum indent for body lines
---@param sw integer shiftwidth for tab expansion
---@return Beast.Indent.Scope[]
local function collect_segments(buf, lines, body_from, body_indent, sw)
	local segments = {}
	local seg_from = nil

	for i = 1, #lines do
		local s = lines[i]
		local is_blank = s:find("%S") == nil
		local indent = is_blank and body_indent or str_indent(s, sw)

		if indent >= body_indent then
			if not seg_from then
				seg_from = body_from + i - 1
			end
		else
			if seg_from then
				segments[#segments + 1] = { buf = buf, from = seg_from, to = body_from + i - 2, indent = body_indent }
				seg_from = nil
			end
		end
	end

	if seg_from then
		segments[#segments + 1] = { buf = buf, from = seg_from, to = body_from + #lines - 1, indent = body_indent }
	end

	return segments
end

---Find scope using treesitter at the given position.
---Must be called inside `nvim_buf_call` for the target buffer.
---@param buf integer
---@param pos {[1]: integer, [2]: integer} 1-indexed line, 0-indexed col
---@return Beast.Indent.Scope[]?
---@type table
local parser_opts = { error = false }

function M.find(buf, pos)
	-- Fast parser check: avoid pcall overhead on repeat calls
	local parser = vim.treesitter.get_parser(buf, nil, parser_opts)
	-- stylua: ignore
	if not parser then return nil end

	local line = pos[1]
	local total = vim.api.nvim_buf_line_count(buf)
	-- stylua: ignore
	if line < 1 or line > total then return nil end

	-- Fetch current line to check blank (avoids vim.fn for common non-blank case)
	local cur_text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
	local resolved, resolved_text

	if cur_text:find("%S") then
		resolved = line
		resolved_text = cur_text
	else
		-- Blank line: resolve to nearest non-blank (2 vim.fn calls worst case)
		resolved = vim.fn.nextnonblank(line)
		if resolved == 0 then resolved = vim.fn.prevnonblank(line) end
		-- stylua: ignore
		if resolved == 0 then return nil end
		resolved_text = vim.api.nvim_buf_get_lines(buf, resolved - 1, resolved, false)[1]
	end

	local first_col = (resolved_text:find("%S") or 1) - 1

	-- Direct tree API: skip vim.treesitter.get_node() overhead
	parser:parse()
	local trees = parser:trees()
	-- stylua: ignore
	if not trees or #trees == 0 then return nil end
	local root = trees[1]:root()
	local r = resolved - 1 -- 0-indexed
	local node = root:named_descendant_for_range(r, first_col, r, first_col)
	-- stylua: ignore
	if not node then return nil end

	local scope_node = find_scope_node(node, root)
	-- stylua: ignore
	if not scope_node then return nil end

	-- Node range (0-indexed) → 1-indexed
	local node_from, _, node_to = scope_node:range()
	local from = node_from + 1
	local to = node_to + 1

	-- Body is between the edges
	local body_from = from + 1
	local body_to = to - 1
	-- stylua: ignore
	if body_from > body_to then return nil end

	-- Batch-fetch only body lines (single API call)
	local body_lines = vim.api.nvim_buf_get_lines(buf, body_from - 1, body_to, false)

	local sw = vim.bo[buf].shiftwidth
	if sw == 0 then sw = vim.bo[buf].tabstop end

	-- Find first non-blank body line indent (pure Lua)
	local first_body_indent = nil
	for i = 1, #body_lines do
		if body_lines[i]:find("%S") then
			first_body_indent = str_indent(body_lines[i], sw)
			break
		end
	end
	-- stylua: ignore
	if not first_body_indent or first_body_indent <= 0 then return nil end

	local segments = collect_segments(buf, body_lines, body_from, first_body_indent, sw)
	-- stylua: ignore
	if #segments == 0 then return nil end

	return segments
end

return M
