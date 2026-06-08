--- Shared factory for LSP-backed finder sources.
---
--- These sources never call the LSP themselves — the fetch is done up-front
--- by `finder/init.lua` so it can:
---   * jump directly when there's a single unique location (no picker flash),
---   * or pre-feed the picker with already-built items.
---
--- The source just yields whatever was captured in `filter.lsp.results`.

local M = {}

--- Build a single source table for one of the supported LSP methods.
---@param kind "definitions"|"references"|"declarations"
---@return Beast.Finder.ASource
function M.create(_kind)
	local source = {
		live = false,
		async = false,
	}

	---@param filter Beast.Finder.Filter
	---@return Beast.Finder.Item[]
	function source.get(filter)
		return (filter.lsp and filter.lsp.results) or {}
	end

	return source
end

return M
