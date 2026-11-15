--- Shared rendering logic for the finder UI.
--- Formats items, writes to list buffer, applies match highlights, triggers preview.
local config = require("beast.libs.finder.config")
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
				if state.view.preview and state.query.source.preview then
					state.query.source.preview(state.view.preview, item)
				elseif state.view.preview then
					ui.preview.show(state.view.preview, item)

					local highlight = state.query.source.preview_highlight
					-- "match": highlight the literal grep matched (stream sources)
					if highlight == "match" and state.view.preview:is_valid() and state.query.filter.pattern ~= "" then
						match_hl.apply_preview(state.view.preview.buf, item.match_text, item.pos)
						vim.cmd("redraw")
					end

					-- "range": highlight the EXACT range the LSP server returned
					-- for this reference (not a substring of the symbol — that
					-- false-matches inside `module`, `modify`, etc.).
					if highlight == "range" and state.view.preview:is_valid() then
						match_hl.apply_lsp_range(state.view.preview.buf, item.pos, item.end_pos)
						vim.cmd("redraw")
					end
				end

				if state.on_preview then
					state.on_preview(item)
				end
			else
				if state.view.preview and state.query.source.preview then
					state.query.source.preview(state.view.preview, nil)
				elseif state.view.preview then
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

--- How this picker draws its rows: the source's formatters, told how wide the list is (for path trimming).
--- Grouped sources (grep/LSP) also have a header formatter: matches are grouped under a single
--- file-path header instead of repeating the path.
---@param state Beast.Finder.State
---@return fun(item: Beast.Finder.Item): Beast.Finder.Highlight[] format_fn
---@return (fun(item: Beast.Finder.Item): Beast.Finder.Highlight[])? header_fn
function M.formatters(state)
	local source = state.query.source
	local list_width = state.view.list:is_valid() and vim.api.nvim_win_get_width(state.view.list.win) or 80
	local format_fn = function(item)
		return source.format(item, list_width)
	end
	local header_fn = source.header and function(item)
		return source.header(item, list_width)
	end or nil
	return format_fn, header_fn
end

--- Format items → write to list buffer → apply match highlights → trigger preview → redraw.
---@param state Beast.Finder.State
function M.render(state)
	local format_fn, header_fn = M.formatters(state)
	-- First render with items: start on the requested item instead of the top one.
	if state.initial_text and not state.initial_done and #state.query.matched > 0 then
		state.initial_done = true
		for i, item in ipairs(state.query.matched) do
			if item.text == state.initial_text then
				state.view.list.cursor = i
				break
			end
		end
	end
	ui.list.render(state.view.list, state.query.matched, format_fn, header_fn, state.query.source.group)
	-- Apply fuzzy match highlights to list (match pipeline only, visible rows)
	if not state.query.source.live and state.view.list:is_valid() then
		local from, to = ui.list.visible_range(state.view.list)
		match_hl.apply_list(state.view.list.buf, state.query.matched, format_fn, from, to, state.view.list._separators and 2 or 1)
	end
	M.schedule_preview(state)
	vim.cmd("redraw")
end

return M
