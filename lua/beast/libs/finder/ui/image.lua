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

---@alias Beast.Finder.ImageProtocol "iterm"|"kitty"

---@type Beast.Finder.ImageProtocol|false|nil
local protocol_cache

--- Which inline-image protocol the host terminal speaks, or nil for none.
--- - "iterm": iTerm2 OSC 1337 (iTerm2, WezTerm)
--- - "kitty": Kitty graphics protocol (Kitty, Ghostty; also WezTerm, but we
---   prefer OSC 1337 there since it needs no chunking)
--- Conservative: bails under tmux/zellij since passthrough escaping isn't
--- implemented.
---@return Beast.Finder.ImageProtocol|nil
function M.protocol()
	if protocol_cache ~= nil then
		return protocol_cache or nil
	end
	---@type Beast.Finder.ImageProtocol|false
	local result = false
	if not vim.env.TMUX and not vim.env.ZELLIJ then
		local prog = vim.env.TERM_PROGRAM
		local term = vim.env.TERM or ""
		if prog == "WezTerm" or prog == "iTerm.app" or vim.env.WEZTERM_PANE then
			result = "iterm"
		elseif prog == "ghostty" or vim.env.GHOSTTY_RESOURCES_DIR or vim.env.KITTY_WINDOW_ID then
			result = "kitty"
		elseif term:find("kitty") or term:find("ghostty") then
			result = "kitty"
		end
	end
	protocol_cache = result
	return result or nil
end

--- Whether the host terminal understands an inline-image protocol we support.
---@return boolean
function M.supported()
	return M.protocol() ~= nil
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

local ST = ESC .. "\\" -- string terminator (ESC \)
local KITTY_ID = 1 -- fixed image id; only one preview image exists at a time
local KITTY_CHUNK = 4096 -- max base64 bytes per Kitty transmission chunk

--- Wrap a terminal payload so it draws at (row, col) without disturbing the
--- editor cursor: save (ESC 7), move (CUP), draw, restore (ESC 8).
---@param row integer
---@param col integer
---@param payload string
---@return string
local function at_cursor(row, col, payload)
	return ESC .. "7" .. ESC .. "[" .. row .. ";" .. col .. "H" .. payload .. ESC .. "8"
end

--- iTerm2 OSC 1337 escape for an inline image of exact cell size draw_w x draw_h.
---@param bytes string raw image bytes
---@param draw_w integer
---@param draw_h integer
---@return string
local function iterm_seq(bytes, draw_w, draw_h)
	return ESC
		.. "]1337;File=size="
		.. #bytes
		.. ";width="
		.. draw_w
		.. ";height="
		.. draw_h
		.. ";preserveAspectRatio=0;inline=1;doNotMoveCursor=1:"
		.. vim.base64.encode(bytes)
		.. BEL
end

--- Kitty graphics protocol: transmit + display a PNG, scaled to fit draw_w x
--- draw_h cells. The previous placement (same id) is deleted first so resizes
--- and image switches don't leave ghosts. Data is base64'd and chunked at 4096
--- bytes; only the first chunk carries the control keys. q=2 silences the
--- terminal's OK/error replies so they don't leak into the buffer.
---@param bytes string raw PNG bytes
---@param draw_w integer
---@param draw_h integer
---@return string
local function kitty_seq(bytes, draw_w, draw_h)
	local delete = ESC .. "_Ga=d,d=I,i=" .. KITTY_ID .. ",q=2" .. ST
	local b64 = vim.base64.encode(bytes)
	local parts = { delete }
	local pos = 1
	local first = true
	local n = #b64
	while pos <= n do
		local piece = b64:sub(pos, pos + KITTY_CHUNK - 1)
		pos = pos + KITTY_CHUNK
		local more = (pos <= n) and 1 or 0
		local keys
		if first then
			-- a=T transmit+display, f=100 PNG, t=d direct, C=1 keep cursor,
			-- c/r scale-to-fit within draw_w x draw_h cells.
			keys = "a=T,f=100,t=d,q=2,i=" .. KITTY_ID .. ",c=" .. draw_w .. ",r=" .. draw_h .. ",C=1,m=" .. more
			first = false
		else
			keys = "m=" .. more
		end
		parts[#parts + 1] = ESC .. "_G" .. keys .. ";" .. piece .. ST
	end
	return table.concat(parts)
end

--- Render `path` as an inline image, fitted and centred inside the content area
--- of `win`, using whichever protocol the terminal supports.
--- Returns false (so the caller can fall back to text) when the terminal is
--- unsupported or the file is missing / empty / too large / wrong format.
---@param win integer
---@param path string
---@return boolean ok
function M.render(win, path)
	local proto = M.protocol()
	if not proto or config.preview_image == false or not vim.api.nvim_win_is_valid(win) then
		return false
	end

	-- The Kitty direct path only carries PNG; non-PNG would need conversion
	-- (deliberately out of scope to stay dependency-free).
	if proto == "kitty" and not M.is_image(path) then
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

	-- Kitty's direct transmission expects PNG bytes; bail to text otherwise.
	if proto == "kitty" and bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" then
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
	-- centre it. Both protocols here take an explicit cell size, so we compute
	-- the contained box ourselves — guaranteeing it never spills past the
	-- preview border, and stays centred regardless of shape.
	local img_w, img_h = image_size(bytes)
	local draw_w, draw_h = cols, rows
	if img_w and img_h and img_w > 0 and img_h > 0 then
		draw_w, draw_h = fit_cells(img_w, img_h, cols, rows, cell_aspect())
	end
	local draw_row = row + math.floor((rows - draw_h) / 2)
	local draw_col = col + math.floor((cols - draw_w) / 2)

	local seq = (proto == "kitty") and kitty_seq(bytes, draw_w, draw_h) or iterm_seq(bytes, draw_w, draw_h)
	term_write(at_cursor(draw_row, draw_col, seq))
	return true
end

--- Erase any inline image currently drawn (Kitty placements persist until
--- deleted; the iTerm2 protocol has no handle, so a buffer repaint clears it).
function M.clear_kitty()
	if M.protocol() == "kitty" then
		term_write(ESC .. "_Ga=d,d=I,i=" .. KITTY_ID .. ",q=2" .. ST)
	end
end

return M
