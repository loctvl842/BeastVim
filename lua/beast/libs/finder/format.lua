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
---@param max_width? integer available column width for trimming
---@return Beast.Finder.Highlight[]
function M.live_grep(item, max_width)
	local path = item.file or ""
	local cwd = item.cwd or vim.fn.getcwd()

	local rel = path
	if path:sub(1, #cwd) == cwd then
		rel = path:sub(#cwd + 2)
	end

	local base = rel:match("[^/]+$") or rel
	local lnum = item.pos and item.pos[1] or 0
	local text = item.grep_text or ""

	-- Trim the path portion if max_width provided
	local display_path = rel
	if max_width then
		local suffix = ":" .. lnum .. ": "
		local path_budget = max_width - #suffix - math.min(#text, 30)
		if path_budget > 0 and #rel > path_budget then
			local dir, fname = trim_path(rel, path_budget)
			display_path = (dir ~= "" and dir .. "/" or "") .. fname
		end
	end

	local result = {}

	local icon, icon_hl = get_icon(base)
	if icon then
		result[#result + 1] = { text = icon .. " ", hl = icon_hl }
	end

	result[#result + 1] = { text = display_path .. ":" .. lnum, hl = "BeastFinderListDir" }
	result[#result + 1] = { text = ": ", hl = "BeastFinderNormal" }
	result[#result + 1] = { text = text, hl = "BeastFinderListFile" }

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

-- LSP sources surface file:line + snippet, identical to live_grep.
M.lsp_definitions = M.live_grep
M.lsp_references = M.live_grep
M.lsp_declarations = M.live_grep
M.lsp_implementations = M.live_grep

return M
