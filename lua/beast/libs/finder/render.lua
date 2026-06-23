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
---@param state Beast.Finder.State
function M.schedule_preview(state)
	local debounced = preview_debouncers[state.query]
	if not debounced then
		debounced = Util.debounce(config.debounce.preview_ms, function()
			-- stylua: ignore
			if not state.view.list:is_valid() then return end

			local item = ui.list.selected(state.view.list)

			if item then
				if state.view.preview then
					ui.preview.show(state.view.preview, item)

					-- Apply match highlights on preview for stream sources (grep)
					if state.query.highlight_preview and state.view.preview:is_valid() and state.query.filter.pattern ~= "" then
						match_hl.apply_preview(state.view.preview.buf, item.match_text, item.pos)
						vim.cmd("redraw")
					end

					-- LSP sources: highlight the EXACT range the server returned
					-- for this reference (not a substring of the symbol — that
					-- false-matches inside `module`, `modify`, etc.).
					if state.query.source.name:match("^lsp_") and state.view.preview:is_valid() then
						match_hl.apply_lsp_range(state.view.preview.buf, item.pos, item.end_pos)
						vim.cmd("redraw")
					end
				end

				if state.on_preview then
					state.on_preview(item)
				end
			else
				if state.view.preview then
					ui.preview.clear(state.view.preview)
				end
			end
		end)
		preview_debouncers[state.query] = debounced
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
---@param state Beast.Finder.State
function M.render(state)
	local raw_format = format[state.query.source.name] or format.filename
	-- Wrap format function to pass available width for path trimming
	local list_width = state.view.list:is_valid() and vim.api.nvim_win_get_width(state.view.list.win) or 80
	local format_fn = function(item)
		return raw_format(item, list_width)
	end
	ui.list.render(state.view.list, state.query.matched, format_fn)
	-- Apply fuzzy match highlights to list (match pipeline only, visible rows)
	if not state.query.highlight_preview and state.view.list:is_valid() then
		local from, to = ui.list.visible_range(state.view.list)
		match_hl.apply_list(state.view.list.buf, state.query.matched, format_fn, from, to)
	end
	M.schedule_preview(state)
	vim.cmd("redraw")
end

return M
