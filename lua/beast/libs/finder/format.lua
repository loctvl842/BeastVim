---@class Beast.Finder.Highlight
---@field text string
---@field hl string?
---@field right_align boolean?

local M = {}

local devicons ---@type table|false|nil nil=not loaded yet, false=unavailable

local function get_icon(filename)
	if devicons == nil then
		local ok, mod = pcall(require, "nvim-web-devicons")
		devicons = ok and mod or false
	end
	if devicons then
		local icon, hl = devicons.get_icon(filename, nil, { default = true })
		return icon, hl
	end
	return nil, nil
end

--- Trim a relative path to fit within `max_width` by collapsing middle segments with "…".
--- Keeps the first segment and filename intact, collapses directories in between.
--- Example: "api-reference/beta/includes/snippets/csharp/file.md" → "api-reference/…/file.md"
---@param rel string relative path
---@param max_width integer available character width
---@return string dir directory portion (may contain …) or empty
---@return string base filename
local function trim_path(rel, max_width)
	local base = rel:match("[^/]+$") or rel
	local dir = rel:match("^(.+)/[^/]+$")
	if not dir then
		return "", base
	end

	local full = dir .. "/" .. base
	if #full <= max_width then
		return dir, base
	end

	-- Split directory into segments
	local segments = {}
	for seg in dir:gmatch("[^/]+") do
		segments[#segments + 1] = seg
	end

	if #segments <= 1 then
		return dir, base
	end

	-- Keep first segment + "…" + progressively add from the end
	local first = segments[1]
	local ellipsis = "…"
	-- Try keeping more trailing segments until it fits
	for keep_end = 1, #segments - 1 do
		local tail_parts = {}
		for i = #segments - keep_end + 1, #segments do
			tail_parts[#tail_parts + 1] = segments[i]
		end
		local tail = table.concat(tail_parts, "/")
		local trimmed = first .. "/" .. ellipsis .. "/" .. tail
		if #trimmed + 1 + #base <= max_width then
			return trimmed, base
		end
	end

	-- Worst case: just first/…
	local minimal = first .. "/" .. ellipsis
	if #minimal + 1 + #base <= max_width then
		return minimal, base
	end

	-- Even that's too long — just show …/base
	return ellipsis, base
end

---@param item Beast.Finder.Item
---@param max_width? integer available column width for trimming
---@return Beast.Finder.Highlight[]
function M.filename(item, max_width)
	local path = item.file or item.text or ""
	local cwd = item.cwd or vim.fn.getcwd()

	-- Make relative to cwd
	local rel = path
	if path:sub(1, #cwd) == cwd then
		rel = path:sub(#cwd + 2) -- skip trailing /
	end

	local dir, base
	if max_width then
		-- Reserve space for icon (2 chars) + dir separator (1 char)
		dir, base = trim_path(rel, max_width - 3)
	else
		dir = rel:match("^(.+)/[^/]+$")
		base = rel:match("[^/]+$") or rel
	end

	local result = {}

	local icon, icon_hl = get_icon(base)
	if icon then
		result[#result + 1] = { text = icon .. " ", hl = icon_hl }
	end

	if dir and dir ~= "" then
		result[#result + 1] = { text = dir .. "/", hl = "BeastFinderListDir" }
	end
	result[#result + 1] = { text = base, hl = "BeastFinderListFile" }

	return result
end

---@param item Beast.Finder.Item
---@return Beast.Finder.Highlight[]
function M.buffers(item)
	local name = item.file or ""
	if name == "" then
		name = "[No Name]"
	else
		local cwd = vim.fn.getcwd()
		if name:sub(1, #cwd) == cwd then
			name = name:sub(#cwd + 2)
		end
	end

	local modified = item.buf and vim.bo[item.buf].modified and " [+]" or ""
	local bufnr_str = item.buf and ("[" .. item.buf .. "] ") or ""

	return {
		{ text = bufnr_str, hl = "BeastFinderListDir" },
		{ text = name, hl = "BeastFinderListFile" },
		{ text = modified, hl = "BeastFinderListMatch" },
	}
end

---@param item Beast.Finder.Item
---@return Beast.Finder.Highlight[]
function M.colorschemes(item)
	return {
		{ text = item.text, hl = "BeastFinderListFile" },
	}
end

---@param item Beast.Finder.Item
---@return Beast.Finder.Highlight[]
function M.help_tags(item)
	local tag = item.text or item.help_tag or ""
	local doc_name
	if item.is_readme then
		doc_name = "README.md"
	else
		doc_name = item.file and vim.fn.fnamemodify(item.file, ":t") or ""
	end

	local result = {}
	result[#result + 1] = { text = " ", hl = "BeastFinderListDir" }
	result[#result + 1] = { text = tag, hl = "BeastFinderListFile" }
	if doc_name ~= "" then
		result[#result + 1] = { text = doc_name .. string.rep(" ", 5), hl = "BeastFinderListDir", right_align = true }
	end
	return result
end

--- Byte range [s, e) of the matched text within `item.grep_text`, or nil.
--- Grep items carry the matched literal in `match_text`; LSP items carry the
--- range end in `end_pos`. Falls back to a plain search for the literal when the
--- reported column doesn't line up (e.g. ugrep visual vs byte columns).
---@param item Beast.Finder.Item
---@return integer? s 0-based start, integer? e 0-based end (exclusive)
local function grep_match_range(item)
	local text = item.grep_text or ""
	if text == "" then
		return nil
	end
	local col = item.pos and item.pos[2] or 0 -- 0-based byte
	local mlen
	if item.match_text and item.match_text ~= "" then
		mlen = #item.match_text
		-- Verify the reported column actually points at the literal; if not,
		-- find the literal in the line and use that instead.
		if text:sub(col + 1, col + mlen) ~= item.match_text then
			local s = text:find(item.match_text, 1, true)
			if s then
				col = s - 1
			else
				return nil
			end
		end
	elseif item.end_pos and item.pos and item.end_pos[1] == item.pos[1] then
		mlen = (item.end_pos[2] or col) - col
	end
	if not mlen or mlen <= 0 then
		return nil
	end
	local s = math.max(0, math.min(col, #text))
	local e = math.max(s, math.min(col + mlen, #text))
	if e <= s then
		return nil
	end
	return s, e
end

--- Match line for a grouped grep/LSP list: "lnum:col  text" (no path — the
--- path is shown once in the group header). Indented so matches sit under their
--- file header. The matched substring is highlighted; the line is not truncated
--- (the list window clips it, nowrap).
---@param item Beast.Finder.Item
---@param max_width? integer unused (kept for the shared formatter signature)
---@return Beast.Finder.Highlight[]
function M.live_grep(item, max_width)
	local lnum = item.pos and item.pos[1] or 0
	local col = (item.pos and item.pos[2] or 0) + 1 -- col is 0-based byte; show 1-based
	local text = item.grep_text or ""
	local location = lnum .. ":" .. col

	local result = {
		{ text = "  ", hl = nil },
		{ text = location, hl = "BeastFinderListDir" },
		{ text = "  ", hl = nil },
	}

	local ms, me = grep_match_range(item)
	if ms then
		if ms > 0 then
			result[#result + 1] = { text = text:sub(1, ms), hl = "BeastFinderListFile" }
		end
		result[#result + 1] = { text = text:sub(ms + 1, me), hl = "BeastFinderListMatch" }
		if me < #text then
			result[#result + 1] = { text = text:sub(me + 1), hl = "BeastFinderListFile" }
		end
	else
		result[#result + 1] = { text = text, hl = "BeastFinderListFile" }
	end
	return result
end

--- File-group header for grouped grep/LSP lists: "<icon> base  dir". Shown once
--- per file, above its matches.
---@param item Beast.Finder.Item
---@param max_width? integer available column width for trimming
---@return Beast.Finder.Highlight[]
function M.live_grep_header(item, max_width)
	local path = item.file or ""
	local cwd = item.cwd or vim.fn.getcwd()
	local rel = path
	if path:sub(1, #cwd) == cwd then
		rel = path:sub(#cwd + 2)
	end
	local base = rel:match("[^/]+$") or rel
	local dir = rel:match("^(.+)/[^/]+$")

	local result = {}
	local icon, icon_hl = get_icon(base)
	if icon then
		result[#result + 1] = { text = icon .. " ", hl = icon_hl }
	end
	result[#result + 1] = { text = base, hl = "BeastFinderListFile" }
	if dir and dir ~= "" then
		if max_width then
			local used = (icon and 2 or 0) + vim.fn.strdisplaywidth(base) + 2
			local budget = math.max(1, max_width - used)
			if #dir > budget then
				local trimmed = trim_path(dir, budget)
				if trimmed ~= "" then
					dir = trimmed
				end
			end
		end
		result[#result + 1] = { text = "  " .. dir, hl = "BeastFinderListDir" }
	end
	return result
end

-- LSP sources surface file:line + snippet, identical to live_grep.
M.lsp_definitions = M.live_grep
M.lsp_references = M.live_grep
M.lsp_declarations = M.live_grep
M.lsp_implementations = M.live_grep

-- Grouped-list headers for grep + LSP sources.
M.lsp_definitions_header = M.live_grep_header
M.lsp_references_header = M.live_grep_header
M.lsp_declarations_header = M.live_grep_header
M.lsp_implementations_header = M.live_grep_header

return M
