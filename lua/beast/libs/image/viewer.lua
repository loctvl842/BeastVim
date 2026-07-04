--- Open an image file and view it inline, drawn over the buffer's window via
--- the terminal graphics protocol (see beast.libs.image). Reading an image file
--- is intercepted so its bytes aren't dumped as text; instead the window shows
--- the rendered image, redrawn on layout changes and cleared when hidden.
---
--- Only active on terminals that support an inline-image protocol; elsewhere
--- `setup` is a no-op and Neovim's default (binary) behaviour is left alone.
local debounce = require("beast.util.debounce")
local image = require("beast.libs.image")

local M = {}

local PATTERNS = {
	"*.png",
	"*.jpg",
	"*.jpeg",
	"*.gif",
	"*.webp",
	"*.bmp",
	"*.tiff",
	"*.tif",
	"*.ico",
	"*.avif",
}

---@class Beast.Image.Viewer.Opts
---@field enabled? boolean register the viewer (default true)
---@field cell_ratio? number passed through to image.render
---@field max_bytes? integer passed through to image.render

---@type Beast.Image.Viewer.Opts
local opts = { enabled = true }

---@type Beast.Util.Debouncer?
local resize_debounced

--- The window currently displaying the image, if any. Single-image model: one
--- placement at a time (matches the finder preview). Tracked so we only clear
--- when the actual image window is left/closed, not on unrelated window events.
---@type integer?
local image_win

--- True for a buffer we've taken over as an image viewer.
---@param buf integer
---@return boolean
local function is_viewer_buf(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].beast_image_viewer == true
end

--- Erase the on-screen image, if one is drawn. The lib removes the image
--- itself: Kitty deletes by id; iTerm2 overwrites the image's cell rectangle
--- with the editor's Normal background, so the cleared region blends into the
--- buffer that replaces it (no mismatched grey block) without needing a forced
--- full redraw.
local function clear_image()
	if not image_win then
		return
	end
	image_win = nil
	image.clear()
end

--- Turn the just-opened image file buffer into a blank host for the rendered
--- image. `nofile` protects the real file from an accidental `:w` blanking it,
--- and (being in the statuscolumn's bt_ignore, plus the explicit flag) removes
--- the gutter so the image isn't pushed off the statuscolumn. These are all
--- buffer-local, so nothing leaks to the next buffer shown in the window.
---@param buf integer
local function setup_buf(buf)
	vim.b[buf].beast_image_viewer = true
	vim.b[buf].beast_statuscolumn_disabled = true
	vim.bo[buf].buftype = "nowrite"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, {})
	vim.bo[buf].modifiable = false
	vim.bo[buf].modified = false
end

--- Draw the image for a window currently showing a viewer buffer.
---@param win integer
local function render_win(win)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if not is_viewer_buf(buf) then
		return
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return
	end
	-- Flush Neovim's repaint of the (blank) window, then draw on top.
	vim.cmd("redraw")
	if image.render(win, name, { cell_ratio = opts.cell_ratio, max_bytes = opts.max_bytes }) then
		image_win = win
	else
		-- Unsupported / unreadable: show a small text placeholder instead.
		image_win = nil
		vim.bo[buf].modifiable = true
		pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, { "", "  (cannot preview image: " .. name .. ")" })
		vim.bo[buf].modifiable = false
	end
end

--- Register the autocmds that drive the viewer. Idempotent.
---@param user_opts? Beast.Image.Viewer.Opts
function M.setup(user_opts)
	opts = vim.tbl_extend("force", opts, user_opts or {})
	if opts.enabled == false or not image.supported() then
		return
	end

	resize_debounced = debounce(60, function()
		if image_win and vim.api.nvim_win_is_valid(image_win) then
			render_win(image_win)
		end
	end)

	local augroup = vim.api.nvim_create_augroup("beast.image.viewer", { clear = true })

	-- Intercept reading an image file: don't dump its bytes as text.
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = augroup,
		pattern = PATTERNS,
		callback = function(ev)
			setup_buf(ev.buf)
		end,
	})

	-- Draw when an image buffer is shown in / focused on a window.
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = augroup,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if is_viewer_buf(vim.api.nvim_win_get_buf(win)) then
				vim.schedule(function()
					render_win(win)
				end)
			end
		end,
	})

	-- Re-draw on layout changes (debounced — resize fires a burst of events).
	vim.api.nvim_create_autocmd({ "WinScrolled", "VimResized", "WinResized" }, {
		group = augroup,
		callback = function()
			if resize_debounced then
				resize_debounced()
			end
		end,
	})

	-- Clear the image when its buffer is replaced in the window (buffer switch).
	-- BufWinLeave fires before the new buffer is shown; clear_image schedules the
	-- forced redraw so it runs after the switch completes.
	vim.api.nvim_create_autocmd("BufWinLeave", {
		group = augroup,
		callback = function(ev)
			if image_win and is_viewer_buf(ev.buf) then
				clear_image()
			end
		end,
	})

	-- WinClosed: either the image's own window closed (clear), or some overlay
	-- (e.g. a key-hint float) that was drawn over the image closed — in which
	-- case the cells it covered were overwritten and Neovim won't repaint the
	-- image there, so re-render to repair the damage.
	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		callback = function(ev)
			local closed = tonumber(ev.match)
			if not image_win then
				return
			end
			if closed == image_win then
				clear_image()
			elseif vim.api.nvim_win_is_valid(image_win) and resize_debounced then
				resize_debounced()
			end
		end,
	})
end

return M
