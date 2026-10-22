-- SHA-1 on LuaJIT's `bit` library. Neovim ships SHA-256 (vim.fn.sha256) but not
-- SHA-1, and the WebSocket handshake (RFC 6455) requires it. Used only for
-- Sec-WebSocket-Accept, never for anything security-relevant.

local bit = require("bit")

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol, tobit, tohex = bit.lshift, bit.rshift, bit.rol, bit.tobit, bit.tohex

local M = {}

---@param n integer
---@return string
local function be32(n)
	return string.char(band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255))
end

--- Hex digest.
---@param msg string
---@return string
function M.hex(msg)
	local len = #msg
	local bits = len * 8
	msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. be32(math.floor(bits / 2 ^ 32)) .. be32(bits % 2 ^ 32)

	local h0, h1, h2, h3, h4 = 0x67452301, tobit(0xEFCDAB89), tobit(0x98BADCFE), 0x10325476, tobit(0xC3D2E1F0)
	local w = {}

	for base = 0, #msg - 64, 64 do
		for i = 0, 15 do
			local b1, b2, b3, b4 = msg:byte(base + 4 * i + 1, base + 4 * i + 4)
			w[i] = bor(lshift(b1, 24), lshift(b2, 16), lshift(b3, 8), b4)
		end
		for i = 16, 79 do
			w[i] = rol(bxor(w[i - 3], w[i - 8], w[i - 14], w[i - 16]), 1)
		end

		local a, b, c, d, e = h0, h1, h2, h3, h4
		for i = 0, 79 do
			local f, k
			if i < 20 then
				f, k = bor(band(b, c), band(bnot(b), d)), 0x5A827999
			elseif i < 40 then
				f, k = bxor(b, c, d), 0x6ED9EBA1
			elseif i < 60 then
				f, k = bor(band(b, c), band(b, d), band(c, d)), tobit(0x8F1BBCDC)
			else
				f, k = bxor(b, c, d), tobit(0xCA62C1D6)
			end
			local temp = tobit(rol(a, 5) + f + e + k + w[i])
			e, d, c, b, a = d, c, rol(b, 30), a, temp
		end
		h0, h1, h2, h3, h4 = tobit(h0 + a), tobit(h1 + b), tobit(h2 + c), tobit(h3 + d), tobit(h4 + e)
	end

	return tohex(h0) .. tohex(h1) .. tohex(h2) .. tohex(h3) .. tohex(h4)
end

--- Raw 20-byte digest.
---@param msg string
---@return string
function M.sha1(msg)
	return (M.hex(msg):gsub("%x%x", function(c)
		return string.char(tonumber(c, 16))
	end))
end

return M
