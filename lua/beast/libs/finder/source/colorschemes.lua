local swatches = require("beast.libs.finder.source.colorscheme_swatches")

local M = {}

M.format = require("beast.libs.finder.format").colorschemes
-- The picker only shows what the swatch worker has computed, so it reloads when that finishes.
M.reload_on = { "BeastFinderSwatchesReady" }

--- Apply the theme. The live preview has usually applied it already; re-applying would repaint the editor again.
---@param item Beast.Finder.Item
function M.open(_, item)
	if vim.g.colors_name ~= item.text then
		pcall(vim.cmd.colorscheme, item.text)
	end
end

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
	local found = {} ---@type {name: string, path: string, rank: integer}[]

	for _, pattern in ipairs({ "colors/*.vim", "colors/*.lua" }) do
		local files = vim.fn.globpath(rtp, pattern, true, true)
		for _, fullpath in ipairs(files) do
			local name = vim.fn.fnamemodify(fullpath, ":t:r")
			if not seen[name] then
				seen[name] = true
				found[#found + 1] = { name = name, path = fullpath, rank = rank(fullpath) }
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
			swatches = swatches.get(entry.name, entry.path),
		}
	end

	-- Fill in missing swatches in the background; the picker reloads on this event.
	swatches.ensure(found, function()
		vim.api.nvim_exec_autocmds("User", { pattern = "BeastFinderSwatchesReady", modeline = false })
	end)

	return items
end

return M
