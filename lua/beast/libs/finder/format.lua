---@class Beast.Finder.Highlight
---@field text string
---@field hl string?

local M = {}

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

	-- Icon via global Icon if available
	local ok, icon, icon_hl = pcall(function()
		if Icon and Icon.get then
			local i, h = Icon.get(base)
			return i, h
		end
		return nil, nil
	end)
	if ok and icon then
		result[#result + 1] = { text = icon .. " ", hl = icon_hl }
	end

	if dir then
		result[#result + 1] = { text = dir .. "/", hl = "BeastFinderDir" }
	end
	result[#result + 1] = { text = base, hl = "BeastFinderFile" }

	return result
end

---@param item Beast.Finder.Item
---@return Beast.Finder.Highlight[]
function M.buffer(item)
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
		{ text = bufnr_str, hl = "BeastFinderDir" },
		{ text = name, hl = "BeastFinderFile" },
		{ text = modified, hl = "BeastFinderMatch" },
	}
end

return M
