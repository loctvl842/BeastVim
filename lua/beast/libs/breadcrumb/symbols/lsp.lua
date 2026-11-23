-- LSP symbol source: keeps one `textDocument/documentSymbol` tree per buffer and
-- answers "which symbols contain this position?".
--
-- The tree is only ever replaced by a newer successful reply, so the trail does
-- not blank while a server re-reads after an edit.

local kinds = require("beast.libs.breadcrumb.symbols.kinds")

local M = {}

local METHOD = "textDocument/documentSymbol"

---@class Beast.Breadcrumb.SymbolNode
---@field name string
---@field kind string  `Icon.kinds` key
---@field range integer[]  { start_row, start_col, end_row, end_col }, 0-indexed, end exclusive, columns in the server's offset encoding
---@field children Beast.Breadcrumb.SymbolNode[]

---@class Beast.Breadcrumb.SymbolEntry
---@field seq integer  Bumped on every request; only the newest reply is applied
---@field tree? Beast.Breadcrumb.SymbolNode[]
---@field encoding? string  Offset encoding of the client that produced `tree`

---@type table<integer, Beast.Breadcrumb.SymbolEntry>
local store = {}

---Called with the buffer number whenever a buffer's tree is replaced.
---@type fun(bufnr: integer)?
M.on_change = nil

-- =========================================================================
-- Normalization
-- =========================================================================

---@param r lsp.Range
---@return integer[]
local function to_range(r)
	return { r.start.line, r.start.character, r["end"].line, r["end"].character }
end

---@param a integer[]
---@param b integer[]
---@return boolean
local function starts_before(a, b)
	return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
end

---@param outer integer[]
---@param inner integer[]
---@return boolean
local function range_contains_range(outer, inner)
	return not starts_before(inner, outer) and not starts_before({ outer[3], outer[4] }, { inner[3], inner[4] })
end

---Sort siblings by start so lookup can binary search.
---@param nodes Beast.Breadcrumb.SymbolNode[]
local function sort_level(nodes)
	table.sort(nodes, function(a, b)
		return starts_before(a.range, b.range)
	end)
end

---@param items lsp.DocumentSymbol[]
---@return Beast.Breadcrumb.SymbolNode[]
local function from_document_symbols(items)
	local nodes = {}
	for _, item in ipairs(items) do
		nodes[#nodes + 1] = {
			name = item.name,
			kind = kinds.name(item.kind),
			range = to_range(item.range),
			children = from_document_symbols(item.children or {}),
		}
	end
	sort_level(nodes)
	return nodes
end

---Flat `SymbolInformation[]` carries no hierarchy; rebuild it from range containment.
---@param items lsp.SymbolInformation[]
---@return Beast.Breadcrumb.SymbolNode[]
local function from_symbol_information(items)
	local flat = {}
	for _, item in ipairs(items) do
		flat[#flat + 1] = { name = item.name, kind = kinds.name(item.kind), range = to_range(item.location.range), children = {} }
	end
	-- Outer symbols first: earlier start, then later end
	table.sort(flat, function(a, b)
		if a.range[1] ~= b.range[1] or a.range[2] ~= b.range[2] then
			return starts_before(a.range, b.range)
		end
		return starts_before({ b.range[3], b.range[4] }, { a.range[3], a.range[4] })
	end)

	local roots, stack = {}, {}
	for _, node in ipairs(flat) do
		while #stack > 0 and not range_contains_range(stack[#stack].range, node.range) do
			stack[#stack] = nil
		end
		local parent = stack[#stack]
		table.insert(parent and parent.children or roots, node)
		stack[#stack + 1] = node
	end
	return roots
end

---@param result lsp.DocumentSymbol[]|lsp.SymbolInformation[]
---@return Beast.Breadcrumb.SymbolNode[]
function M.normalize(result)
	if result[1] and result[1].location then
		return from_symbol_information(result --[[@as lsp.SymbolInformation[] ]])
	end
	return from_document_symbols(result --[[@as lsp.DocumentSymbol[] ]])
end

-- =========================================================================
-- Lookup
-- =========================================================================

---@param r integer[]
---@param row integer
---@param col integer
---@return boolean
local function contains(r, row, col)
	if row < r[1] or row > r[3] then
		return false
	end
	if row == r[1] and col < r[2] then
		return false
	end
	return not (row == r[3] and col >= r[4])
end

---Symbols containing (row, col), outermost first. Siblings are disjoint and sorted,
---so each level is a binary search for the last node starting at or before the position.
---@param tree Beast.Breadcrumb.SymbolNode[]
---@param row integer
---@param col integer  In the same encoding as the tree's ranges
---@return Beast.Breadcrumb.SymbolNode[]
function M.find(tree, row, col)
	local chain = {}
	local level = tree
	while #level > 0 do
		local lo, hi, hit = 1, #level, nil
		while lo <= hi do
			local mid = math.floor((lo + hi) / 2)
			if starts_before({ row, col }, level[mid].range) then
				hi = mid - 1
			else
				hit, lo = level[mid], mid + 1
			end
		end
		if not hit or not contains(hit.range, row, col) then
			break
		end
		chain[#chain + 1] = hit
		level = hit.children
	end
	return chain
end

---Trail at a buffer position. `nil` means this source has nothing for the buffer (no
---server answer yet, or the server reports no symbols); `{}` means a server answered
---but the cursor is outside every symbol.
---@param bufnr integer
---@param row integer  0-indexed
---@param col integer  0-indexed byte column
---@return Beast.Breadcrumb.Symbol[]?
function M.trail(bufnr, row, col)
	local entry = store[bufnr]
	if not entry or not entry.tree or #entry.tree == 0 then
		return nil
	end

	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
	col = vim.str_utfindex(line, entry.encoding, col, false)

	local trail = {}
	for _, node in ipairs(M.find(entry.tree, row, col)) do
		if node.name ~= "" then
			trail[#trail + 1] = { name = node.name, kind = node.kind }
		end
	end
	return trail
end

-- =========================================================================
-- Refresh
-- =========================================================================

---Request fresh symbols for a buffer. No-op when no attached client supports the method.
---@param bufnr integer
function M.refresh(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) or #vim.lsp.get_clients({ bufnr = bufnr, method = METHOD }) == 0 then
		return
	end

	local entry = store[bufnr] or { seq = 0 }
	store[bufnr] = entry
	entry.seq = entry.seq + 1
	local seq = entry.seq

	local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
	vim.lsp.buf_request_all(bufnr, METHOD, params, function(results)
		if store[bufnr] ~= entry or entry.seq ~= seq then
			return
		end

		-- Client order keeps the pick stable when several servers answer
		local ids = vim.tbl_keys(results)
		table.sort(ids)

		local answered = false
		for _, id in ipairs(ids) do
			local res = results[id]
			if not res.err then
				answered = true
				if res.result and #res.result > 0 then
					local client = vim.lsp.get_client_by_id(id)
					entry.tree = M.normalize(res.result)
					entry.encoding = client and client.offset_encoding or "utf-16"
					if M.on_change then
						M.on_change(bufnr)
					end
					return
				end
			end
		end

		-- Servers that answered with nothing: the file has no symbols. Errors (e.g. content
		-- modified) say nothing, so the previous tree stays.
		if answered and entry.tree and #entry.tree > 0 then
			entry.tree = {}
			if M.on_change then
				M.on_change(bufnr)
			end
		end
	end)
end

---Forget a buffer (closed, or its last symbol server detached).
---@param bufnr integer
function M.clear(bufnr)
	store[bufnr] = nil
end

return M
