local config = require("beast.libs.indent.config")
local guide = require("beast.libs.indent.guide")
local scope = require("beast.libs.indent.scope")

local ns = vim.api.nvim_create_namespace("BeastIndent")
local augroup = nil

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
	if is_excluded(buf) then return end

	local sw = vim.bo[buf].shiftwidth
	sw = sw == 0 and vim.bo[buf].tabstop or sw
	-- stylua: ignore
	if sw <= 0 then return end

	local leftcol = vim.api.nvim_buf_call(buf, vim.fn.winsaveview).leftcol --[[@as integer]]

	vim.api.nvim_buf_call(buf, function()
		if config.guide.enabled then
			for line = top + 1, bottom + 1 do
				local indent = guide.get_indent(buf, line, sw)
				if indent > 0 then
					guide.draw(buf, ns, line, indent, sw, leftcol)
				end
			end
		end

		scope.draw(buf, ns, win, top + 1, bottom + 1, leftcol, sw)
	end)
end

local function ensure_autocmds()
	-- stylua: ignore
	if augroup then return end
	augroup = vim.api.nvim_create_augroup("BeastIndent", { clear = true })

	local function on_move()
		scope.update(is_excluded)
	end

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, { group = augroup, callback = on_move })

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = scope.cleanup_win,
	})
end

---@param opts? Beast.Indent.Config
function M.setup(opts)
	config.setup(opts)
	require("beast").apply_highlights("beast.libs.indent.highlights")
	vim.api.nvim_set_decoration_provider(ns, { on_win = on_win })
	ensure_autocmds()
	vim.schedule(function()
		scope.update(is_excluded)
	end)
end

return M
