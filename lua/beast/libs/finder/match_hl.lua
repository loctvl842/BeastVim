--- Match highlights for the finder list + preview buffers.
---
--- Implementation note: highlights are stamped via a `nvim_set_decoration_provider`
--- (`on_win` + `on_line`) using ephemeral extmarks, so we only pay for rows
--- actually being drawn. The previous implementation looped the whole preview
--- buffer (could be 1000s of lines for grep) on every keystroke and stamped a
--- non-ephemeral extmark per match — that's gone now.
---
--- Callers (`apply_list`, `apply_preview`) only update per-buffer state; the
--- redraw is what produces the highlights.

local M = {}

local MATCH_NS = vim.api.nvim_create_namespace("beast-finder-match")

-- =========================================================================
-- Per-buffer state
-- =========================================================================

---@class Beast.Finder.MatchHL.ListState
---@field ranges_by_row table<integer, {[1]: integer, [2]: integer}[]>  0-indexed buf_row → {start_col, end_col}[]

---@class Beast.Finder.MatchHL.PreviewState
---@field terms string[]  lowercased substrings to highlight (plain, no patterns)

---@type table<integer, Beast.Finder.MatchHL.ListState>
local list_state = {}
---@type table<integer, Beast.Finder.MatchHL.PreviewState>
local preview_state = {}

-- =========================================================================
-- Helpers
-- =========================================================================

--- Merge adjacent 1-based positions into 0-indexed {start_col, end_col} ranges
---@param positions integer[] sorted 1-based byte indices
---@return {[1]: integer, [2]: integer}[] ranges 0-indexed
local function positions_to_ranges(positions)
	if not positions or #positions == 0 then
		return {}
	end
	local ranges = {}
	local start = positions[1]
	local prev = positions[1]
	for i = 2, #positions do
		local p = positions[i]
		if p == prev + 1 then
			prev = p
		else
			ranges[#ranges + 1] = { start - 1, prev }
			start = p
			prev = p
		end
	end
	ranges[#ranges + 1] = { start - 1, prev }
	return ranges
end

--- Extract highlightable terms from a pattern string.
---@param pattern string
---@return string[]
local function extract_terms(pattern)
	local terms = {}
	for term in pattern:gmatch("%S+") do
		if term:sub(1, 1) == "!" then
			-- skip inverse
		elseif term:sub(1, 1) == "'" then
			terms[#terms + 1] = term:sub(2)
		elseif term:sub(1, 1) == "^" then
			terms[#terms + 1] = term:sub(2)
		elseif term:sub(-1) == "$" then
			terms[#terms + 1] = term:sub(1, -2)
		else
			for part in term:gmatch("[^|]+") do
				if part ~= "" then
					terms[#terms + 1] = part
				end
			end
		end
	end
	return terms
end

--- Compute {buf_row → ranges} for the visible item slice. Mirrors the
--- offset arithmetic of the old `apply_list` body verbatim.
---@param items Beast.Finder.Item[]
---@param format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
---@param from integer 1-based first visible item
---@param to integer 1-based last visible item
---@return table<integer, {[1]: integer, [2]: integer}[]>
local function compute_list_ranges(items, format_fn, from, to)
	local ranges_by_row = {}
	for i = from, to do
		local item = items[i]
		if not item or not item.positions or #item.positions == 0 then
			goto continue
		end

		-- Calculate the byte offset added by the format prefix (icon + space, etc.)
		local highlights = format_fn(item)
		local item_text = item.text or ""
		local rendered_parts = {}
		for _, h in ipairs(highlights) do
			if not h.right_align then
				rendered_parts[#rendered_parts + 1] = h.text
			end
		end
		local rendered = table.concat(rendered_parts)
		local rel_text = item_text
		local cwd = item.cwd or vim.fn.getcwd()
		if rel_text:sub(1, #cwd) == cwd then
			rel_text = rel_text:sub(#cwd + 2)
		end
		local offset = rendered:find(rel_text, 1, true)
		if not offset then
			offset = 1
		else
			offset = offset - 1
		end

		local sorted_pos = {}
		for _, p in ipairs(item.positions) do
			sorted_pos[#sorted_pos + 1] = p
		end
		table.sort(sorted_pos)
		local ranges = positions_to_ranges(sorted_pos)

		local buf_row = i - from
		local rendered_len = #rendered
		local row_ranges = {}
		for _, range in ipairs(ranges) do
			local start_col = range[1] + offset
			local end_col = range[2] + offset
			if start_col < rendered_len and end_col <= rendered_len then
				row_ranges[#row_ranges + 1] = { start_col, end_col }
			end
		end
		if #row_ranges > 0 then
			ranges_by_row[buf_row] = row_ranges
		end

		::continue::
	end
	return ranges_by_row
end

-- =========================================================================
-- Decoration provider — stamps ephemeral extmarks only for visible rows
-- =========================================================================

local installed = false
local function install_provider()
	-- stylua: ignore
	if installed then return end
	installed = true

	vim.api.nvim_set_decoration_provider(MATCH_NS, {
		-- Cheap predicate: skip windows whose buffer we don't manage.
		on_win = function(_, _, buf)
			return list_state[buf] ~= nil or preview_state[buf] ~= nil
		end,

		on_line = function(_, _, buf, row)
			local lst = list_state[buf]
			if lst then
				local row_ranges = lst.ranges_by_row[row]
				-- stylua: ignore
				if row_ranges == nil then return end
				for i = 1, #row_ranges do
					local r = row_ranges[i]
					vim.api.nvim_buf_set_extmark(buf, MATCH_NS, row, r[1], {
						end_col = r[2],
						hl_group = "BeastFinderListMatch",
						ephemeral = true,
						priority = 5000,
					})
				end
				return
			end

			local prv = preview_state[buf]
			if prv then
				local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
				-- stylua: ignore
				if line == nil or line == "" then return end
				local lower = line:lower()
				local terms = prv.terms
				for ti = 1, #terms do
					local term = terms[ti]
					local start = 1
					while true do
						local s, e = lower:find(term, start, true)
						-- stylua: ignore
						if not s then break end
						vim.api.nvim_buf_set_extmark(buf, MATCH_NS, row, s - 1, {
							end_col = e,
							hl_group = "BeastFinderPreviewMatch",
							ephemeral = true,
							priority = 5000,
						})
						start = s + 1
					end
				end
			end
		end,
	})

	-- Clean up state when buffers go away so we don't leak entries indexed
	-- by stale buffer handles (handles are reused by Neovim).
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		group = vim.api.nvim_create_augroup("BeastFinderMatchHL", { clear = true }),
		callback = function(args)
			list_state[args.buf] = nil
			preview_state[args.buf] = nil
		end,
	})
end

-- =========================================================================
-- Public API
-- =========================================================================

--- Apply fuzzy match highlights to the list buffer using item.positions.
--- Only processes items in the visible range [from, to] (1-based into items).
--- Buffer rows are offset so that `from` maps to buffer row 0.
---@param buf integer buffer handle
---@param items Beast.Finder.Item[] matched items (with .positions field)
---@param format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
---@param from integer 1-based first visible item index
---@param to integer 1-based last visible item index
function M.apply_list(buf, items, format_fn, from, to)
	install_provider()
	from = from or 1
	to = to or #items
	list_state[buf] = { ranges_by_row = compute_list_ranges(items, format_fn, from, to) }
end

--- Apply substring match highlights to preview buffer.
--- Terms are extracted from the query pattern; matching is plain + case-insensitive.
---@param buf integer buffer handle
---@param query string current search query
function M.apply_preview(buf, query)
	install_provider()
	if not query or query == "" then
		preview_state[buf] = nil
		return
	end

	local terms = extract_terms(query)
	if #terms == 0 then
		preview_state[buf] = nil
		return
	end

	local lowered = {}
	for i = 1, #terms do
		lowered[i] = terms[i]:lower()
	end
	preview_state[buf] = { terms = lowered }
end

--- Clear match highlights from a buffer.
---@param buf integer
function M.clear(buf)
	list_state[buf] = nil
	preview_state[buf] = nil
end

return M
