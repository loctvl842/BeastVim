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
---@field title? fun(filter?: Beast.Finder.Filter): string overrides the title derived from the source name; asked again at the start of every live search
---@field count? fun(items: Beast.Finder.Item[], total: integer): string text shown right-aligned in the prompt row once a search finishes (`total` = how many items match the pattern)
---@field check? fun(): boolean runs before the picker opens; false aborts (the source has already told the user why)
---@field preview? fun(view: Beast.Finder.PreviewView, item?: Beast.Finder.Item) replaces the file preview; item is nil when the list is empty
---@field format fun(item: Beast.Finder.Item, width?: integer): Beast.Finder.Highlight[] how a row looks (default: `format.filename`)
---@field header? fun(item: Beast.Finder.Item, width?: integer): Beast.Finder.Highlight[] grouped lists: the header drawn above the first row of each group
---@field group fun(item: Beast.Finder.Item): any rows with an equal group share one header (default: `item.file`)
---@field preview_highlight? "match"|"range" what the default file preview highlights: the grep match text, or the exact range an LSP server returned
---@field open fun(session: Beast.Finder.Session, item: Beast.Finder.Item) what Enter does with an item (default: open its url, else its file)
---@field reload_on string[] `User` events that load the source again while the picker is open (default: `{ "BeastVisibilityChanged" }`)

---@alias Beast.Finder.Source "files"|"buffers"|"live_grep"|"colorschemes"|"help_tags"|"lsp_definitions"|"lsp_references"|"lsp_declarations"|"lsp_implementations"|"gh_pr"|"gh_issue"

---@class Beast.Finder.SourceRegistry
---@field [Beast.Finder.Source] Beast.Finder.ASource
local M = {}

---@param item Beast.Finder.Item
---@return any
local function default_group(item)
	return item.file
end

--- Fill in what a source does not declare, so no other module has to ask which source it is dealing with.
---@param mod table the source module
---@param name string registry key
---@return Beast.Finder.ASource
local function normalize(mod, name)
	mod.name = name
	mod.format = mod.format or require("beast.libs.finder.format").filename
	mod.open = mod.open or require("beast.libs.finder.action").open_default
	mod.group = mod.group or default_group
	mod.reload_on = mod.reload_on or { "BeastVisibilityChanged" }
	return mod
end

setmetatable(M, {
	__index = function(_, k)
		return normalize(require("beast.libs.finder.source." .. k), k)
	end,
})

return M
