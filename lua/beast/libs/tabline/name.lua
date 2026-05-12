local M = {}

--- Build unique display names for all buffers in a single O(N) pass.
--- Returns a table mapping bufnr → disambiguated name string.
---@param buffers integer[] List of buffer numbers
---@param raw_names? table<integer, string> Pre-fetched buffer names (optional)
---@return table<integer, string> names_by_buf
function M.build_names(buffers, raw_names)
	-- Group buffers by their tail filename
	local by_tail = {}
	local tails = {}
	for _, bufnr in ipairs(buffers) do
		local fullname = raw_names and raw_names[bufnr] or vim.api.nvim_buf_get_name(bufnr)
		local tail = fullname:match("[^/]+$") or ""
		if tail == "" then
			tail = "[No Name]"
		end
		tails[bufnr] = tail
		if not by_tail[tail] then
			by_tail[tail] = {}
		end
		table.insert(by_tail[tail], bufnr)
	end

	local result = {}
	for tail, group in pairs(by_tail) do
		if #group == 1 then
			result[group[1]] = tail
		else
			-- Disambiguate: find minimal parent prefix
			local paths = {}
			for _, bufnr in ipairs(group) do
				local fullpath = raw_names and raw_names[bufnr] or vim.api.nvim_buf_get_name(bufnr)
				paths[bufnr] = vim.split(fullpath, "/", { plain = true })
			end

			for _, bufnr in ipairs(group) do
				local parts = paths[bufnr]
				local depth = 2
				local found = false

				while depth <= #parts do
					local prefix = table.concat(vim.list_slice(parts, #parts - depth + 1, #parts), "/")
					local is_unique = true

					for _, other in ipairs(group) do
						if other ~= bufnr then
							local other_parts = paths[other]
							local other_prefix = table.concat(vim.list_slice(other_parts, #other_parts - depth + 1, #other_parts), "/")
							if prefix == other_prefix then
								is_unique = false
								break
							end
						end
					end

					if is_unique then
						if depth >= 2 then
							result[bufnr] = parts[#parts - 1] .. "/" .. parts[#parts]
						else
							result[bufnr] = prefix
						end
						found = true
						break
					end

					depth = depth + 1
				end

				if not found then
					result[bufnr] = tail
				end
			end
		end
	end

	return result
end

--- Truncate a text to a target display width with leading ellipsis.
---@param text string
---@param max_width integer
---@return string
function M.truncate_text(text, max_width)
	-- stylua: ignore
	if max_width == nil or max_width <= 0 then return "" end

	local len = #text
	-- Fast path: pure ASCII (byte length == display width)
	if not text:find("[\128-\255]") then
		-- stylua: ignore
		if len <= max_width then return text end
		-- stylua: ignore
		if max_width <= 1 then return "…" end
		return "…" .. text:sub(len - max_width + 2)
	end

	-- Slow path: multibyte characters
	local total_width = vim.fn.strdisplaywidth(text)
	-- stylua: ignore
	if total_width <= max_width then return text end

	-- stylua: ignore
	if max_width <= 1 then return "…" end

	local chars = vim.fn.strchars(text)
	local current_width = total_width
	local start_index = 0

	for i = 0, chars - 1 do
		-- stylua: ignore
		if current_width <= (max_width - 1) then break end
		local char = vim.fn.strcharpart(text, i, 1)
		current_width = current_width - vim.fn.strdisplaywidth(char)
		start_index = i + 1
	end

	return "…" .. vim.fn.strcharpart(text, start_index)
end

return M
