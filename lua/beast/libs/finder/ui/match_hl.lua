local config = require("beast.libs.finder.config")

local M = {}

local MATCH_NS = vim.api.nvim_create_namespace("beastvim-finder-match")

--- Escape Lua pattern special characters
---@param str string
---@return string
local function escape_pattern(str)
	return (str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

--- Find all substring match ranges of query in text (case-insensitive)
---@param text string
---@param query string
---@return {[1]: integer, [2]: integer}[] ranges (0-indexed byte columns)
function M.find_ranges(text, query)
	-- stylua: ignore
	if query == "" then return {} end

	local ranges = {}
	local pattern = escape_pattern(query)
	local lower_text = text:lower()
	local lower_pattern = pattern:lower()
	local start = 1

	while true do
		local s, e = lower_text:find(lower_pattern, start)
		if not s then
			break
		end
		ranges[#ranges + 1] = { s - 1, e }
		start = s + 1
	end

	return ranges
end

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

--- Apply fuzzy match highlights to the list buffer using item.positions
---@param buf integer buffer handle
---@param items Beast.Finder.Item[] matched items (with .positions field)
---@param format_fn fun(item: Beast.Finder.Item): Beast.Finder.Highlight[]
function M.apply_list(buf, items, format_fn)
	vim.api.nvim_buf_clear_namespace(buf, MATCH_NS, 0, -1)

	for row, item in ipairs(items) do
		if not item.positions or #item.positions == 0 then
			goto continue
		end

		-- Calculate the byte offset added by the format prefix (icon + space, etc.)
		local highlights = format_fn(item)
		local prefix_len = 0
		local item_text = item.text or ""
		-- The rendered line = concat of all highlight parts
		-- item.text is the raw path; find where it starts in the rendered line
		local rendered_parts = {}
		for _, h in ipairs(highlights) do
			rendered_parts[#rendered_parts + 1] = h.text
		end
		local rendered = table.concat(rendered_parts)
		-- Find the offset: item.text (or its relative form) starts at some byte in rendered
		-- The format adds icon prefix before the path. The path in rendered is relative.
		-- We need to find the byte offset where the matchable text starts.
		local rel_text = item_text
		local cwd = item.cwd or vim.fn.getcwd()
		if rel_text:sub(1, #cwd) == cwd then
			rel_text = rel_text:sub(#cwd + 2)
		end
		local offset = rendered:find(rel_text, 1, true)
		if not offset then
			offset = 1
		else
			offset = offset - 1 -- convert to 0-based prefix length
		end

		-- Sort positions and convert to ranges with offset
		local sorted_pos = {}
		for _, p in ipairs(item.positions) do
			sorted_pos[#sorted_pos + 1] = p
		end
		table.sort(sorted_pos)
		local ranges = positions_to_ranges(sorted_pos)

		for _, range in ipairs(ranges) do
			local start_col = range[1] + offset
			local end_col = range[2] + offset
			if start_col < #rendered and end_col <= #rendered then
				vim.api.nvim_buf_set_extmark(buf, MATCH_NS, row - 1, start_col, {
					end_col = end_col,
					hl_group = "BeastFinderListMatch",
					priority = 5000,
				})
			end
		end

		::continue::
	end
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

--- Apply substring match highlights to preview buffer
---@param buf integer buffer handle
---@param query string current search query
function M.apply_preview(buf, query)
	vim.api.nvim_buf_clear_namespace(buf, MATCH_NS, 0, -1)
	-- stylua: ignore
	if not query or query == "" then return end

	local terms = extract_terms(query)
	-- stylua: ignore
	if #terms == 0 then return end

	local line_count = vim.api.nvim_buf_line_count(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, line_count, false)

	for row, line in ipairs(lines) do
		for _, term in ipairs(terms) do
			local ranges = M.find_ranges(line, term)
			for _, range in ipairs(ranges) do
				vim.api.nvim_buf_set_extmark(buf, MATCH_NS, row - 1, range[1], {
					end_col = range[2],
					hl_group = "BeastFinderPreviewMatch",
					priority = 5000,
				})
			end
		end
	end
end

--- Clear match highlights from a buffer
---@param buf integer
function M.clear(buf)
	vim.api.nvim_buf_clear_namespace(buf, MATCH_NS, 0, -1)
end

return M
