local config = require("beast.libs.indent.config")
local guide = require("beast.libs.indent.guide")

local ns = vim.api.nvim_create_namespace("BeastIndent")

local M = {}

---@param buf integer
---@return boolean
local function is_excluded(buf)
	local ft = vim.bo[buf].filetype or ""
	for _, excluded in ipairs(config.exclude_filetypes) do
		-- stylua: ignore
		if ft == excluded then return true end
	end
	return vim.bo[buf].buftype ~= ""
end

---Decoration provider callback — called every redraw cycle.
---@param _ any
---@param win integer
---@param buf integer
---@param top integer 0-indexed
---@param bottom integer 0-indexed
local function on_win(_, win, buf, top, bottom)
	-- stylua: ignore
	if not config.guide.enabled then return end
	-- stylua: ignore
	if is_excluded(buf) then return end

	local sw = vim.bo[buf].shiftwidth
	sw = sw == 0 and vim.bo[buf].tabstop or sw
	-- stylua: ignore
	if sw <= 0 then return end

	local leftcol = vim.api.nvim_buf_call(buf, vim.fn.winsaveview).leftcol --[[@as integer]]

	vim.api.nvim_buf_call(buf, function()
		for line = top + 1, bottom + 1 do
			local indent = guide.get_indent(buf, line, sw)
			if indent > 0 then
				guide.draw(buf, ns, line, indent, sw, leftcol)
			end
		end
	end)
end

---@param opts? Beast.Indent.Config
function M.setup(opts)
	config.setup(opts)
	require("beast.libs.indent.highlights")
	vim.api.nvim_set_decoration_provider(ns, { on_win = on_win })
end

return M
