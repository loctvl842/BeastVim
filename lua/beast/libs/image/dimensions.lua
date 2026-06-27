--- Image sizing math for terminal rendering: parse native pixel dimensions
--- from a file's header bytes (no decode, no dependency) and translate a target
--- cell box into a contained, aspect-preserving cell size.
local M = {}

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
function M.size(d)
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

-- Cell pixel geometry — needed to translate "fit within N rows x M cols" into a
-- pixel aspect. Best-effort TIOCGWINSZ via FFI; callers supply a fallback ratio
-- for terminals that don't report pixel size.
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

--- Cell height-to-width ratio (e.g. ~2.0), queried live so font zoom is picked
--- up. Falls back to `fallback` when the terminal reports no pixel size.
---@param fallback number cell height/width to use when unavailable
---@return number
function M.cell_aspect(fallback)
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
	return (type(fallback) == "number" and fallback > 0) and fallback or 2.0
end

--- Largest cell box (<= cols x rows) that preserves the image's pixel aspect.
---@param img_w integer
---@param img_h integer
---@param cols integer
---@param rows integer
---@param ratio number cell height/width
---@return integer fc_w, integer fc_h
function M.fit_cells(img_w, img_h, cols, rows, ratio)
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

return M
