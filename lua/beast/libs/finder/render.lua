--- Shared rendering logic for the finder UI.
--- Formats items, writes to list buffer, applies match highlights, triggers preview.
local config = require("beast.libs.finder.config")
local format = require("beast.libs.finder.format")
local match_hl = require("beast.libs.finder.match_hl")
local ui = require("beast.libs.finder.ui")

local M = {}

--- Per-query preview debouncers (keyed by query table reference).
---@type table<Beast.Finder.Query, Beast.Util.Debouncer>
local preview_debouncers = {}

--- Debounce preview window updates — waits N ms after cursor moves before loading file content.
---@param query Beast.Finder.Query
function M.schedule_preview(query)
	local debounced = preview_debouncers[query]
	if not debounced then
		debounced = Util.debounce(config.debounce.preview_ms, function()
			-- stylua: ignore
			if not query.list_view:is_valid() then return end

			local item = ui.list.selected(query.list_view)

			if item then
				if query.preview_view then
					ui.preview.show(query.preview_view, item)

					-- Apply match highlights on preview for stream sources (grep)
					if query.highlight_preview and query.preview_view:is_valid() and query.filter.pattern ~= "" then
						match_hl.apply_preview(query.preview_view.buf, item.match_text, item.pos)
						vim.cmd("redraw")
					end

					-- LSP sources: highlight the EXACT range the server returned
					-- for this reference (not a substring of the symbol — that
					-- false-matches inside `module`, `modify`, etc.).
					if query.filter and query.filter.lsp and query.preview_view:is_valid() then
						match_hl.apply_lsp_range(query.preview_view.buf, item.pos, item.end_pos)
						vim.cmd("redraw")
					end
				end

				if query._on_preview then
					query._on_preview(item)
				end
			else
				if query.preview_view then
					ui.preview.clear(query.preview_view)
				end
			end
		end)
		preview_debouncers[query] = debounced
	end
	debounced()
end

--- Clean up the preview debouncer for a query (call from close).
---@param query Beast.Finder.Query
function M.cleanup(query)
	local debounced = preview_debouncers[query]
	if debounced then
		debounced:close()
		preview_debouncers[query] = nil
	end
end

--- Format items → write to list buffer → apply match highlights → trigger preview → redraw.
---@param query Beast.Finder.Query
function M.render(query)
	local raw_format = format[query.source] or format.filename
	-- Wrap format function to pass available width for path trimming
	local list_width = query.list_view:is_valid() and vim.api.nvim_win_get_width(query.list_view.win) or 80
	local format_fn = function(item)
		return raw_format(item, list_width)
	end
	ui.list.render(query.list_view, query.matched, format_fn)
	-- Apply fuzzy match highlights to list (match pipeline only, visible rows)
	if not query.highlight_preview and query.list_view:is_valid() then
		local from, to = ui.list.visible_range(query.list_view)
		match_hl.apply_list(query.list_view.buf, query.matched, format_fn, from, to)
	end
	M.schedule_preview(query)
	vim.cmd("redraw")
end

return M
