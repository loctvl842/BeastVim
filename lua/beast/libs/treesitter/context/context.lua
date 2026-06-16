-- Sticky-context computation.
--
-- Given a window, walk the treesitter ancestors of the node under the cursor
-- ("cursor" mode — the only mode this lib supports) and collect the ones whose
-- header has scrolled above the viewport top. Each surviving ancestor yields a
-- buffer range plus the text lines that make up its header (e.g. a function
-- signature, a class declaration, an `if (...)` line).
--
-- Ported from nvim-treesitter-context (MIT, see queries/NOTICE), trimmed to
-- cursor mode without separator support.

local fn, api = vim.fn, vim.api

local config = require("beast.libs.treesitter.config")
local query_loader = require("beast.libs.treesitter.context.query")

local M = {}

--- Height (in lines) a context range occupies. A range that ends at column 0
--- does not include its final row.
---@param range Range4
---@return integer
local function range_height(range)
	return range[3] - range[1] + (range[4] == 0 and 0 or 1)
end

--- Parent nodes of `range` within `langtree`, ordered root -> nearest-parent.
---@param langtree vim.treesitter.LanguageTree
---@param range Range4
---@return TSNode[]?
local function get_parent_nodes(langtree, range)
	local tree = langtree:tree_for_range(range, { ignore_injections = true })
	if not tree then
		return
	end

	local root = tree:root()
	local node = root:named_descendant_for_range(unpack(range))
	if not node then
		return
	end

	local ret = {} ---@type TSNode[]
	-- `child_with_descendant` (Nvim 0.11+) lets us descend without rebuilding
	-- the parent chain bottom-up; fall back to `:parent()` on older versions.
	---@diagnostic disable-next-line: undefined-field
	if root.child_with_descendant ~= nil then
		local p = root ---@type TSNode?
		while p do
			ret[#ret + 1] = p
			---@diagnostic disable-next-line: undefined-field
			p = p:child_with_descendant(node)
		end
		ret[#ret + 1] = node
	else
		local p = node ---@type TSNode?
		while p do
			table.insert(ret, 1, p)
			p = p:parent()
		end
	end

	return ret
end

--- Maximum number of context lines we are allowed to draw for `winid`. Caps at
--- the distance between the viewport top and the cursor so the float never
--- covers the cursor line, and at the user's `max_lines` budget.
---@param winid integer
---@return integer
local function calc_max_lines(winid)
	local max_lines = config.context.max_lines or 0
	max_lines = max_lines == 0 and -1 or max_lines

	local wintop = fn.line("w0", winid)
	local cursor = fn.line(".", winid)
	local max_from_cursor = cursor - wintop

	if max_lines ~= -1 then
		return math.min(max_lines, max_from_cursor)
	end
	return max_from_cursor
end

--- Run the context query on `node` and return the header range it describes,
--- or nil when `node` is not itself a context node.
---@param node TSNode
---@param bufnr integer
---@param query vim.treesitter.Query
---@return Range4?
local function context_range(node, bufnr, query)
	---@diagnostic disable-next-line: missing-fields
	local range = { node:range() } ---@type Range4
	range[3] = range[1] + 1
	range[4] = 0

	-- `max_start_depth = 0` restricts matching to `node` itself (a perf hint on
	-- Nvim 0.10+, ignored earlier).
	for _, match in query:iter_matches(node, bufnr, 0, -1, { max_start_depth = 0 }) do
		local is_context = false

		for id, nodes in pairs(match) do
			-- Nvim 0.9 yields a single TSNode, 0.10+ yields a list.
			local node0 = type(nodes) == "table" and nodes[#nodes] or nodes
			local srow, scol, erow, ecol = node0:range()
			local name = query.captures[id]

			if name == "context" then
				is_context = is_context or (node == node0)
			elseif name == "context.start" then
				range[1] = srow
				range[2] = scol
			elseif name == "context.final" then
				range[3] = erow
				range[4] = ecol
			elseif name == "context.end" then
				range[3] = srow
				range[4] = scol
			end
		end

		if is_context then
			return range
		end
	end
end

--- Trim `trim` lines off the collected contexts, removing whole ranges when
--- they fit inside the trim budget. `top` removes from the outermost end.
---@param ranges Range4[]
---@param lines string[][]
---@param trim integer
---@param top boolean
local function trim_contexts(ranges, lines, trim, top)
	while trim > 0 do
		local idx = top and 1 or #ranges
		local target = ranges[idx]
		if not target then
			return
		end

		local height = range_height(target)
		if height <= trim then
			table.remove(ranges, idx)
			table.remove(lines, idx)
		else
			target[3] = target[3] - trim + (target[4] == 0 and 0 or 1)
			target[4] = 0
			local target_lines = lines[idx]
			for _ = 1, trim do
				target_lines[#target_lines] = nil
			end
		end
		trim = math.max(0, trim - height)
	end
end

--- Resolve a header range to its concrete buffer text, dropping trailing empty
--- lines and clamping multi-line headers to `multiline_threshold`.
---@param range Range4
---@param bufnr integer
---@return Range4, string[]
local function get_text_for_range(range, bufnr)
	local start_row, end_row, end_col = range[1], range[3], range[4]

	if end_col == 0 then
		end_row = end_row - 1
		end_col = -1
	end

	local lines = api.nvim_buf_get_text(bufnr, start_row, 0, end_row, -1, {})

	local threshold = config.context.multiline_threshold or 20
	while #lines > 0 do
		local last = lines[#lines]:sub(1, end_col)
		if last:match("%S") and #lines <= threshold then
			break
		end
		lines[#lines] = nil
		end_col = -1
		end_row = end_row - 1
	end

	if end_col ~= 0 then
		end_col = 0
		end_row = end_row + 1
	end

	return { start_row, 0, end_row, end_col }, lines
end

--- Chain of language trees (root + injected) that contain `range`.
---@param bufnr integer
---@param range Range4
---@return vim.treesitter.LanguageTree[]
local function get_parent_langtrees(bufnr, range)
	local root_tree = vim.treesitter.get_parser(bufnr)
	if not root_tree then
		return {}
	end

	---@diagnostic disable-next-line: redundant-parameter
	root_tree:parse(range, function() end)
	local ret = { root_tree }

	while true do
		local child = nil
		for _, langtree in pairs(ret[#ret]:children()) do
			if langtree:contains(range) then
				child = langtree
				break
			end
		end
		if not child then
			break
		end
		ret[#ret + 1] = child
	end

	return ret
end

--- Iterate (parents, query) pairs over every language tree covering `range`
--- that has a usable context query.
---@param bufnr integer
---@param range Range4
---@return fun(): TSNode[]?, vim.treesitter.Query?
local function iter_context_parents(bufnr, range)
	local i = 0
	local trees = get_parent_langtrees(bufnr, range)
	return function()
		local parents, query
		repeat
			i = i + 1
			local tree = trees[i]
			if not tree then
				return
			end
			parents = get_parent_nodes(tree, range)
			query = query_loader.get(tree:lang())
		until parents and query
		return parents, query
	end
end

--- Flatten the per-context line lists into one flat list of strings.
---@param t string[][]
---@return string[]
local function flatten_lines(t)
	local result = {}
	for _, group in ipairs(t) do
		for _, line in ipairs(group) do
			result[#result + 1] = line
		end
	end
	return result
end

---@param range Range4
---@return boolean
local function range_is_valid(range)
	return not (range[1] == range[3] and range[2] == range[4])
end

--- Compute the sticky context for `winid`.
---@param winid? integer
---@return Range4[]?, string[]?
function M.get(winid)
	winid = winid or api.nvim_get_current_win()
	local bufnr = api.nvim_win_get_buf(winid)

	if not api.nvim_buf_is_loaded(bufnr) then
		return
	end

	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser then
		return
	end

	local max_lines = calc_max_lines(winid)
	local top_row = fn.line("w0", winid) - 1

	local cursor = api.nvim_win_get_cursor(winid)
	local row, col = cursor[1] - 1, cursor[2]

	local ranges = {} ---@type Range4[]
	local lines = {} ---@type string[][]
	local height = 0

	for offset = 0, max_lines do
		local node_row = row + offset
		local col0 = offset == 0 and col or 0
		local line_range = { node_row, col0, node_row, col0 + 1 }

		ranges = {}
		lines = {}
		height = 0

		for parents, query in iter_context_parents(bufnr, line_range) do
			for _, parent in ipairs(parents) do
				local parent_start_row = parent:range()
				local visible = top_row + math.min(max_lines, height)

				-- Only pin the parent when its header sits above the part of
				-- the viewport not already covered by earlier contexts.
				if parent_start_row < visible then
					local range0 = context_range(parent, bufnr, query)
					if range0 and range_is_valid(range0) then
						local range, text = get_text_for_range(range0, bufnr)
						if range_is_valid(range) then
							local last = ranges[#ranges]
							if last and parent_start_row == last[1] then
								-- Multiple contexts share a row: keep the inner one.
								height = height - range_height(last)
								ranges[#ranges] = nil
								lines[#lines] = nil
							end

							height = height + range_height(range)
							ranges[#ranges + 1] = range
							lines[#lines + 1] = text
						end
					end
				end
			end
		end

		if node_row >= top_row + math.min(max_lines, height) then
			break
		end
	end

	local trim = height - max_lines
	if trim > 0 then
		trim_contexts(ranges, lines, trim, (config.context.trim_scope or "outer") == "outer")
	end

	return ranges, flatten_lines(lines)
end

return M
