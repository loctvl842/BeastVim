-- Fake WebSocket client shared by the review server tests.
--
-- Raw libuv TCP so the server is exercised exactly as a foreign client would:
-- masked frames, hand-written upgrade request, byte-level reads.

local bit = require("bit")

local uv = vim.uv or vim.loop

local M = {}

---@param cond fun(): boolean
---@param ms? integer
---@return boolean
function M.wait(cond, ms)
	return vim.wait(ms or 2000, cond, 5)
end
local wait = M.wait

--- Build a masked client frame.
function M.client_frame(opcode, payload, opts)
	opts = opts or {}
	local fin = opts.fin == false and 0 or 128
	local len = #payload
	local mask = { 0x12, 0x34, 0x56, 0x78 }
	local head
	if len < 126 then
		head = string.char(fin + opcode, (opts.unmasked and 0 or 128) + len)
	elseif len < 65536 then
		head = string.char(fin + opcode, 128 + 126, bit.rshift(len, 8), bit.band(len, 255))
	else
		head = string.char(
			fin + opcode,
			128 + 127,
			0,
			0,
			0,
			0,
			bit.band(bit.rshift(len, 24), 255),
			bit.band(bit.rshift(len, 16), 255),
			bit.band(bit.rshift(len, 8), 255),
			bit.band(len, 255)
		)
	end
	if opts.unmasked then
		return head .. payload
	end
	local out = {}
	for i = 1, len do
		out[i] = string.char(bit.bxor(payload:byte(i), mask[(i - 1) % 4 + 1]))
	end
	return head .. string.char(unpack(mask)) .. table.concat(out)
end

--- Minimal raw TCP client for exercising the server.
function M.connect(port)
	local c = { data = "", closed = false }
	c.sock = uv.new_tcp()
	c.sock:connect("127.0.0.1", port, function(err)
		c.connected, c.err = true, err
		if err then
			return
		end
		c.sock:read_start(function(rerr, chunk)
			if rerr or not chunk then
				c.closed = true
				return
			end
			c.data = c.data .. chunk
		end)
	end)
	wait(function()
		return c.connected
	end)
	function c:write(s)
		self.sock:write(s)
	end
	function c:close()
		if not self.sock:is_closing() then
			self.sock:close()
		end
	end
	return c
end

function M.upgrade_request(token, extra)
	local lines = {
		"GET / HTTP/1.1",
		"Host: 127.0.0.1",
		"Upgrade: websocket",
		"Connection: Upgrade",
		"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==",
		"Sec-WebSocket-Version: 13",
	}
	if token then
		lines[#lines + 1] = "x-claude-code-ide-authorization: " .. token
	end
	for _, l in ipairs(extra or {}) do
		lines[#lines + 1] = l
	end
	return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

--- Connect and complete the handshake; returns client and the bytes after the 101.
function M.open(port, token)
	local c = M.connect(port)
	c:write(M.upgrade_request(token))
	wait(function()
		return c.data:find("\r\n\r\n", 1, true) ~= nil
	end)
	local head_end = c.data:find("\r\n\r\n", 1, true)
	c.data = c.data:sub(head_end + 4)
	return c
end

--- Pop one complete server text frame (unmasked, < 64 KB) off `c.data`.
---@return string? payload
function M.next_message(c)
	local d = c.data
	if #d < 2 then
		return nil
	end
	local len, pos = d:byte(2), 3
	if len == 126 then
		if #d < 4 then
			return nil
		end
		len, pos = d:byte(3) * 256 + d:byte(4), 5
	end
	if #d < pos - 1 + len then
		return nil
	end
	c.data = d:sub(pos + len)
	return d:sub(pos, pos + len - 1)
end

--- Wait for the next JSON message from the server.
---@return table? msg
function M.recv(c, ms)
	local payload
	wait(function()
		payload = M.next_message(c)
		return payload ~= nil
	end, ms)
	return payload and vim.json.decode(payload) or nil
end

---@param c table
---@param msg table
function M.send(c, msg)
	c:write(M.client_frame(1, vim.json.encode(msg)))
end

return M
