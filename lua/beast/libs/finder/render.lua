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
---@param session Beast.Finder.Session
function M.schedule_preview(session)
	local debounced = preview_debouncers[session.level.query]
	if not debounced then
		debounced = Util.debounce(config.debounce.preview_ms, function()
			-- stylua: ignore
			if not session.view.list:is_valid() then return end

			local item = ui.list.selected(session.view.list)

			if item then
				if session.view.preview and session.level.query.source.preview then
					session.level.query.source.preview(session.view.preview, item)
				elseif session.view.preview then
					ui.preview.show(session.view.preview, item)

					local highlight = session.level.query.source.preview_highlight
					-- "match": highlight the literal grep matched (stream sources)
					if highlight == "match" and session.view.preview:is_valid() and session.level.query.filter.pattern ~= "" then
						match_hl.apply_preview(session.view.preview.buf, item.match_text, item.pos)
						vim.cmd("redraw")
					end

					-- "range": highlight the EXACT range the LSP server returned
					-- for this reference (not a substring of the symbol — that
					-- false-matches inside `module`, `modify`, etc.).
					if highlight == "range" and session.view.preview:is_valid() then
						match_hl.apply_lsp_range(session.view.preview.buf, item.pos, item.end_pos)
						vim.cmd("redraw")
					end
				end

				if session.on_preview then
					session.on_preview(item)
				end
			else
				if session.view.preview and session.level.query.source.preview then
					session.level.query.source.preview(session.view.preview, nil)
				elseif session.view.preview then
					ui.preview.clear(session.view.preview)
				end
			end
		end)
		preview_debouncers[session.level.query] = debounced
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
---@param session Beast.Finder.Session
---@return fun(item: Beast.Finder.Item): Beast.Finder.Highlight[] format_fn
---@return (fun(item: Beast.Finder.Item): Beast.Finder.Highlight[])? header_fn
function M.formatters(session)
	local source = session.level.query.source
	local list_width = session.view.list:is_valid() and vim.api.nvim_win_get_width(session.view.list.win) or 80
	local format_fn = function(item)
		return source.format(item, list_width)
	end
	local header_fn = source.header and function(item)
		return source.header(item, list_width)
	end or nil
	return format_fn, header_fn
end

--- Format items → write to list buffer → apply match highlights → trigger preview → redraw.
---@param session Beast.Finder.Session
function M.render(session)
	local format_fn, header_fn = M.formatters(session)
	-- First render with items: start on the requested item instead of the top one.
	if session.initial_text and not session.initial_done and #session.level.query.matched > 0 then
		session.initial_done = true
		for i, item in ipairs(session.level.query.matched) do
			if item.text == session.initial_text then
				session.view.list.cursor = i
				break
			end
		end
	end
	ui.list.render(session.view.list, session.level.query.matched, format_fn, header_fn, session.level.query.source.group)
	-- Apply fuzzy match highlights to list (match pipeline only, visible rows)
	if not session.level.query.source.live and session.view.list:is_valid() then
		local from, to = ui.list.visible_range(session.view.list)
		match_hl.apply_list(session.view.list.buf, session.level.query.matched, format_fn, from, to, session.view.list._separators and 2 or 1)
	end
	M.schedule_preview(session)
	vim.cmd("redraw")
end

return M
