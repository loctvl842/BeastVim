local M = {}

---Rank by origin, mirroring beast.theme.sources precedence:
---1 = BeastVim config `colors/`, 2 = Neovim builtin, 3 = plugin.
---@param fullpath string
---@return integer
local function rank(fullpath)
	local dir = vim.fs.dirname(fullpath)
	if dir == vim.fs.normalize(vim.fn.stdpath("config") .. "/colors") then
		return 1
	end
	if dir == vim.fs.normalize(vim.env.VIMRUNTIME .. "/colors") then
		return 2
	end
	return 3
end

---@return Beast.Finder.Item[]
function M.get()
	-- Only include colorschemes from currently loaded plugins (in rtp)
	local rtp = vim.o.runtimepath
	local seen = {} ---@type table<string, boolean>
	local found = {} ---@type {name: string, rank: integer}[]

	for _, pattern in ipairs({ "colors/*.vim", "colors/*.lua" }) do
		local files = vim.fn.globpath(rtp, pattern, true, true)
		for _, fullpath in ipairs(files) do
			local name = vim.fn.fnamemodify(fullpath, ":t:r")
			if not seen[name] then
				seen[name] = true
				found[#found + 1] = { name = name, rank = rank(fullpath) }
			end
		end
	end

	table.sort(found, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.name < b.name
	end)

	local items = {}
	for idx, entry in ipairs(found) do
		items[idx] = {
			idx = idx,
			score = 0,
			text = entry.name,
		}
	end

	return items
end

return M
