local palette = require("beast.theme.palette")
local sources = require("beast.theme.sources")

---@class Beast.Theme
local M = {}

---@type Beast.Theme.Palette
local cache = vim.deepcopy(palette.defaults)

--- Kind of the active colorscheme (resolved live, so it is valid before the
--- first `refresh()`).
---   beastvim: this config's `colors/`
---   nvim:     Neovim's `$VIMRUNTIME/colors`
---   plugin:   any third-party colorscheme
---@return "beastvim"|"nvim"|"plugin"
function M.kind()
	return sources.detect().name
end

--- Re-extract all palette colors from the current colorscheme.
function M.refresh()
	local source = sources.detect()
	cache = source.extract()
	if source.post_apply then
		source.post_apply(cache)
	end
end

--- Get the current palette (read-only snapshot).
---@return Beast.Theme.Palette
function M.get()
	return cache
end

function M.setup()
	require("beast").apply_highlights("beast.theme.highlights")
	require("beast").apply_highlights("beast.theme.blink")
end

return M
