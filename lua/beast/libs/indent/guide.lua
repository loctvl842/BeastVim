local config = require("beast.libs.indent.config")

local Guide = {}

---Compute indent for a line, handling blank lines by using neighbours.
---@param buf integer
---@param line integer 1-based line number
---@param shiftwidth integer
---@return integer indent column count (0-based)
function Guide.get_indent(buf, line, shiftwidth)
	local line_count = vim.api.nvim_buf_line_count(buf)
	-- stylua: ignore
	if line < 1 or line > line_count then return 0 end

	local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
	if text and text:find("%S") then
		return vim.fn.indent(line)
	end

	-- Blank line: use min of prev/next non-blank indent (+ shiftwidth if they differ)
	local prev = vim.fn.prevnonblank(line)
	local next_line = vim.fn.nextnonblank(line)
	local prev_indent = prev > 0 and vim.fn.indent(prev) or 0
	local next_indent = (next_line > 0 and next_line <= line_count) and vim.fn.indent(next_line) or 0
	local indent = math.min(prev_indent, next_indent)
	if prev_indent ~= next_indent and indent > 0 then
		indent = indent + shiftwidth
	end
	return indent
end

---Draw ephemeral indent guide extmarks for a single line.
---@param buf integer
---@param ns integer namespace
---@param line integer 1-based line number
---@param indent integer indent column count
---@param shiftwidth integer
---@param leftcol integer horizontal scroll offset
function Guide.draw(buf, ns, line, indent, shiftwidth, leftcol)
	local symbol = config.guide.symbol
	local priority = config.guide.priority
	local virt_text = { { symbol, "BeastIndentGuide" } }

	for col = 0, indent - 1, shiftwidth do
		local win_col = col - leftcol
		-- stylua: ignore
		if win_col < 0 then goto continue end

		vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
			virt_text = virt_text,
			virt_text_pos = "overlay",
			virt_text_win_col = win_col,
			hl_mode = "combine",
			priority = priority,
			ephemeral = true,
		})

		::continue::
	end
end

return Guide
