--- Terminal graphics protocols: detect which inline-image protocol the host
--- terminal speaks, and encode raw image bytes into the matching escape
--- sequence. Pure string/byte work — no Neovim window APIs here.
local M = {}

local ESC = "\27"
local BEL = "\7"
local ST = ESC .. "\\" -- string terminator (ESC \)

local KITTY_ID = 1 -- fixed image id; only one preview image exists at a time
local KITTY_CHUNK = 4096 -- max base64 bytes per Kitty transmission chunk

---@alias Beast.Image.Protocol "iterm"|"kitty"

---@type Beast.Image.Protocol|false|nil
local protocol_cache

--- Which inline-image protocol the host terminal speaks, or nil for none.
--- - "iterm": iTerm2 OSC 1337 (iTerm2, WezTerm)
--- - "kitty": Kitty graphics protocol (Kitty, Ghostty)
--- Conservative: bails under tmux/zellij since passthrough escaping isn't
--- implemented. Cached with a `false` sentinel so a negative result (terminal
--- not supported) is remembered rather than re-probed on every call.
---@return Beast.Image.Protocol|nil
function M.detect()
	if protocol_cache ~= nil then
		return protocol_cache or nil
	end
	---@type Beast.Image.Protocol|false
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

--- Wrap a terminal payload so it draws at (row, col) without disturbing the
--- editor cursor: save (ESC 7), move (CUP), draw, restore (ESC 8).
---@param row integer 1-based screen row
---@param col integer 1-based screen column
---@param payload string
---@return string
function M.at_cursor(row, col, payload)
	return ESC .. "7" .. ESC .. "[" .. row .. ";" .. col .. "H" .. payload .. ESC .. "8"
end

--- iTerm2 OSC 1337 escape for an inline image of exact cell size draw_w x draw_h.
--- preserveAspectRatio=0 makes the terminal honour the given cell box exactly.
---@param bytes string raw image bytes
---@param draw_w integer
---@param draw_h integer
---@return string
function M.iterm_seq(bytes, draw_w, draw_h)
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
function M.kitty_seq(bytes, draw_w, draw_h)
	local b64 = vim.base64.encode(bytes)
	local parts = { M.kitty_delete_seq() }
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

--- Escape that deletes our placement (and its data) by image id. No-op meaning
--- for the iTerm2 protocol, which has no handle — a buffer repaint clears those.
---@return string
function M.kitty_delete_seq()
	return ESC .. "_Ga=d,d=I,i=" .. KITTY_ID .. ",q=2" .. ST
end

--- Erase a cell rectangle (the iTerm2 protocol stores images inside the cells
--- under the cursor and has no delete command; Neovim's grid diff won't re-emit
--- cells it believes are already blank, so the image lingers after a buffer
--- switch). We overwrite the exact rectangle with ECH (CSI n X), which the
--- terminal turns into blank cells, dropping the image attribute.
---
--- `bg` (0xRRGGBB) sets the background the erased cells take. Pass the editor's
--- Normal background so the cleared region matches the surrounding buffer;
--- without it the cells take the terminal's current pen colour and show up as a
--- mismatched (often grey) rectangle. Wrapped in save-cursor / reset-SGR /
--- restore-cursor so the editor's cursor and pen are left untouched.
---@param row integer 1-based top screen row
---@param col integer 1-based left screen column
---@param w integer width in cells
---@param h integer height in cells
---@param bg? integer background colour as 0xRRGGBB
---@return string
function M.erase_rect_seq(row, col, w, h, bg)
	local parts = { ESC .. "7" } -- save cursor
	if bg then
		local r = math.floor(bg / 65536) % 256
		local g = math.floor(bg / 256) % 256
		local b = bg % 256
		parts[#parts + 1] = ESC .. "[48;2;" .. r .. ";" .. g .. ";" .. b .. "m"
	end
	for r = row, row + h - 1 do
		parts[#parts + 1] = ESC .. "[" .. r .. ";" .. col .. "H" -- move to row start
		parts[#parts + 1] = ESC .. "[" .. w .. "X" -- ECH: erase w cells in place
	end
	parts[#parts + 1] = ESC .. "[m" .. ESC .. "8" -- reset SGR, restore cursor
	return table.concat(parts)
end

--- Whether `bytes` begins with the PNG signature (Kitty direct transmission
--- only carries PNG).
---@param bytes string
---@return boolean
function M.is_png(bytes)
	return bytes:sub(1, 8) == "\137PNG\r\n\26\n"
end

return M
