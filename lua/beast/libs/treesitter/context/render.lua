-- Sticky-context rendering.
--
-- Draws the computed context as floating overlays pinned to the top of the
-- source window:
--   * a content float holding the header text, syntax-highlighted by copying
--     the live buffer's treesitter (and core) extmarks, and
--   * a gutter float that re-evaluates the window's `statuscolumn` for each
--     context line so the sticky overlay covers the number/sign column too
--     (this is the "cover the statuscolumn" behaviour) rather than leaving a
--     bare gap on the left.
--
-- Ported from nvim-treesitter-context (MIT, see queries/NOTICE), reduced to a
-- single source window with no separator and backed by Beast's View wrappers.

local api, fn = vim.api, vim.fn
local highlighter = vim.treesitter.highlighter

local config = require("beast.libs.treesitter.config")

local M = {}

local ns = api.nvim_create_namespace("beastvim_treesitter_context")

-- Floats per source window, keyed by window id. Reused across renders;
-- reconfigured in place while valid and only recreated after a close. Keeping a
-- map (rather than a single set) lets the overlay persist in every split at
-- once, independent of which window is focused.
---@type table<integer, { content: Beast.View.Instance?, gutter: Beast.View.Instance? }>
local states = {}

-- ===========================================================================
-- LOW-LEVEL HELPERS
-- ===========================================================================

---@param range Range4
---@return integer
local function range_height(range)
	return range[3] - range[1] + (range[4] == 0 and 0 or 1)
end

--- Width of the source window's gutter (number + sign + fold columns).
---@param winid integer
---@return integer
local function get_gutter_width(winid)
	return fn.getwininfo(winid)[1].textoff
end

---@param name string
---@param from_buf integer
---@param to_buf integer
local function copy_option(name, from_buf, to_buf)
	local current = vim.bo[from_buf][name]
	if current ~= vim.bo[to_buf][name] then
		vim.bo[to_buf][name] = current
	end
end

---@param bufnr integer
---@param row integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
---@param ns0? integer
local function add_extmark(bufnr, row, col, opts, ns0)
	pcall(api.nvim_buf_set_extmark, bufnr, ns0 or ns, row, col, opts)
end

---@param arow integer
---@param acol integer
---@param brow integer
---@param bcol integer
---@return boolean
local function is_after(arow, acol, brow, bcol)
	return arow > brow or (arow == brow and acol > bcol)
end

--- Replace the lines of `bufnr` only when they actually changed (avoids redraw
--- churn while scrolling within the same context).
---@param bufnr integer
---@param lines string[]
---@return boolean changed
local function set_lines(bufnr, lines)
	local current = api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local changed = #current ~= #lines
	if not changed then
		for i, line in ipairs(current) do
			if line ~= lines[i] then
				changed = true
				break
			end
		end
	end

	if changed then
		vim.bo[bufnr].modifiable = true
		api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.bo[bufnr].modifiable = false
		vim.bo[bufnr].modified = false
	end

	return changed
end

-- ===========================================================================
-- FLOAT LIFECYCLE
-- ===========================================================================

---@param view Beast.View.Instance?
---@param winid integer
---@param width integer
---@param height integer
---@param col integer
---@param winhl string
---@return Beast.View.Instance?
local function display_window(view, winid, width, height, col, winhl)
	if view and view:is_valid() then
		pcall(api.nvim_win_set_config, view.win, {
			win = winid,
			relative = "win",
			width = width,
			height = height,
			row = 0,
			col = col,
		})
		return view
	end

	local buf = View.buf.new("beast-treesitter-context")
	local ok, win = pcall(api.nvim_open_win, buf, false, {
		win = winid,
		relative = "win",
		width = width,
		height = height,
		row = 0,
		col = col,
		focusable = false,
		style = "minimal",
		noautocmd = true,
		zindex = config.context.zindex or 20,
		border = "none",
	})
	if not ok or not win then
		pcall(api.nvim_buf_delete, buf, { force = true })
		return nil
	end

	View.win.wo(win, "wrap", false)
	View.win.wo(win, "foldenable", false)
	View.win.wo(win, "winhighlight", "Normal:" .. winhl)
	View.win.wo(win, "winblend", 0)
	return View(buf, win)
end

--- Match the context float's horizontal scroll to the source window so long
--- header lines line up under the code.
---@param winid integer
---@param ctx_winid integer
local function sync_horizontal_scroll(winid, ctx_winid)
	local src = api.nvim_win_call(winid, fn.winsaveview)
	local ctx = api.nvim_win_call(ctx_winid, fn.winsaveview)
	if src.leftcol ~= ctx.leftcol then
		api.nvim_win_call(ctx_winid, function()
			fn.winrestview({ leftcol = src.leftcol })
		end)
	end
end

-- ===========================================================================
-- CONTENT HIGHLIGHTING
-- ===========================================================================

---@param buf_query vim.treesitter.highlighter.Query
---@param capture integer
---@return integer?
local function get_hl(buf_query, capture)
	---@diagnostic disable-next-line: invisible
	if buf_query.get_hl_from_capture then
		---@diagnostic disable-next-line: invisible
		return buf_query:get_hl_from_capture(capture)
	end
	---@diagnostic disable-next-line: invisible
	return buf_query.hl_cache[capture]
end

--- Re-create the source buffer's treesitter highlights inside the context
--- buffer by replaying its captures against the pinned ranges.
---@param bufnr integer
---@param ctx_bufnr integer
---@param contexts Range4[]
local function highlight_contexts(bufnr, ctx_bufnr, contexts)
	local buf_highlighter = highlighter.active[bufnr]

	copy_option("tabstop", bufnr, ctx_bufnr)

	if not buf_highlighter then
		-- No treesitter highlighting: fall back to legacy syntax via filetype.
		copy_option("filetype", bufnr, ctx_bufnr)
		return
	end

	buf_highlighter.tree:for_each_tree(function(tstree, ltree)
		---@diagnostic disable-next-line: invisible
		local buf_query = buf_highlighter:get_query(ltree:lang())
		---@diagnostic disable-next-line: invisible
		local query = buf_query:query()
		if not query then
			return
		end

		local offset = 0
		for _, context in ipairs(contexts) do
			local pri_offset = 0
			local start_row, end_row, end_col = context[1], context[3], context[4]

			for capture, node, metadata in query:iter_captures(tstree:root(), bufnr, start_row, end_row + 1) do
				local range = vim.treesitter.get_range(node, bufnr, metadata[capture])
				local nsrow, nscol, nerow, necol = range[1], range[2], range[4], range[5]

				if nsrow >= start_row then
					if is_after(nsrow, nscol, end_row, end_col) then
						break
					elseif is_after(nerow, necol, end_row, end_col) then
						nerow, necol = end_row, end_col
					end

					local msrow = offset + (nsrow - start_row)
					local merow = offset + (nerow - start_row)
					local priority = tonumber(metadata.priority) or (vim.hl and vim.hl.priorities.treesitter) or vim.highlight.priorities.treesitter
					local conceal = metadata.conceal or (metadata[capture] and metadata[capture].conceal)

					add_extmark(ctx_bufnr, msrow, nscol, {
						end_row = merow,
						end_col = necol,
						priority = priority + pri_offset,
						hl_group = get_hl(buf_query, capture),
						conceal = conceal,
					})
					pri_offset = pri_offset + 1
				end
			end
			offset = offset + range_height(context)
		end
	end)
end

--- Copy core (`nvim.*`) extmarks (diagnostics underlines, LSP semantic tokens,
--- inlay hints, …) from the source buffer onto the matching context rows.
---@param bufnr integer
---@param ctx_bufnr integer
---@param contexts Range4[]
local function copy_extmarks(bufnr, ctx_bufnr, contexts)
	local core_ns = {} ---@type table<integer, true>
	for name, id in pairs(api.nvim_get_namespaces()) do
		if vim.startswith(name, "nvim.") then
			core_ns[id] = true
		end
	end

	local offset = 0
	for _, context in ipairs(contexts) do
		local csrow, cscol, cerow, cecol = context[1], context[2], context[3], context[4]
		local marks = api.nvim_buf_get_extmarks(bufnr, -1, { csrow, cscol }, { cerow, cecol }, { details = true })

		for _, mark in ipairs(marks) do
			local row, col = mark[2], mark[3]
			local opts = mark[4] --[[@as vim.api.keyset.extmark_details]]
			if core_ns[opts.ns_id] then
				local end_row, end_col = nil, opts.end_col
				if opts.end_row then
					local mend_row = opts.end_row
					if is_after(mend_row, end_col or 0, cerow, cecol) then
						mend_row, end_col = cerow, cecol
					end
					end_row = offset + (mend_row - csrow)
				end

				local virt_text_pos = opts.virt_text_pos
				if virt_text_pos == "win_col" then
					virt_text_pos = nil
				end

				add_extmark(ctx_bufnr, offset + (row - csrow), col, {
					end_row = end_row,
					end_col = end_col,
					priority = opts.priority,
					hl_group = opts.hl_group,
					hl_eol = opts.hl_eol,
					virt_text = opts.virt_text,
					virt_text_pos = virt_text_pos,
					hl_mode = opts.hl_mode,
					line_hl_group = opts.line_hl_group,
					conceal = opts.conceal,
				}, opts.ns_id)
			end
		end
		offset = offset + range_height(context)
	end
end

--- Underline the last row of a float to mark the context/content boundary.
---@param bufnr integer
---@param row integer
---@param hl_group string
local function highlight_bottom(bufnr, row, hl_group)
	add_extmark(bufnr, row, 0, { end_line = row + 1, hl_group = hl_group, hl_eol = true })
end

-- ===========================================================================
-- GUTTER (STATUSCOLUMN) RENDERING
-- ===========================================================================

---@param ctx_line integer
---@param win integer
---@return integer
local function relative_line_num(ctx_line, win)
	local cursor_line = fn.line(".", win)
	local folded = 0
	local current = ctx_line
	while current < cursor_line do
		local fold_end = fn.foldclosedend(current)
		if fold_end == -1 then
			current = current + 1
		else
			folded = folded + fold_end - current
			current = fold_end + 1
		end
	end
	return cursor_line - ctx_line - folded
end

--- Evaluate the window's statuscolumn for line `lnum` (text + highlight spans),
--- falling back to a plain number when no statuscolumn is set.
---@param win integer
---@param lnum integer
---@param width integer
---@return string, table[]?
local function build_lno_str(win, lnum, width)
	local has_col, statuscol = pcall(api.nvim_get_option_value, "statuscolumn", { win = win, scope = "local" })
	if has_col and statuscol and statuscol ~= "" then
		local ok, data = pcall(api.nvim_eval_statusline, statuscol, {
			winid = win,
			use_statuscol_lnum = lnum,
			highlights = true,
			fillchar = " ",
		})
		if ok then
			return data.str, data.highlights
		end
	end
	local relnum
	if vim.wo[win].relativenumber then
		relnum = relative_line_num(lnum, win)
	end
	return string.format("%" .. width .. "d", relnum or lnum)
end

---@param buf integer
---@param text string[]
---@param highlights table[][]
local function highlight_lno_str(buf, text, highlights)
	for line, linehl in ipairs(highlights) do
		for hlidx, hl in ipairs(linehl) do
			local col = hl.start
			local endcol = hlidx < #linehl and linehl[hlidx + 1].start or #text[line]
			if col ~= endcol then
				local groups = hl.groups or { hl.group }
				for i, group in ipairs(groups) do
					-- Recolour the line-number segments so they read as context.
					groups[i] = group:find("LineNr") and "BeastTreesitterContextLineNumber" or group
				end
				add_extmark(buf, line - 1, col, {
					end_col = endcol,
					hl_group = hl.groups and groups or groups[1],
				})
			end
		end
	end
end

---@param win integer
---@param buf integer
---@param contexts Range4[]
---@param gutter_width integer
local function render_gutter(win, buf, contexts, gutter_width)
	local text = {} ---@type string[]
	local highlights = {} ---@type table[][]

	for _, range in ipairs(contexts) do
		for i = 1, range_height(range) do
			local str, hl = build_lno_str(win, range[1] + i, gutter_width - 1)
			text[#text + 1] = str
			highlights[#highlights + 1] = hl or {}
		end
	end

	set_lines(buf, text)
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	highlight_lno_str(buf, text, highlights)
	highlight_bottom(buf, #text - 1, "BeastTreesitterContextLineNumberBottom")
end

-- ===========================================================================
-- PUBLIC API
-- ===========================================================================

--- Open or update the context overlays for `winid`.
---@param winid integer
---@param ranges Range4[]
---@param lines string[]
---@param force_hl? boolean
function M.open(winid, ranges, lines, force_hl)
	local bufnr = api.nvim_win_get_buf(winid)
	local gutter_width = get_gutter_width(winid)
	local content_width = math.max(1, api.nvim_win_get_width(winid) - gutter_width)
	local height = math.max(1, #lines)

	local st = states[winid] or {}
	states[winid] = st

	-- Gutter float (statuscolumn coverage).
	local want_gutter = gutter_width > 0 and (config.context.line_numbers ~= false)
	if want_gutter then
		st.gutter = display_window(st.gutter, winid, gutter_width, height, 0, "BeastTreesitterContextLineNumber")
		if st.gutter and st.gutter:is_valid() and (vim.wo[winid].number or vim.wo[winid].relativenumber) then
			render_gutter(winid, st.gutter.buf, ranges, gutter_width)
		end
	elseif st.gutter then
		st.gutter:close()
		st.gutter = nil
	end

	-- Content float.
	st.content = display_window(st.content, winid, content_width, height, gutter_width, "BeastTreesitterContext")
	if not st.content or not st.content:is_valid() then
		return
	end

	local ctx_bufnr = st.content.buf
	local changed = set_lines(ctx_bufnr, lines)

	if changed or force_hl then
		api.nvim_buf_clear_namespace(ctx_bufnr, ns, 0, -1)
		highlight_contexts(bufnr, ctx_bufnr, ranges)
		copy_extmarks(bufnr, ctx_bufnr, ranges)
		highlight_bottom(ctx_bufnr, height - 1, "BeastTreesitterContextBottom")
		sync_horizontal_scroll(winid, st.content.win)
	end
end

--- Close the context overlays for a single source window.
---@param winid integer
function M.close(winid)
	local st = states[winid]
	if not st then
		return
	end
	if st.content then
		st.content:close()
	end
	if st.gutter then
		st.gutter:close()
	end
	states[winid] = nil
end

--- Close every context overlay.
function M.close_all()
	for winid in pairs(states) do
		M.close(winid)
	end
end

--- Close the overlays of every window not present in `keep` (a set of window
--- ids). Used to garbage-collect floats for windows that closed or became
--- ineligible.
---@param keep table<integer, true>
function M.close_except(keep)
	for winid in pairs(states) do
		if not keep[winid] then
			M.close(winid)
		end
	end
end

return M
