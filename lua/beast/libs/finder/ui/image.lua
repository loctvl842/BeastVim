--- Inline-image rendering for the finder preview using the iTerm2 image
--- protocol (OSC 1337) — the same escape `wezterm imgcat` emits, but generated
--- in-process so it can be positioned over a floating preview window.
---
--- `wezterm imgcat` itself can't be shelled out from Neovim: it probes the
--- terminal and requires its stdout to be a real TTY, so from a job pipe it
--- aborts with "Device not configured" and emits nothing. We therefore build
--- the OSC payload ourselves (readfile → base64 → wrap) and write the raw bytes
--- straight to the controlling terminal via `v:stderr`, bypassing Neovim's cell
--- grid. The terminal paints the image; Neovim never knows it's there, so the
--- caller is responsible for re-rendering after any repaint of the region.
local config = require("beast.libs.finder.config")

local M = {}

local ESC = "\27"
local BEL = "\7"

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

-- Base64-ing huge files and pushing them to the TTY is slow; skip anything
-- larger than this and let the caller fall back to a text placeholder.
local MAX_BYTES = 10 * 1024 * 1024

-- ---------------------------------------------------------------------------
-- Image dimensions (native pixel size) — parsed from header bytes so we can
-- fit the image to the preview while preserving aspect ratio. No dependency,
-- no decode: just read the width/height fields of the common formats.
-- ---------------------------------------------------------------------------

---@param d string raw bytes
---@param p integer 1-based offset
---@param n integer number of bytes
---@return integer
local function be(d, p, n)
	local v = 0
	for i = 0, n - 1 do
		v = v * 256 + d:byte(p + i)
	end
	return v
end

---@param d string raw bytes
---@param p integer 1-based offset
---@param n integer number of bytes
---@return integer
local function le(d, p, n)
	local v = 0
	for i = n - 1, 0, -1 do
		v = v * 256 + d:byte(p + i)
	end
	return v
end

--- Native pixel dimensions of a PNG/JPEG/GIF/BMP/WebP image, or nil if unknown.
---@param d string raw file bytes
---@return integer? width, integer? height
local function image_size(d)
	local n = #d
	-- PNG: 8-byte signature, then IHDR (width/height big-endian at 17/21).
	if n >= 24 and d:sub(1, 8) == "\137PNG\r\n\26\n" then
		return be(d, 17, 4), be(d, 21, 4)
	end
	-- GIF: "GIF87a"/"GIF89a", logical screen width/height little-endian at 7/9.
	if n >= 10 and (d:sub(1, 6) == "GIF87a" or d:sub(1, 6) == "GIF89a") then
		return le(d, 7, 2), le(d, 9, 2)
	end
	-- BMP: "BM", width/height little-endian at 19/23 (height may be negative).
	if n >= 26 and d:sub(1, 2) == "BM" then
		local w, h = le(d, 19, 4), le(d, 23, 4)
		if h >= 0x80000000 then
			h = 0x100000000 - h
		end
		return w, h
	end
	-- JPEG: scan segments for a Start-Of-Frame marker (height/width big-endian).
	if n >= 4 and d:byte(1) == 0xFF and d:byte(2) == 0xD8 then
		local i = 3
		while i + 8 <= n do
			if d:byte(i) ~= 0xFF then
				return nil
			end
			local marker = d:byte(i + 1)
			if marker >= 0xC0 and marker <= 0xCF and marker ~= 0xC4 and marker ~= 0xC8 and marker ~= 0xCC then
				return be(d, i + 7, 2), be(d, i + 5, 2)
			end
			i = i + 2 + be(d, i + 2, 2)
		end
		return nil
	end
	-- WebP: "RIFF"...."WEBP" + a VP8/VP8L/VP8X chunk.
	if n >= 30 and d:sub(1, 4) == "RIFF" and d:sub(9, 12) == "WEBP" then
		local fourcc = d:sub(13, 16)
		if fourcc == "VP8 " then
			return le(d, 27, 2) % 0x4000, le(d, 29, 2) % 0x4000
		elseif fourcc == "VP8X" then
			return le(d, 25, 3) + 1, le(d, 28, 3) + 1
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Cell pixel geometry — needed to translate "fit within N rows x M cols" into
-- a pixel aspect. Best-effort TIOCGWINSZ via FFI; falls back to a configurable
-- ratio when the terminal doesn't report pixel size.
-- ---------------------------------------------------------------------------

local ffi_ok, ffi = pcall(require, "ffi")
if ffi_ok then
	pcall(
		ffi.cdef,
		[[
		struct beast_winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
		int ioctl(int, unsigned long, ...);
	]]
	)
end
local TIOCGWINSZ = (jit and (jit.os == "OSX" or jit.os == "BSD")) and 0x40087468 or 0x5413

--- Cell height-to-width ratio (e.g. ~2.0). Queried live so font zoom is picked
--- up; falls back to config.preview_image_cell_ratio (default 2.0).
---@return number
local function cell_aspect()
	if ffi_ok then
		local ok, ratio = pcall(function()
			local ws = ffi.new("struct beast_winsize[1]")
			if ffi.C.ioctl(1, TIOCGWINSZ, ws) ~= 0 then
				return nil
			end
			-- guard: many terminals report 0 pixel size
			if ws[0].ws_xpixel == 0 or ws[0].ws_ypixel == 0 or ws[0].ws_col == 0 or ws[0].ws_row == 0 then
				return nil
			end
			local cw = ws[0].ws_xpixel / ws[0].ws_col
			local ch = ws[0].ws_ypixel / ws[0].ws_row
			return ch / cw
		end)
		if ok and ratio then
			return ratio
		end
	end
	local r = config.preview_image_cell_ratio
	return (type(r) == "number" and r > 0) and r or 2.0
end

--- Largest cell box (<= cols x rows) that preserves the image's pixel aspect.
---@param img_w integer
---@param img_h integer
---@param cols integer
---@param rows integer
---@param ratio number cell height/width
---@return integer fc_w, integer fc_h
local function fit_cells(img_w, img_h, cols, rows, ratio)
	-- Preserve aspect in cells: fc_w/fc_h = (img_w/img_h) * (cell_h/cell_w).
	local k = (img_w / img_h) * ratio
	local fc_w = cols
	local fc_h = math.floor(fc_w / k + 0.5)
	if fc_h > rows then
		fc_h = rows
		fc_w = math.floor(fc_h * k + 0.5)
	end
	fc_w = math.max(1, math.min(cols, fc_w))
	fc_h = math.max(1, math.min(rows, fc_h))
	return fc_w, fc_h
end

---@type boolean?
local supported_cache

--- Whether the host terminal understands the iTerm2 inline-image protocol.
--- Conservative: WezTerm and iTerm2 only. tmux/zellij passthrough escaping is
--- not implemented, so bail when multiplexed.
---@return boolean
function M.supported()
	if supported_cache ~= nil then
		return supported_cache
	end
	local ok = false
	if not vim.env.TMUX and not vim.env.ZELLIJ then
		local prog = vim.env.TERM_PROGRAM
		if prog == "WezTerm" or prog == "iTerm.app" or vim.env.WEZTERM_PANE then
			ok = true
		end
	end
	supported_cache = ok
	return ok
end

--- Image preview is on (config not disabled) and the terminal can render it.
---@return boolean
function M.enabled()
	return config.preview_image ~= false and M.supported()
end

---@param path string
---@return boolean
function M.is_image(path)
	local ext = path:match("%.([%w]+)$")
	return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

--- Write raw bytes to the controlling terminal, bypassing Neovim's renderer.
---@param data string
local function term_write(data)
	pcall(vim.fn.chansend, vim.v.stderr, data)
end

--- Render `path` as an inline image filling the content area of `win`.
--- Returns false (so the caller can fall back to text) when the terminal is
--- unsupported or the file is missing / empty / too large to push.
---@param win integer
---@param path string
---@return boolean ok
function M.render(win, path)
	if not M.enabled() or not vim.api.nvim_win_is_valid(win) then
		return false
	end

	local stat = vim.uv.fs_stat(path)
	if not stat or stat.type ~= "file" or stat.size == 0 or stat.size > MAX_BYTES then
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
	-- centre it. WezTerm's own "preserveAspectRatio" only constrains width and
	-- lets height overflow, so we compute the contained cell size ourselves and
	-- pass it exactly (preserveAspectRatio=0) — guaranteeing it never spills
	-- past the preview border.
	local img_w, img_h = image_size(bytes)
	local draw_w, draw_h = cols, rows
	if img_w and img_h and img_w > 0 and img_h > 0 then
		draw_w, draw_h = fit_cells(img_w, img_h, cols, rows, cell_aspect())
	end
	local draw_row = row + math.floor((rows - draw_h) / 2)
	local draw_col = col + math.floor((cols - draw_w) / 2)

	-- width/height in cells; doNotMoveCursor keeps the terminal cursor put.
	local osc = ESC
		.. "]1337;File=size="
		.. #bytes
		.. ";width="
		.. draw_w
		.. ";height="
		.. draw_h
		.. ";preserveAspectRatio=0;inline=1;doNotMoveCursor=1:"
		.. vim.base64.encode(bytes)
		.. BEL

	-- Save cursor, jump to the (centred) draw position, draw, restore cursor.
	local move = ESC .. "[" .. draw_row .. ";" .. draw_col .. "H"
	term_write(ESC .. "7" .. move .. osc .. ESC .. "8")
	return true
end

return M
