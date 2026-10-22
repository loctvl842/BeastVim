-- Display-only painting of one hunk. Nothing here edits buffer text, so
-- conflict markers can never reach disk.
--
--   Current lines  -> red band (line_hl_group) + trailing label
--   Incoming lines -> green virt_lines under the last Current line
--
-- Position is always read back from extmarks (`locate`), never cached, so
-- earlier accepts that shift line numbers cannot misplace later hunks.

local api = vim.api

local M = {}

local NS = api.nvim_create_namespace("beast_review")

M.namespace = NS

local HL_CURRENT = "BeastReviewCurrent"
local HL_INCOMING = "BeastReviewIncoming"
local HL_LABEL = "BeastReviewLabel"

---@class Beast.Review.Marks
---@field ids integer[]      every extmark painted for the hunk
---@field first? integer     extmark on the first Current line
---@field last? integer      extmark on the last Current line
---@field anchor? integer    extmark of a pure insertion (no Current lines)
---@field after? boolean     anchor sits on the line *before* the insertion point

---@param buf integer
---@return integer
local function band_width(buf)
	local win = vim.fn.bufwinid(buf)
	if win == -1 then
		return 80
	end
	return api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

---@param s string
---@param width integer
local function pad(s, width)
	return s .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(s)))
end

---@param buf integer
---@param h Beast.Review.Hunk
---@param tag string  "i/n"
---@return table[][]? virt_lines
local function incoming_lines(buf, h, tag)
	if #h.new == 0 then
		return nil
	end
	local width = band_width(buf)
	local tab = string.rep(" ", vim.bo[buf].tabstop)
	local label = "  ← Incoming (Claude) " .. tag
	local virt = {}
	for i, line in ipairs(h.new) do
		line = line:gsub("\t", tab)
		if i == 1 then
			virt[i] = { { pad(line, width - vim.fn.strdisplaywidth(label)), HL_INCOMING }, { label, HL_LABEL } }
		else
			virt[i] = { { pad(line, width), HL_INCOMING } }
		end
	end
	return virt
end

---@param buf integer
---@param row integer
---@param opts table
---@param marks Beast.Review.Marks
---@return integer id
local function mark(buf, row, opts, marks)
	-- Invalidate (rather than collapse onto a neighbour) when the user deletes
	-- the line, so `locate` can tell the hunk is gone.
	opts.invalidate = true
	opts.undo_restore = false
	local id = api.nvim_buf_set_extmark(buf, NS, row, 0, opts)
	marks.ids[#marks.ids + 1] = id
	return id
end

--- Paint `h` over `buf`.
---@param buf integer
---@param h Beast.Review.Hunk
---@param idx integer   1-based position among the proposal's hunks
---@param total integer
---@return Beast.Review.Marks
function M.paint(buf, h, idx, total)
	local tag = idx .. "/" .. total
	local virt = incoming_lines(buf, h, tag)
	local marks = { ids = {} }

	if h.old_count == 0 then
		-- Pure insertion: hang the Incoming lines off a neighbouring line.
		local above = h.row == 0
		marks.after = not above
		marks.anchor = mark(buf, above and 0 or h.row - 1, {
			virt_lines = virt,
			virt_lines_above = above,
		}, marks)
		return marks
	end

	local label = #h.new == 0 and "  ← Current (Claude removes this) " or "  ← Current "
	for i = 0, h.old_count - 1 do
		local opts = { line_hl_group = HL_CURRENT, priority = 200 }
		if i == 0 then
			opts.virt_text = { { label .. tag, HL_LABEL } }
			opts.virt_text_pos = "eol"
			opts.hl_mode = "combine"
		end
		if i == h.old_count - 1 then
			opts.virt_lines = virt
		end
		local id = mark(buf, h.row + i, opts, marks)
		marks.first = marks.first or id
		marks.last = id
	end
	return marks
end

---@param buf integer
---@param id integer
---@return integer? row
local function row_of(buf, id)
	local pos = api.nvim_buf_get_extmark_by_id(buf, NS, id, { details = true })
	if pos[3] and pos[3].invalid then
		return nil
	end
	return pos[1]
end

--- Where the hunk currently sits: the row Current starts at and how many
--- rows it spans. Returns nil when the marks no longer resolve.
---@param buf integer
---@param marks Beast.Review.Marks
---@return integer? row, integer? count
function M.locate(buf, marks)
	if marks.anchor then
		local r = row_of(buf, marks.anchor)
		if not r then
			return nil
		end
		return marks.after and r + 1 or r, 0
	end
	local a, b = row_of(buf, marks.first), row_of(buf, marks.last)
	if not a or not b or b < a then
		return nil
	end
	return a, b - a + 1
end

---@param buf integer
---@param marks Beast.Review.Marks
function M.clear(buf, marks)
	for _, id in ipairs(marks.ids) do
		pcall(api.nvim_buf_del_extmark, buf, NS, id)
	end
end

---@param buf integer
function M.clear_all(buf)
	if api.nvim_buf_is_valid(buf) then
		api.nvim_buf_clear_namespace(buf, NS, 0, -1)
	end
end

return M
