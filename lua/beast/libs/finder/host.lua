--- What a pipeline (engine) may tell whoever owns it, so engines never touch windows.
--- The picker builds a host that draws into its windows; headless clients (search.lua,
--- tests) use `headless()`.

---@class Beast.Finder.Host
---@field alive fun(): boolean false once the owner is closed or no longer showing this query; engines drop late work
---@field render fun() `query.matched` changed
---@field busy fun(on: boolean) a search is running (spinner)
---@field rewind fun() the results were replaced wholesale: start again from the first row
---@field count fun(text?: string) text for the prompt's count label; nil or "" clears it
---@field title fun(text: string) text for the prompt's title
---@field rows fun(): integer visible list rows (the stream pipeline sizes its render budget with it)

---@class Beast.Finder.HostModule
local M = {}

--- A host that draws nothing. `overrides` replaces any of its methods.
---@param overrides? table
---@return Beast.Finder.Host
function M.headless(overrides)
	return vim.tbl_extend("force", {
		alive = function()
			return true
		end,
		render = function() end,
		busy = function() end,
		rewind = function() end,
		count = function() end,
		title = function() end,
		rows = function()
			return 50
		end,
	}, overrides or {})
end

return M
