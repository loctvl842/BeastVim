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

--- The last image we drew, so it can be erased exactly. The iTerm2 protocol has
--- no image handle, so the only way to remove an image is to overwrite the cell
--- rectangle it occupies — both when clearing and before drawing a replacement
--- (e.g. on resize), otherwise the old placement leaks behind the new one. The
--- owning window is kept so the erase can be clipped to that window's current
--- bounds and never touch a neighbour (e.g. an explorer opened beside it).
---@type { win: integer, row: integer, col: integer, w: integer, h: integer }?
local last_placement

--- The editor's Normal background as 0xRRGGBB, or nil if unset/transparent.
---@return integer?
local function normal_bg()
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal" })
	if ok and hl and type(hl.bg) == "number" then
		return hl.bg
	end
	return nil
end

--- A window's current screen rectangle (1-based row/col, cell width/height), or
--- nil if the window is gone.
---@param win integer
---@return integer? row, integer? col, integer? w, integer? h
local function win_region(win)
	if not vim.api.nvim_win_is_valid(win) then
		return nil
	end
	local sp = vim.fn.screenpos(win, 1, 1)
	local row, col
	if sp.row and sp.row > 0 then
		row, col = sp.row, sp.col
	else
		local pos = vim.api.nvim_win_get_position(win)
		row, col = pos[1] + 1, pos[2] + 1
	end
	return row, col, vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
end

--- Erase the previously drawn iTerm2 image by overwriting its cells with the
--- editor's Normal background (Kitty images are deleted by id instead, so this
--- is iterm-only). The erase is clipped to the owning window's current bounds so
--- a stale full-width placement can't blank a neighbouring window after the
--- layout changed. Clears `last_placement`.
---@param proto Beast.Image.Protocol|nil
local function erase_last(proto)
	local p = last_placement
	last_placement = nil
	if proto ~= "iterm" or not p then
		return
	end
	-- Clip the placement to the window's current region; cells outside it now
	-- belong to another window (already repainted by Neovim) and must not be
	-- touched.
	local wr, wc, ww, wh = win_region(p.win)
	local top, left, right, bottom = p.row, p.col, p.col + p.w, p.row + p.h
	if wr then
		top = math.max(top, wr)
		left = math.max(left, wc)
		right = math.min(right, wc + ww)
		bottom = math.min(bottom, wr + wh)
	end
	if right > left and bottom > top then
		term_write(protocol.erase_rect_seq(top, left, right - left, bottom - top, normal_bg()))
	end
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
	-- Resolve the window's text area in absolute screen cells. screenpos points
	-- at the first *text* cell — i.e. past the sign/number/status columns — so
	-- the image starts after the gutter. The window width, however, includes
	-- that gutter; using it directly would size the image too wide and overflow
	-- past the right edge into a neighbouring window. Subtract the gutter so the
	-- image is bounded by the text area.
	local wpos = vim.api.nvim_win_get_position(win)
	local sp = vim.fn.screenpos(win, 1, 1)
	local row, col, gutter
	if sp.row and sp.row > 0 then
		row, col = sp.row, sp.col
		gutter = col - (wpos[2] + 1) -- columns consumed by the gutter
	else
		-- Fallback (window not currently drawn): grid 0-based -> terminal 1-based.
		row, col, gutter = wpos[1] + 1, wpos[2] + 1, 0
	end
	local cols = math.max(1, vim.api.nvim_win_get_width(win) - gutter)
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

	-- Erase any previous iTerm2 placement before drawing the replacement, or it
	-- leaks behind the new image (e.g. when re-rendering at a new position after
	-- a window resize). Kitty's transmit deletes the prior placement by id, so
	-- this is a no-op there.
	erase_last(proto)

	local seq = (proto == "kitty") and protocol.kitty_seq(bytes, draw_w, draw_h) or protocol.iterm_seq(bytes, draw_w, draw_h)
	term_write(protocol.at_cursor(draw_row, draw_col, seq))
	last_placement = { win = win, row = draw_row, col = draw_col, w = draw_w, h = draw_h }
	return true
end

--- Erase the inline image previously drawn by `render`. Kitty placements are
--- deleted by id; iTerm2 images (which have no handle and sit in terminal cells
--- that Neovim's grid diff won't repaint over) are removed by overwriting the
--- exact rectangle they occupy with the editor's Normal background, so the
--- cleared region blends in instead of leaving a mismatched (grey) block.
function M.clear()
	local proto = protocol.detect()
	if proto == "kitty" then
		term_write(protocol.kitty_delete_seq())
		last_placement = nil
	else
		erase_last(proto)
	end
end

return M
