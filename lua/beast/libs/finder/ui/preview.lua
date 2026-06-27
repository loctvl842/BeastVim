local View = require("beast.libs.view")
local config = require("beast.libs.finder.config")
local image = require("beast.libs.image")

---@class Beast.Finder.PreviewView : Beast.View.Instance
---@field ns integer
---@field visible boolean
---@field loaded_file? string  absolute path of the file currently shown in the buffer
---@field loaded_line_count integer  line count of the loaded file (for cursor clamping)
---@field loaded_image? string  absolute path of the image currently drawn over the window
---@overload fun(buf?: integer, win?: integer, ns: integer): Beast.Finder.PreviewView
local PreviewView = View:extend(
	---@param obj Beast.Finder.PreviewView
	function(obj, ns)
		obj.ns = ns
		obj.visible = true
		obj.loaded_file = nil
		obj.loaded_line_count = 0
		obj.loaded_image = nil
	end
)

---@class Beast.Finder.UI.Preview
local M = {}

local MAX_PREVIEW_LINES = 500

--- Move the cursor to (line, col) in the preview window, centring vertically
--- (`zz`) and horizontally (leftcol pan) so long lines remain visible. Vertical
--- centring also ensures the smooth-scroll lib sees a topline change to animate
--- when cycling between hits inside the same viewport.
---@param view Beast.Finder.PreviewView
---@param line integer 1-based row
---@param col integer 0-based byte column
local function set_cursor_centered(view, line, col)
	pcall(vim.api.nvim_win_set_cursor, view.win, { line, col })
	pcall(vim.api.nvim_win_call, view.win, function()
		vim.cmd("normal! zz")
		local win_w = vim.api.nvim_win_get_width(view.win)
		-- Subtract a rough text-area offset for the 'number' column.
		local text_w = math.max(1, win_w - 6)
		local leftcol = math.max(0, col - math.floor(text_w / 2))
		vim.fn.winrestview({ leftcol = leftcol })
	end)
end

---@param view Beast.Finder.PreviewView
---@param file string  absolute path of the image to draw
function M.draw_image(view, file)
	-- Blank the buffer + hide the number column so Neovim paints an empty region
	-- (no text, no line numbers) underneath the image.
	View.win.wo(view.win, "number", false)
	vim.bo[view.buf].modifiable = true
	pcall(vim.api.nvim_buf_set_lines, view.buf, 0, -1, false, {})
	vim.bo[view.buf].modifiable = false
	vim.bo[view.buf].filetype = ""

	pcall(vim.api.nvim_win_set_config, view.win, {
		title = " " .. vim.fn.fnamemodify(file, ":t") .. " ",
		title_pos = "center",
	})

	view.loaded_file = nil
	view.loaded_line_count = 0
	view.loaded_image = file

	-- Flush Neovim's blank repaint of the region, then draw the image on top.
	vim.cmd("redraw")
	if not image.render(view.win, file, { cell_ratio = config.preview_image_cell_ratio }) then
		-- Terminal refused or file unreadable — fall back to a placeholder.
		view.loaded_image = nil
		View.win.wo(view.win, "number", true)
		vim.bo[view.buf].modifiable = true
		vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { "(cannot preview image)" })
		vim.bo[view.buf].modifiable = false
	end
end

--- Re-draw the current image after the window has moved/resized or the screen
--- was fully repainted (e.g. on VimResized). Deferred so it runs after Neovim's
--- own redraw, which would otherwise erase the freshly drawn image.
---@param view Beast.Finder.PreviewView
function M.refresh(view)
	-- stylua: ignore
	if not view:is_valid() or not view.loaded_image then return end
	local file = view.loaded_image
	vim.schedule(function()
		-- stylua: ignore
		if not view:is_valid() or view.loaded_image ~= file then return end
		vim.cmd("redraw")
		image.render(view.win, file, { cell_ratio = config.preview_image_cell_ratio })
	end)
end

---@param win_row integer
---@param win_col integer
---@param win_w integer
---@param win_h integer
---@return Beast.Finder.PreviewView
function M.create(win_row, win_col, win_w, win_h)
	local buf = View.buf.new("beast-finder-preview")
	local ns = vim.api.nvim_create_namespace("beast-finder-preview")

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = win_w,
		height = win_h,
		row = win_row,
		col = win_col,
		style = "minimal",
		border = { "┬", "─", "╮", "│", "╯", "─", "┴", "│" },
		zindex = 102,
	})

	View.win.wo(win, "winhl", "Normal:BeastFinderNormal,FloatBorder:BeastFinderBorder,FloatTitle:BeastFinderPreviewTitle")
	View.win.wo(win, "wrap", false)
	View.win.wo(win, "number", true)
	View.win.wo(win, "relativenumber", false)

	return PreviewView(buf, win, ns)
end

---@param view Beast.Finder.PreviewView
---@param item Beast.Finder.Item
function M.show(view, item)
	-- stylua: ignore
	if not view:is_valid() or not view.visible then return end

	-- Image path: draw the file as an inline image over the window via the
	-- terminal's graphics protocol instead of dumping its bytes into the buffer.
	if item.file and image.is_image(item.file) and config.preview_image ~= false and image.supported() then
		-- Same image already drawn — leave it in place (cursor moves over
		-- identical selections must not re-push the payload).
		if view.loaded_image == item.file then
			return
		end
		M.draw_image(view, item.file)
		return
	end

	-- Replacing a previously drawn image with text/other: drop the marker,
	-- restore the number column, and erase any persistent (Kitty) placement.
	-- The buffer repaint below clears iTerm2-protocol images on its own.
	if view.loaded_image then
		view.loaded_image = nil
		image.clear()
		View.win.wo(view.win, "number", true)
	end

	-- Fast path: same file as currently loaded — just move the cursor.
	if item.file and view.loaded_file == item.file then
		if item.pos then
			local line = math.max(1, math.min(item.pos[1], math.max(1, view.loaded_line_count)))
			set_cursor_centered(view, line, item.pos[2] or 0)
		else
			pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
		end
		return
	end

	local lines = {}
	local ft = ""
	local title = ""
	if item.file then
		local ok, result = pcall(vim.fn.readfile, item.file, "", MAX_PREVIEW_LINES)
		if ok then
			for i, line in ipairs(result) do
				result[i] = line:gsub("[\r%z]", "")
			end
			lines = result
		else
			lines = { "(cannot read file)" }
		end
		ft = vim.filetype.match({ filename = item.file }) or ""
		title = vim.fn.fnamemodify(item.file, ":t")
	end

	-- Update window title with current file name
	if title ~= "" then
		pcall(vim.api.nvim_win_set_config, view.win, {
			title = " " .. title .. " ",
			title_pos = "center",
		})
	end
	vim.bo[view.buf].modifiable = true
	local ok_set = pcall(vim.api.nvim_buf_set_lines, view.buf, 0, -1, false, lines)
	if not ok_set then
		-- Binary file — lines contain embedded newlines
		vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { "(binary file)" })
		vim.bo[view.buf].modifiable = false
		view.loaded_file = nil
		view.loaded_line_count = 1
		return
	end
	vim.bo[view.buf].modifiable = false
	vim.bo[view.buf].filetype = ft
	view.loaded_file = item.file
	view.loaded_line_count = #lines

	-- Jump to the item's line if provided
	if item.pos and view:is_valid() then
		local line = math.max(1, math.min(item.pos[1], math.max(1, #lines)))
		set_cursor_centered(view, line, item.pos[2] or 0)
	else
		pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
	end
end

---@param view Beast.Finder.PreviewView
function M.clear(view)
	-- stylua: ignore
	if not view:is_valid() then return end
	if view.loaded_image then
		view.loaded_image = nil
		image.clear()
		View.win.wo(view.win, "number", true)
	end
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, {})
	vim.bo[view.buf].modifiable = false
	pcall(vim.api.nvim_win_set_config, view.win, { title = "", title_pos = "center" })
	view.loaded_file = nil
	view.loaded_line_count = 0
end

return M
