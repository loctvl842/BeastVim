--- Inline terminal image rendering, drawn over a Neovim window via the
--- terminal's native graphics protocol (iTerm2 OSC 1337 or Kitty graphics).
---
--- Neovim renders a grid of text cells and knows nothing about pixels, so we
--- build the protocol escape ourselves and write the raw bytes straight to the
--- controlling terminal via `v:stderr`, bypassing Neovim's renderer. The
--- terminal paints the image; Neovim never knows it's there, so the caller must
--- re-`render` after any repaint of the region (resize, full redraw) and
--- `clear` it before tearing the window down.
---
--- Supported on WezTerm/iTerm2 (OSC 1337) and Kitty/Ghostty (Kitty protocol).
--- Elsewhere `render` returns false so callers can fall back to a text preview.
local dimensions = require("beast.libs.image.dimensions")
local protocol = require("beast.libs.image.protocol")

local M = {}

-- Base64-ing huge files and pushing them to the TTY is slow; skip anything
-- larger than this by default and let the caller fall back to text.
local DEFAULT_MAX_BYTES = 10 * 1024 * 1024
local DEFAULT_CELL_RATIO = 2.0

---@type table<string, true>
local IMAGE_EXT = {
	png = true,
	jpg = true,
	jpeg = true,
	gif = true,
	webp = true,
	bmp = true,
	tiff = true,
	tif = true,
	ico = true,
	avif = true,
}

---@class Beast.Image.Opts
---@field cell_ratio? number cell height/width fallback when the terminal reports no pixel size (default 2.0)
---@field max_bytes? integer skip files larger than this (default 10MiB)

--- Whether `path` has a known image extension.
---@param path string
---@return boolean
function M.is_image(path)
	local ext = path:match("%.([%w]+)$")
	return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

--- Which inline-image protocol the host terminal speaks, or nil for none.
---@return Beast.Image.Protocol|nil
function M.protocol()
	return protocol.detect()
end

--- Whether the host terminal understands an inline-image protocol we support.
---@return boolean
function M.supported()
	return protocol.detect() ~= nil
end

--- Write raw bytes to the controlling terminal, bypassing Neovim's renderer.
---@param data string
local function term_write(data)
	pcall(vim.fn.chansend, vim.v.stderr, data)
end

--- Render `path` as an inline image, fitted and centred inside the content area
--- of `win`, using whichever protocol the terminal supports.
--- Returns false (so the caller can fall back to text) when the terminal is
--- unsupported or the file is missing / empty / too large / wrong format.
---@param win integer
---@param path string
---@param opts? Beast.Image.Opts
---@return boolean ok
function M.render(win, path, opts)
	opts = opts or {}
	local proto = protocol.detect()
	if not proto or not vim.api.nvim_win_is_valid(win) then
		return false
	end

	-- The Kitty direct path only carries PNG; non-PNG would need conversion
	-- (deliberately out of scope to stay dependency-free).
	if proto == "kitty" and not M.is_image(path) then
		return false
	end

	local max_bytes = opts.max_bytes or DEFAULT_MAX_BYTES
	local stat = vim.uv.fs_stat(path)
	if not stat or stat.type ~= "file" or stat.size == 0 or stat.size > max_bytes then
		return false
	end

	local f = io.open(path, "rb")
	if not f then
		return false
	end
	local bytes = f:read("*a")
	f:close()
	if not bytes or #bytes == 0 then
		return false
	end

	-- Kitty's direct transmission expects PNG bytes; bail to text otherwise.
	if proto == "kitty" and not protocol.is_png(bytes) then
		return false
	end

	-- Absolute 1-based terminal cell of the window's first content cell.
	-- screenpos accounts for the window border (and any gutter); a raw
	-- nvim_win_get_position returns the border's outer corner, so drawing there
	-- lands the image on the top/left border.
	local sp = vim.fn.screenpos(win, 1, 1)
	local row, col
	if sp.row and sp.row > 0 then
		row, col = sp.row, sp.col
	else
		-- Fallback (window not currently drawn): grid 0-based -> terminal 1-based.
		local pos = vim.api.nvim_win_get_position(win)
		row, col = pos[1] + 1, pos[2] + 1
	end
	local cols = vim.api.nvim_win_get_width(win)
	local rows = vim.api.nvim_win_get_height(win)

	-- Fit the image inside the cols x rows box preserving aspect ratio, then
	-- centre it. Both protocols take an explicit cell size, so we compute the
	-- contained box ourselves — guaranteeing it never spills past the window
	-- edge, and stays centred regardless of shape.
	local img_w, img_h = dimensions.size(bytes)
	local draw_w, draw_h = cols, rows
	if img_w and img_h and img_w > 0 and img_h > 0 then
		local ratio = dimensions.cell_aspect(opts.cell_ratio or DEFAULT_CELL_RATIO)
		draw_w, draw_h = dimensions.fit_cells(img_w, img_h, cols, rows, ratio)
	end
	local draw_row = row + math.floor((rows - draw_h) / 2)
	local draw_col = col + math.floor((cols - draw_w) / 2)

	local seq = (proto == "kitty") and protocol.kitty_seq(bytes, draw_w, draw_h) or protocol.iterm_seq(bytes, draw_w, draw_h)
	term_write(protocol.at_cursor(draw_row, draw_col, seq))
	return true
end

--- Erase any inline image previously drawn by `render`. Only meaningful for the
--- Kitty protocol, whose placements persist past a buffer/window repaint; the
--- iTerm2 protocol has no handle, so a repaint clears those on its own.
function M.clear()
	if protocol.detect() == "kitty" then
		term_write(protocol.kitty_delete_seq())
	end
end

return M
