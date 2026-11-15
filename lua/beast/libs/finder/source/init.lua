---@class Beast.Finder.ASource
---@field name Beast.Finder.Source  registry key, injected on resolve
---@field live boolean
---@field async boolean
---@field auto_select boolean  Jump to the item immediately if it's the only one
---@field label? string  Display label for the statusline pre-flight indicator (auto_select sources only)
---@field get fun(filter: Beast.Finder.Filter, cb?: fun(item: Beast.Finder.Item|nil))
---@field cmd? string
---@field args? string[]
---@field cancel? fun()
---@field initial_query? string live sources: prompt text the picker opens with, searched immediately
---@field retain_results? boolean live sources: keep the previous list on screen until the new results arrive
---@field run_when_empty? boolean live sources: search even when the prompt is empty
---@field debounce_ms? integer live sources: overrides `config.debounce.live_ms`
---@field title? fun(): string overrides the title derived from the source name
---@field count? fun(items: Beast.Finder.Item[]): string text shown right-aligned in the prompt row once a search finishes
---@field check? fun(): boolean runs before the picker opens; false aborts (the source has already told the user why)
---@field preview? fun(view: Beast.Finder.PreviewView, item: Beast.Finder.Item) replaces the file preview

---@alias Beast.Finder.Source "files"|"buffers"|"live_grep"|"colorschemes"|"help_tags"|"lsp_definitions"|"lsp_references"|"lsp_declarations"|"lsp_implementations"|"gh_pr"|"gh_issue"

---@class Beast.Finder.SourceRegistry
---@field [Beast.Finder.Source] Beast.Finder.ASource
local M = {}

setmetatable(M, {
	__index = function(_, k)
		local mod = require("beast.libs.finder.source." .. k)
		mod.name = k
		return mod
	end,
})

return M
