--- A changed file's diff, as the finder shows it. One place knows a file's patch, its one-line summary and
--- what to say when there is no patch (binary, or too large for GitHub to return); it turns the patch into
--- rows for the shared diff renderer (`beast.libs.view.diff`) and draws them in the preview pane.
local View = require("beast.libs.view")
local view_diff = require("beast.libs.view.diff")

---@class Beast.Finder.UI.Diff
local M = {}

--- A file shows at most this many diff lines; the rest is counted in a note.
M.MAX_ROWS = 3000

---@class Beast.Finder.Diff.File
---@field status string added|removed|modified|renamed|...
---@field previous? string path before a rename
---@field additions integer
---@field deletions integer
---@field patch? string unified diff; absent for binary or very large diffs

local NO_DIFF = "(diff too large or binary)"
local BAR = 5 -- blocks in the +/- bar of the header
local MARKS = { ["+"] = "add", ["-"] = "del", [" "] = "ctx", ["\\"] = "note" }

--- "modified  +5 -6", then the `path` when given, then "(was <old path>)" for a rename.
---@param file Beast.Finder.Diff.File
---@param path? string
---@return string
function M.summary(file, path)
	local text = ("%-9s +%d -%d"):format(file.status, file.additions, file.deletions)
	if path then
		text = text .. "  " .. path
	end
	return file.previous and (text .. "  (was " .. file.previous .. ")") or text
end

--- The patch of a file as lines, or the one line saying there is none.
---@param file Beast.Finder.Diff.File
---@return string[]
function M.raw_lines(file)
	return file.patch and vim.split(file.patch, "\n", { plain = true }) or { NO_DIFF }
end

---@class Beast.Finder.Diff.Line
---@field kind "ctx" | "del" | "add" | "note"
---@field text string

---@class Beast.Finder.Diff.Hunk
---@field header string the "@@ -a,b +c,d @@ context" line as it came
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field lines Beast.Finder.Diff.Line[]

--- The hunks of a unified diff. A "\ No newline at end of file" line is a `note`; CRLF is dropped.
---@param patch string
---@return Beast.Finder.Diff.Hunk[]
function M.parse(patch)
	local lines = vim.split(patch:gsub("\r", ""), "\n", { plain = true })
	while lines[#lines] == "" do
		lines[#lines] = nil
	end
	local hunks, hunk = {}, nil
	for _, line in ipairs(lines) do
		local os, oc, ns, nc = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
		if os then
			hunk = {
				header = line,
				old_start = tonumber(os),
				old_count = oc == "" and 1 or tonumber(oc),
				new_start = tonumber(ns),
				new_count = nc == "" and 1 or tonumber(nc),
				lines = {},
			}
			hunks[#hunks + 1] = hunk
		elseif hunk then
			local kind = MARKS[line:sub(1, 1)]
			if kind == "note" then
				hunk.lines[#hunk.lines + 1] = { kind = kind, text = line }
			elseif kind then
				hunk.lines[#hunk.lines + 1] = { kind = kind, text = line:sub(2) }
			else
				-- A blank context line may have lost its leading space on the way.
				hunk.lines[#hunk.lines + 1] = { kind = "ctx", text = line }
			end
		end
	end
	return hunks
end

---@param n integer
---@return string
local function unchanged(n)
	return ("⋯ %d unchanged line%s"):format(n, n == 1 and "" or "s")
end

--- The header row: the summary and a bar of five blocks split between additions and deletions.
---@param file Beast.Finder.Diff.File
---@return Beast.View.DiffRow
local function head_row(file)
	local text = M.summary(file)
	local marks = {}
	local total = file.additions + file.deletions
	if total > 0 then
		local adds = math.floor(BAR * file.additions / total + 0.5)
		-- A side with changes always shows at least one block.
		adds = math.max(file.additions > 0 and 1 or 0, math.min(adds, file.deletions > 0 and BAR - 1 or BAR))
		text = text .. "  "
		local block = "■"
		for i = 1, BAR do
			local group = i <= adds and "BeastViewDiffStatAdd" or "BeastViewDiffStatDelete"
			marks[#marks + 1] = { #text, #text + #block, group }
			text = text .. block
		end
	end
	return { plain = true, sign = " ", text = text, hl = "BeastViewDiffHead", marks = marks }
end

--- The rows of one changed file: its header, then every hunk (a band, the lines with their numbers, the
--- unchanged lines hidden between hunks counted in a row of their own).
---@param file Beast.Finder.Diff.File
---@return Beast.View.DiffRow[]
function M.rows(file)
	local rows = { head_row(file) }
	if not file.patch then
		rows[#rows + 1] = { plain = true, sign = " ", text = NO_DIFF, hl = "BeastViewDiffGap" }
		return rows
	end

	local dels, adds = {}, {}
	local function flush()
		view_diff.pair(dels, adds)
		dels, adds = {}, {}
	end

	local shown, hidden_after = 0, 0
	local after ---@type integer? first old line after the previous hunk
	for _, hunk in ipairs(M.parse(file.patch)) do
		-- The first old line the hunk covers (a hunk with no old lines sits after line `old_start`).
		local first = hunk.old_count == 0 and hunk.old_start + 1 or hunk.old_start
		local gap = first - (after or 1)
		if gap > 0 then
			rows[#rows + 1] = {
				plain = true,
				sign = " ",
				text = unchanged(gap) .. (after and "" or " above"),
				hl = "BeastViewDiffGap",
			}
		end
		after = first + hunk.old_count
		rows[#rows + 1] = { plain = true, sign = " ", text = "▸ " .. hunk.header, hl = "BeastViewDiffHunk" }

		local old, new = hunk.old_start, hunk.new_start
		for _, line in ipairs(hunk.lines) do
			if shown >= M.MAX_ROWS then
				hidden_after = hidden_after + 1
			elseif line.kind == "note" then
				flush()
				rows[#rows + 1] = { plain = true, sign = " ", text = line.text, hl = "BeastViewDiffGap" }
			else
				shown = shown + 1
				if line.kind == "del" then
					if #adds > 0 then
						flush()
					end
					local row = { sign = "-", old = old, text = line.text }
					dels[#dels + 1] = row
					rows[#rows + 1] = row
					old = old + 1
				elseif line.kind == "add" then
					local row = { sign = "+", new = new, text = line.text }
					adds[#adds + 1] = row
					rows[#rows + 1] = row
					new = new + 1
				else
					flush()
					rows[#rows + 1] = { sign = " ", old = old, new = new, text = line.text }
					old, new = old + 1, new + 1
				end
			end
		end
		flush()
	end
	if hidden_after > 0 then
		rows[#rows + 1] = {
			plain = true,
			sign = " ",
			text = ("(%d more lines not shown)"):format(hidden_after),
			hl = "BeastViewDiffGap",
		}
	end
	return rows
end

--- Draw `rows` in the preview pane: lines, tints, the number gutter, and the window set up to show them
--- (long lines wrap). The pane is shared with the other levels, so every other writer calls `leave` first.
---@param view Beast.Finder.PreviewView
---@param rows Beast.View.DiffRow[]
---@param title string
function M.draw(view, rows, title)
	-- stylua: ignore
	if not view:is_valid() then return end
	local rendered = view_diff.render(rows, { columns = 2 })
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, rendered.body)
	vim.bo[view.buf].modifiable = false
	vim.bo[view.buf].filetype = ""
	view_diff.paint(view.buf, rendered)
	view_diff.attach(view.win, rendered.width)
	View.win.wo(view.win, "wrap", true)
	view.diff_drawn = true
	-- The pane shows a diff, not a file of the working tree.
	view.loaded_file = nil
	pcall(vim.api.nvim_win_set_config, view.win, { title = title, title_pos = "center" })
	pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
end

--- Undo what `draw` did to the pane, if it drew; a no-op otherwise.
---@param view Beast.Finder.PreviewView
function M.leave(view)
	-- stylua: ignore
	if not view.diff_drawn then return end
	view.diff_drawn = nil
	if view:is_valid() then
		view_diff.clear(view.buf)
		view_diff.detach(view.win)
		View.win.wo(view.win, "wrap", false)
	end
end

return M
