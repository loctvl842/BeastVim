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

---@param item Beast.Finder.Item
---@return Beast.Finder.Highlight[]
function M.filename(item)
	local path = item.file or item.text or ""
	local cwd = item.cwd or vim.fn.getcwd()

	-- Make relative to cwd
	local rel = path
	if path:sub(1, #cwd) == cwd then
		rel = path:sub(#cwd + 2) -- skip trailing /
	end

	local dir = rel:match("^(.+)/[^/]+$")
	local base = rel:match("[^/]+$") or rel

	local result = {}

	local icon, icon_hl = get_icon(base)
	if icon then
		result[#result + 1] = { text = icon .. " ", hl = icon_hl }
	end

	if dir then
		result[#result + 1] = { text = dir .. "/", hl = "BeastFinderListDir" }
	end
	result[#result + 1] = { text = base, hl = "BeastFinderListFile" }

	return result
end

---@param item Beast.Finder.Item
---@return Beast.Finder.Highlight[]
function M.live_grep(item)
	local path = item.file or ""
	local cwd = item.cwd or vim.fn.getcwd()

	local rel = path
	if path:sub(1, #cwd) == cwd then
		rel = path:sub(#cwd + 2)
	end

	local base = rel:match("[^/]+$") or rel
	local lnum = item.pos and item.pos[1] or 0
	local text = item.grep_text or ""

	local result = {}

	local icon, icon_hl = get_icon(base)
	if icon then
		result[#result + 1] = { text = icon .. " ", hl = icon_hl }
	end

	result[#result + 1] = { text = rel .. ":" .. lnum, hl = "BeastFinderListDir" }
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

return M
