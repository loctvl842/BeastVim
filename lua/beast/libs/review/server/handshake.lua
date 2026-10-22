-- HTTP upgrade handshake (RFC 6455 section 4) with token authentication.
-- The token check runs before any other validation: an unauthenticated peer
-- learns nothing beyond "401".

local bit = require("bit")

local sha1 = require("beast.libs.review.server.sha1")

local M = {}

local GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
local AUTH_HEADER = "x-claude-code-ide-authorization"

M.MAX_HEADER_BYTES = 8192

---@param key string  Sec-WebSocket-Key from the client
---@return string
function M.accept_key(key)
	return vim.base64.encode(sha1.sha1(key .. GUID))
end

--- Compare without bailing at the first differing byte.
---@param a? string
---@param b string
---@return boolean
local function equal(a, b)
	if type(a) ~= "string" or #a ~= #b then
		return false
	end
	local diff = 0
	for i = 1, #a do
		diff = bit.bor(diff, bit.bxor(a:byte(i), b:byte(i)))
	end
	return diff == 0
end

---@class Beast.Review.Request
---@field method string
---@field path string
---@field headers table<string, string>  lower-cased names

--- Parse a buffered HTTP request head.
---@param buf string
---@return Beast.Review.Request? request  nil while the head is incomplete (or malformed)
---@return string? rest                   bytes after the head
---@return string? err                    set when the head can never become valid
function M.parse(buf)
	local head_end = buf:find("\r\n\r\n", 1, true)
	if not head_end then
		if #buf > M.MAX_HEADER_BYTES then
			return nil, nil, "headers too large"
		end
		return nil
	end
	if head_end > M.MAX_HEADER_BYTES then
		return nil, nil, "headers too large"
	end

	local lines = vim.split(buf:sub(1, head_end - 1), "\r\n", { plain = true })
	local method, path = lines[1]:match("^(%u+) (%S+) HTTP/1%.1$")
	if not method then
		return nil, nil, "malformed request line"
	end

	local headers = {}
	for i = 2, #lines do
		-- vim.trim is linear; a `(.-)%s*$` pattern here is quadratic on padded values.
		local name, value = lines[i]:match("^([^:%s]+):(.*)$")
		if not name then
			return nil, nil, "malformed header"
		end
		headers[name:lower()] = vim.trim(value)
	end
	return { method = method, path = path, headers = headers }, buf:sub(head_end + 4)
end

---@param code integer
---@param reason string
---@return string
local function reject(code, reason)
	return ("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"):format(code, reason)
end

--- A client that offers subprotocols aborts unless the server answers with
--- exactly one of them (RFC 6455 section 4.2.2). Prefer MCP's.
---@param offered? string  Sec-WebSocket-Protocol request header
---@return string?
local function pick_protocol(offered)
	local first
	for name in (offered or ""):gmatch("[^,%s]+") do
		if name == "mcp" then
			return name
		end
		first = first or name
	end
	return first
end

--- Decide how to answer an upgrade request.
---@param req Beast.Review.Request
---@param token string
---@return boolean ok
---@return string response  101 on success, otherwise an error response
---@return string? reason   why the request was refused (for diagnostics)
function M.respond(req, token)
	local h = req.headers
	if not equal(h[AUTH_HEADER], token) then
		return false, reject(401, "Unauthorized"), h[AUTH_HEADER] and "wrong auth token" or "missing auth token"
	end
	if req.method ~= "GET" or (h.upgrade or ""):lower() ~= "websocket" then
		return false, reject(400, "Bad Request"), "not a WebSocket upgrade"
	end
	if not (h.connection or ""):lower():find("upgrade", 1, true) then
		return false, reject(400, "Bad Request"), "missing Connection: Upgrade"
	end
	if h["sec-websocket-version"] ~= "13" or not h["sec-websocket-key"] or h["sec-websocket-key"] == "" then
		return false, reject(400, "Bad Request"), "bad Sec-WebSocket-Version or Key"
	end

	local protocol = pick_protocol(h["sec-websocket-protocol"])
	return true,
		("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n%s\r\n"):format(
			M.accept_key(h["sec-websocket-key"]),
			protocol and ("Sec-WebSocket-Protocol: %s\r\n"):format(protocol) or ""
		)
end

return M
