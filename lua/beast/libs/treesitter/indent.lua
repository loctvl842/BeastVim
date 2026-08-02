-- Treesitter-driven `'indentexpr'`.
--
-- Neovim core has no `vim.treesitter.indentexpr()` — structure-aware indent is
-- normally a feature of the nvim-treesitter plugin, which this config
-- deliberately doesn't depend on. This module is a from-scratch consumer of
-- the same `indents.scm` query convention (`@indent.begin`/`@indent.end`/
-- `@indent.branch`/`@indent.dedent`/`@indent.align`/`@indent.auto`/
-- `@indent.ignore`/`@indent.zero`) that `install.lua` already downloads
-- alongside highlights/folds/injections/locals for every language. The
-- capture-walking algorithm below follows the same interpretation of those
-- captures as nvim-treesitter's `indent.lua` (MIT), since the query files
-- themselves are written against that convention.
--
-- `treesitter/init.lua` only assigns `vim.bo[buf].indentexpr` to this module
-- when `vim.treesitter.query.get(lang, "indents")` is non-nil for the
-- buffer's language — buffers without an indents query never have their
-- indentexpr touched, so this module is never called for them.

local ts = vim.treesitter

local M = {}

-- Languages whose parser is only ever injected for comment content (jsdoc,
-- luadoc, ...). Never picked as the "smallest enclosing root" for a line.
local comment_langs = {
	comment = true,
	luadoc = true,
	javadoc = true,
	jsdoc = true,
	phpdoc = true,
}

---@param lnum integer 1-indexed
---@return string
local function get_line(lnum)
	return vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or ""
end

---@param lnum integer 1-indexed
---@return integer
local function indentcols_at(lnum)
	local _, cols = get_line(lnum):find("^%s*")
	return cols or 0
end

---@param root TSNode
---@param lnum integer 1-indexed
---@param col? integer
---@return TSNode?
local function first_node_at_line(root, lnum, col)
	col = col or indentcols_at(lnum)
	return root:descendant_for_range(lnum - 1, col, lnum - 1, col + 1)
end

---@param root TSNode
---@param lnum integer 1-indexed
---@param col? integer
---@return TSNode?
local function last_node_at_line(root, lnum, col)
	col = col or (#get_line(lnum) - 1)
	return root:descendant_for_range(lnum - 1, col, lnum - 1, col + 1)
end

--- Find `node`'s direct child of type `delimiter`, and whether nothing but
--- whitespace/the delimiter itself follows it on that line (used by
--- `@indent.align` to tell a "hanging" open delimiter from an inline one).
---@param bufnr integer
---@param node TSNode
---@param delimiter string
---@return TSNode?, boolean?
local function find_delimiter(bufnr, node, delimiter)
	for child in node:iter_children() do
		if child:type() == delimiter then
			local linenr = child:start()
			local line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1] or ""
			local _, _, _, ecol = child:range()
			local escaped = delimiter:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1")
			local trailing = line:sub(ecol + 1):gsub("[%s" .. escaped .. "]*", "")
			return child, #trailing == 0
		end
	end
end

-- Per-buffer single-slot cache of the compiled `indents` capture map, keyed
-- by the tree's root node id so a reparse invalidates it naturally.
---@type table<integer, { root_id: string, lang: string, map: table<string, table<string, table>> }>
local capture_cache = {}

--- Capture map for `root`'s tree: capture name -> node id -> `#set!` metadata.
---@param bufnr integer
---@param root TSNode
---@param lang string
---@return table<string, table<string, table>>
local function get_captures(bufnr, root, lang)
	local root_id = root:id()
	local cached = capture_cache[bufnr]
	if cached and cached.root_id == root_id and cached.lang == lang then
		return cached.map
	end

	local map = {
		["indent.auto"] = {},
		["indent.begin"] = {},
		["indent.end"] = {},
		["indent.dedent"] = {},
		["indent.branch"] = {},
		["indent.ignore"] = {},
		["indent.align"] = {},
		["indent.zero"] = {},
	}

	local query = ts.query.get(lang, "indents")
	if query then
		for id, node, metadata in query:iter_captures(root, bufnr) do
			local name = query.captures[id]
			if map[name] then
				map[name][node:id()] = metadata or {}
			end
		end
	end

	capture_cache[bufnr] = { root_id = root_id, lang = lang, map = map }
	return map
end

--- Smallest enclosing (non-comment-injection) tree root covering `lnum`.
---@param bufnr integer
---@param lnum integer 1-indexed
---@return TSNode?, string?
local function get_root_for_line(bufnr, lnum)
	local parser = ts.get_parser(bufnr)
	if not parser then
		return nil
	end

	-- Parse the whole visible window, not just `lnum` — an injected tree
	-- (e.g. a markdown fenced code block, an HTML <script> tag) elsewhere in
	-- the viewport needs to already be discovered for `for_each_tree` below
	-- to find it, and the blank-line path can resolve to a row outside
	-- `lnum` via `prevnonblank`.
	parser:parse({ vim.fn.line("w0") - 1, vim.fn.line("w$") })

	local root, lang
	parser:for_each_tree(function(tstree, langtree)
		if not tstree or comment_langs[langtree:lang()] then
			return
		end
		local candidate = tstree:root()
		if ts.is_in_node_range(candidate, lnum - 1, 0) then
			if not root or root:byte_length() >= candidate:byte_length() then
				root = candidate
				lang = langtree:lang()
			end
		end
	end)

	return root, lang
end

--- Resolve the alignment metadata on `node` for the current target line.
--- Returns the new running `indent`, whether it is an absolute column (no
--- further ancestor indenting should apply), and whether the node counted as
--- processed for its start row.
---@param bufnr integer
---@param node TSNode
---@param metadata table
---@param indent integer
---@param indent_size integer
---@param lnum integer 1-indexed
---@param should_process boolean
---@return integer indent, boolean is_absolute, boolean processed
local function resolve_align(bufnr, node, metadata, indent, indent_size, lnum, should_process)
	local o_node, o_last_in_line
	if metadata["indent.open_delimiter"] then
		o_node, o_last_in_line = find_delimiter(bufnr, node, metadata["indent.open_delimiter"])
	else
		o_node = node
	end

	local c_node, c_last_in_line
	if metadata["indent.close_delimiter"] then
		c_node, c_last_in_line = find_delimiter(bufnr, node, metadata["indent.close_delimiter"])
	else
		c_node = node
	end

	if not o_node then
		return indent, false, false
	end

	local o_srow, o_scol = o_node:start()
	local c_srow = c_node and select(1, c_node:start())
	local is_absolute = false

	if o_last_in_line then
		-- Hanging indent: the open delimiter was last on its line.
		if should_process then
			indent = indent + indent_size
			if c_last_in_line and c_srow and c_srow < lnum - 1 then
				indent = math.max(indent - indent_size, 0)
			end
		end
	elseif c_last_in_line and c_srow and o_srow ~= c_srow and c_srow < lnum - 1 then
		indent = math.max(indent - indent_size, 0)
	else
		indent = o_scol + (metadata["indent.increment"] or 1)
		is_absolute = true
	end

	if c_srow and c_srow ~= o_srow and c_srow == lnum - 1 and metadata["indent.avoid_last_matching_next"] then
		-- Closing line would otherwise land at the same depth as the next
		-- line — nudge it one step deeper to keep them visually distinct.
		if indent <= vim.fn.indent(o_srow + 1) + indent_size then
			indent = indent + indent_size
		end
	end

	return indent, is_absolute, true
end

--- Compute the indent (in columns) for `lnum`, or -1 to copy the previous
--- line's indent (Vim's `'indentexpr'` convention).
---@param lnum integer 1-indexed
---@return integer
function M.get_indent(lnum)
	local bufnr = vim.api.nvim_get_current_buf()
	local root, lang = get_root_for_line(bufnr, lnum)
	if not root then
		return -1
	end

	local captures = get_captures(bufnr, root, lang)

	local node
	if get_line(lnum):match("^%s*$") then
		local prevlnum = vim.fn.prevnonblank(lnum)
		if prevlnum == 0 then
			return -1
		end
		local indentcols = indentcols_at(prevlnum)
		local prevline = vim.trim(get_line(prevlnum))
		node = last_node_at_line(root, prevlnum, indentcols + #prevline - 1)
		if node and node:type():match("comment") then
			local first = first_node_at_line(root, prevlnum, indentcols)
			local _, scol = node:range()
			if first and first:id() ~= node:id() then
				prevline = vim.trim(prevline:sub(1, scol - indentcols))
				node = last_node_at_line(root, prevlnum, indentcols + #prevline - 1)
			end
		end
		if node and captures["indent.end"][node:id()] then
			node = first_node_at_line(root, lnum)
		end
	else
		node = first_node_at_line(root, lnum)
	end

	if node and captures["indent.zero"][node:id()] then
		return 0
	end

	local indent_size = vim.fn.shiftwidth()
	local indent = 0
	local root_srow = select(1, root:start())
	if root_srow ~= 0 then
		indent = vim.fn.indent(root_srow + 1)
	end

	-- Tracks which start-rows have already contributed an indent step, so a
	-- node spanning multiple ancestor levels on the same row isn't counted
	-- twice.
	local processed_rows = {} ---@type table<integer, boolean>

	while node do
		local id = node:id()

		if
			not captures["indent.begin"][id]
			and not captures["indent.align"][id]
			and captures["indent.auto"][id]
			and node:start() < lnum - 1
			and lnum - 1 <= node:end_()
		then
			return -1
		end

		if not captures["indent.begin"][id] and captures["indent.ignore"][id] and node:start() < lnum - 1 and lnum - 1 <= node:end_() then
			return 0
		end

		local srow, _, erow = node:range()
		local is_processed = false
		local should_process = not processed_rows[srow]

		if should_process and ((captures["indent.branch"][id] and srow == lnum - 1) or (captures["indent.dedent"][id] and srow ~= lnum - 1)) then
			indent = indent - indent_size
			is_processed = true
		end

		local is_in_err = should_process and (node:parent() ~= nil) and node:parent():has_error()
		local begin_meta = captures["indent.begin"][id]
		if
			should_process
			and begin_meta
			and (srow ~= erow or is_in_err or begin_meta["indent.immediate"])
			and (srow ~= lnum - 1 or begin_meta["indent.start_at_same_line"])
		then
			indent = indent + indent_size
			is_processed = true
		end

		if is_in_err and not captures["indent.align"][id] then
			-- Promote a child's `@indent.align` metadata onto the ERROR node
			-- itself, matching how the queries express "align inside a still-
			-- being-typed, currently invalid construct".
			for child in node:iter_children() do
				if captures["indent.align"][child:id()] then
					captures["indent.align"][id] = captures["indent.align"][child:id()]
					break
				end
			end
		end

		local align_meta = captures["indent.align"][id]
		if should_process and align_meta and (srow ~= erow or is_in_err) and srow ~= lnum - 1 then
			local is_absolute, matched
			indent, is_absolute, matched = resolve_align(bufnr, node, align_meta, indent, indent_size, lnum, should_process)
			is_processed = is_processed or matched
			if is_absolute then
				return indent
			end
		end

		processed_rows[srow] = processed_rows[srow] or is_processed
		node = node:parent()
	end

	return indent
end

--- Entry point for `'indentexpr'`. Reads `v:lnum`, as the option contract
--- requires. Never allowed to error out of an edit — a failure here falls
--- back to "keep the current indent" rather than surfacing to the user.
---@return integer
function M.indentexpr()
	local ok, result = pcall(M.get_indent, vim.v.lnum)
	if not ok then
		return -1
	end
	return result
end

return M
