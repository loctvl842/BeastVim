-- WebSocket framing (RFC 6455 section 5). Clients must mask; servers must not.

local bit = require("bit")

local M = {}

M.OP = { CONT = 0, TEXT = 1, BINARY = 2, CLOSE = 8, PING = 9, PONG = 10 }

M.CLOSE = { NORMAL = 1000, PROTOCOL = 1002, UNSUPPORTED = 1003, TOO_BIG = 1009 }

local UNMASK_CHUNK = 4096 -- stays well below LuaJIT's unpack argument limit

---@param s string
---@param mask integer[]  four mask bytes
---@return string
local function unmask(s, mask)
	local out, n = {}, #s
	for i = 1, n, UNMASK_CHUNK do
		local bytes = { s:byte(i, math.min(i + UNMASK_CHUNK - 1, n)) }
		for j = 1, #bytes do
			bytes[j] = bit.bxor(bytes[j], mask[(i + j - 2) % 4 + 1])
		end
		out[#out + 1] = string.char(unpack(bytes))
	end
	return table.concat(out)
end

---@class Beast.Review.Frame
---@field fin boolean
---@field opcode integer
---@field payload string

--- Decode one client frame from the front of `buf`.
---@param buf string
---@param max_payload integer
---@return Beast.Review.Frame? frame   nil when more bytes are needed or on error
---@return integer|string consumed     bytes used; on error, the close code to answer with
function M.decode(buf, max_payload)
	if #buf < 2 then
		return nil, 0
	end
	local b1, b2 = buf:byte(1, 2)
	local fin, rsv, opcode = b1 >= 128, bit.band(bit.rshift(b1, 4), 7), bit.band(b1, 15)
	local masked, len = b2 >= 128, bit.band(b2, 127)

	if rsv ~= 0 or not masked then
		return nil, M.CLOSE.PROTOCOL
	end
	local is_control = opcode >= 8
	if is_control and (not fin or len > 125) then
		return nil, M.CLOSE.PROTOCOL
	end

	local pos = 3
	if len == 126 then
		if #buf < 4 then
			return nil, 0
		end
		local hi, lo = buf:byte(3, 4)
		len, pos = hi * 256 + lo, 5
	elseif len == 127 then
		if #buf < 10 then
			return nil, 0
		end
		local b = { buf:byte(3, 10) }
		if b[1] >= 128 then
			return nil, M.CLOSE.PROTOCOL
		end
		len = 0
		for i = 1, 8 do
			len = len * 256 + b[i]
		end
		pos = 11
	end

	if len > max_payload then
		return nil, M.CLOSE.TOO_BIG
	end
	if #buf < pos + 3 + len then
		return nil, 0
	end

	local mask = { buf:byte(pos, pos + 3) }
	local payload = unmask(buf:sub(pos + 4, pos + 3 + len), mask)
	return { fin = fin, opcode = opcode, payload = payload }, pos + 3 + len
end

--- Encode an unmasked server frame.
---@param opcode integer
---@param payload? string
---@return string
function M.encode(opcode, payload)
	payload = payload or ""
	local len = #payload
	local head
	if len < 126 then
		head = string.char(128 + opcode, len)
	elseif len < 65536 then
		head = string.char(128 + opcode, 126, bit.rshift(len, 8), bit.band(len, 255))
	else
		local b = {}
		local n = len
		for i = 8, 1, -1 do
			b[i] = n % 256
			n = math.floor(n / 256)
		end
		head = string.char(128 + opcode, 127, unpack(b))
	end
	return head .. payload
end

--- Close frame body: 2-byte status code, big endian.
---@param code integer
---@return string
function M.close_payload(code)
	return string.char(bit.rshift(code, 8), bit.band(code, 255))
end

return M
