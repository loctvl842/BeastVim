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

local MIN_SIZE = 1

-- ── Public ─────────────────────────────────────────────────────────

---Find the indent scope around a position using indent-based detection.
---Must be called inside `nvim_buf_call` for the target buffer.
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

return M
