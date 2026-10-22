-- =========================================================================
-- Test: beast.libs.review.server (SHA-1, handshake, framing, TCP transport)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-review-ws.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;./tests/?.lua;" .. package.path

local bit = require("bit")
local frame = require("beast.libs.review.server.frame")
local handshake = require("beast.libs.review.server.handshake")
local server = require("beast.libs.review.server")
local sha1 = require("beast.libs.review.server.sha1")

local ws = require("review_ws_client")
local client_frame, connect, upgrade_request, wait = ws.client_frame, ws.connect, ws.upgrade_request, ws.wait
local TOKEN = "a3f1c2d4e5f60718293a4b5c6d7e8f90"

local passed, failed = 0, 0

local function assert_test(name, cond, msg)
	if cond then
		passed = passed + 1
		io.write("  PASS: " .. name .. "\n")
	else
		failed = failed + 1
		io.write("  FAIL: " .. name .. " - " .. (msg or "assertion failed") .. "\n")
	end
end

local function assert_eq(name, got, expected)
	assert_test(name, vim.deep_equal(got, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(got))
end

print("== sha1 (RFC 3174 vectors) ==")
do
	assert_eq("empty", sha1.hex(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
	assert_eq("abc", sha1.hex("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
	assert_eq("two-block message", sha1.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
	assert_eq("million a", sha1.hex(string.rep("a", 1000000)), "34aa973cd4c4daa4f61eeb2bdbad27316534016f")
	assert_eq("55 bytes (padding edge)", #sha1.hex(string.rep("x", 55)), 40)
	assert_eq("56 bytes (padding edge)", #sha1.hex(string.rep("x", 56)), 40)
	assert_eq("raw digest is 20 bytes", #sha1.sha1("abc"), 20)
end

print("== handshake ==")
do
	assert_eq("RFC 6455 accept key", handshake.accept_key("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

	local function req(overrides)
		local headers = {
			upgrade = "websocket",
			connection = "Upgrade",
			["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
			["sec-websocket-version"] = "13",
			["x-claude-code-ide-authorization"] = TOKEN,
		}
		for k, v in pairs(overrides or {}) do
			headers[k] = v or nil
		end
		return { method = "GET", path = "/", headers = headers }
	end

	local ok, resp = handshake.respond(req(), TOKEN)
	assert_test("good request accepted", ok and resp:find("101 Switching Protocols", 1, true) ~= nil)
	assert_test("response carries accept key", resp:find("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", 1, true) ~= nil)

	ok, resp = handshake.respond(req({ ["x-claude-code-ide-authorization"] = "wrong" }), TOKEN)
	assert_test("wrong token -> 401", not ok and resp:find("401", 1, true) ~= nil)
	ok, resp = handshake.respond(req({ ["x-claude-code-ide-authorization"] = false }), TOKEN)
	assert_test("missing token -> 401", not ok and resp:find("401", 1, true) ~= nil)
	ok, resp = handshake.respond(req({ ["x-claude-code-ide-authorization"] = TOKEN .. "0" }), TOKEN)
	assert_test("longer token -> 401", not ok and resp:find("401", 1, true) ~= nil)
	ok, resp = handshake.respond(req({ ["x-claude-code-ide-authorization"] = false, upgrade = false }), TOKEN)
	assert_test("auth is checked before anything else", not ok and resp:find("401", 1, true) ~= nil)
	ok, resp = handshake.respond(req({ ["sec-websocket-key"] = false }), TOKEN)
	assert_test("missing key -> 400", not ok and resp:find("400", 1, true) ~= nil)
	ok, resp = handshake.respond(req({ ["sec-websocket-version"] = "8" }), TOKEN)
	assert_test("wrong version -> 400", not ok and resp:find("400", 1, true) ~= nil)
	ok, resp = handshake.respond(req({ upgrade = "h2c" }), TOKEN)
	assert_test("not an upgrade -> 400", not ok and resp:find("400", 1, true) ~= nil)

	local parsed, rest = handshake.parse("GET /x HTTP/1.1\r\nHost: a\r\nX-Foo:  bar \r\n\r\nEXTRA")
	assert_eq("parse path", parsed and parsed.path, "/x")
	assert_eq("parse header (trimmed, lower-cased)", parsed and parsed.headers["x-foo"], "bar")
	assert_eq("parse leaves trailing bytes", rest, "EXTRA")
	assert_eq("incomplete head -> nil", (handshake.parse("GET / HTTP/1.1\r\nHost: a\r\n")), nil)
	local _, _, err = handshake.parse(string.rep("A", 9000))
	assert_eq("oversized head -> error", err, "headers too large")
	_, _, err = handshake.parse("NOT HTTP\r\n\r\n")
	assert_eq("malformed request line -> error", err, "malformed request line")
end

print("== frame ==")
do
	local f, used = frame.decode(client_frame(frame.OP.TEXT, "hello"), 1000)
	assert_eq("decode text", f and f.payload, "hello")
	assert_eq("decode consumed", used, 11)
	assert_test("fin set", f and f.fin == true)

	local partial = client_frame(frame.OP.TEXT, "hello"):sub(1, 7)
	local pf, pused = frame.decode(partial, 1000)
	assert_test("partial frame waits", pf == nil and pused == 0)

	local two = client_frame(frame.OP.TEXT, "a") .. client_frame(frame.OP.TEXT, "b")
	local f1, u1 = frame.decode(two, 1000)
	local f2 = frame.decode(two:sub(u1 + 1), 1000)
	assert_eq("back-to-back frames", { f1.payload, f2.payload }, { "a", "b" })

	local big = string.rep("x", 300)
	assert_eq("16-bit length", (frame.decode(client_frame(frame.OP.TEXT, big), 1000)).payload, big)
	local huge = string.rep("y", 70000)
	assert_eq("64-bit length", (frame.decode(client_frame(frame.OP.TEXT, huge), 100000)).payload, huge)

	local _, code = frame.decode(client_frame(frame.OP.TEXT, huge), 1000)
	assert_eq("over limit -> 1009", code, frame.CLOSE.TOO_BIG)
	_, code = frame.decode(client_frame(frame.OP.TEXT, "hi", { unmasked = true }), 1000)
	assert_eq("unmasked client frame -> 1002", code, frame.CLOSE.PROTOCOL)
	_, code = frame.decode(client_frame(frame.OP.PING, "x", { fin = false }), 1000)
	assert_eq("fragmented control frame -> 1002", code, frame.CLOSE.PROTOCOL)

	assert_eq("encode short", frame.encode(frame.OP.TEXT, "hi"), "\129\2hi")
	assert_eq("encode 16-bit header", frame.encode(frame.OP.TEXT, big):sub(1, 4), "\129\126\1\44")
	local enc = frame.encode(frame.OP.TEXT, huge)
	assert_eq("encode 64-bit header", enc:sub(1, 10), "\129\127\0\0\0\0\0\1\17\112")
end

local function open(port)
	return ws.open(port, TOKEN)
end

local events = { open = 0, closed = 0, messages = {} }
local srv, serr = server.start({
	token = TOKEN,
	max_payload = 100000,
	handshake_timeout_ms = 300,
	on_open = function()
		events.open = events.open + 1
	end,
	on_message = function(client, text)
		events.messages[#events.messages + 1] = text
		client:send("echo:" .. #text)
	end,
	on_close = function()
		events.closed = events.closed + 1
	end,
})
assert(srv, serr)

print("== server: lifecycle ==")
do
	assert_test("bound an OS-assigned port", srv.port > 0)
	local c = connect(srv.port)
	assert_test("accepts a TCP connection on loopback", c.err == nil)
	c:close()
end

print("== server: authentication ==")
do
	local c = connect(srv.port)
	c:write(upgrade_request("wrong-token"))
	wait(function()
		return c.closed
	end)
	assert_test("bad token gets 401", c.data:find("401 Unauthorized", 1, true) ~= nil)
	assert_test("bad token connection closed", c.closed)
	c:close()

	c = connect(srv.port)
	c:write(upgrade_request(nil))
	wait(function()
		return c.closed
	end)
	assert_test("no token gets 401", c.data:find("401", 1, true) ~= nil)
	c:close()
	assert_eq("rejected peers never reach on_open", events.open, 0)
end

print("== server: messages ==")
do
	local c = open(srv.port)
	assert_eq(
		"on_open fired once",
		wait(function()
			return events.open == 1
		end),
		true
	)

	c:write(client_frame(frame.OP.TEXT, "hello"))
	wait(function()
		return #events.messages == 1
	end)
	assert_eq("server received text", events.messages[1], "hello")
	wait(function()
		return #c.data >= 8
	end)
	assert_eq("server reply is an unmasked text frame", c.data:sub(1, 8), "\129\6echo:5")
	c.data = ""

	local big = string.rep("z", 70000)
	c:write(client_frame(frame.OP.TEXT, big))
	wait(function()
		return #events.messages == 2
	end)
	assert_eq("70 KB message intact", events.messages[2], big)
	wait(function()
		return #c.data >= 12 -- "echo:70000" reply
	end)
	c.data = ""

	c:write(client_frame(frame.OP.TEXT, "hel", { fin = false }) .. client_frame(frame.OP.CONT, "lo"))
	wait(function()
		return #events.messages == 3
	end)
	assert_eq("fragmented message reassembled", events.messages[3], "hello")
	wait(function()
		return #c.data >= 8 -- "echo:5" reply
	end)
	c.data = ""

	c:write(client_frame(frame.OP.PING, "pp"))
	wait(function()
		return #c.data >= 4
	end)
	assert_eq("ping answered with pong", c.data:sub(1, 4), "\138\2pp")
	c.data = ""

	-- Byte-at-a-time delivery must still parse.
	local f = client_frame(frame.OP.TEXT, "slow")
	for i = 1, #f do
		c:write(f:sub(i, i))
		vim.wait(2)
	end
	wait(function()
		return #events.messages == 4
	end)
	assert_eq("byte-at-a-time frame parsed", events.messages[4], "slow")

	c:write(client_frame(frame.OP.CLOSE, "\3\232"))
	wait(function()
		return c.closed
	end)
	assert_test("close frame closes the connection", c.closed)
	assert_eq(
		"on_close fired",
		wait(function()
			return events.closed == 1
		end),
		true
	)
	c:close()
end

print("== server: protocol violations ==")
do
	local c = open(srv.port)
	c:write(client_frame(frame.OP.TEXT, string.rep("q", 200000)))
	wait(function()
		return c.closed
	end)
	assert_eq("oversize -> close 1009", c.data:sub(1, 4), "\136\2\3\241")
	assert_test("oversize connection dropped", c.closed)
	c:close()

	c = open(srv.port)
	c:write(client_frame(frame.OP.TEXT, "x", { unmasked = true }))
	wait(function()
		return c.closed
	end)
	assert_eq("unmasked -> close 1002", c.data:sub(1, 4), "\136\2\3\234")
	c:close()

	c = open(srv.port)
	c:write(client_frame(frame.OP.CONT, "x"))
	wait(function()
		return c.closed
	end)
	assert_eq("stray continuation -> close 1002", c.data:sub(1, 4), "\136\2\3\234")
	c:close()

	c = open(srv.port)
	c:write(client_frame(frame.OP.BINARY, "x"))
	wait(function()
		return c.closed
	end)
	assert_eq("binary -> close 1003", c.data:sub(1, 4), "\136\2\3\235")
	c:close()
end

print("== server: hostile handshakes ==")
do
	local c = connect(srv.port)
	c:write(string.rep("A", 20000))
	wait(function()
		return c.closed
	end)
	assert_test("endless header dropped", c.closed and c.data:find("400", 1, true) ~= nil)
	c:close()

	c = connect(srv.port)
	local ok = wait(function()
		return c.closed
	end, 1500)
	assert_test("silent peer dropped by handshake timeout", ok)
	c:close()
end

print("== server: more protocol rules ==")
do
	local c = open(srv.port)
	c:write(client_frame(3, "x"))
	wait(function()
		return c.closed
	end)
	assert_eq("reserved opcode -> close 1002", c.data:sub(1, 4), "\136\2\3\234")
	c:close()

	c = open(srv.port)
	local rsv = client_frame(frame.OP.TEXT, "x")
	c:write(string.char(rsv:byte(1) + 0x40) .. rsv:sub(2))
	wait(function()
		return c.closed
	end)
	assert_eq("rsv bit set -> close 1002", c.data:sub(1, 4), "\136\2\3\234")
	c:close()

	c = open(srv.port)
	local before = #events.messages
	c:write(client_frame(frame.OP.TEXT, "ab", { fin = false }) .. client_frame(frame.OP.PING, "p") .. client_frame(frame.OP.CONT, "cd"))
	wait(function()
		return #events.messages == before + 1
	end)
	assert_eq("ping between fragments allowed", events.messages[#events.messages], "abcd")
	c:close()

	-- After a close is initiated, further input is neither parsed nor delivered.
	c = open(srv.port)
	before = #events.messages
	c:write(client_frame(frame.OP.TEXT, string.rep("q", 200000)) .. client_frame(frame.OP.TEXT, "late"))
	wait(function()
		return c.closed
	end)
	vim.wait(50)
	assert_eq("nothing delivered after close", #events.messages, before)
	assert_eq("exactly one close frame sent", select(2, c.data:gsub("\136\2\3\241", "")), 1)
	c:close()
end

print("== server: no connection leak ==")
do
	local function live()
		local n = 0
		for _ in pairs(srv.clients) do
			n = n + 1
		end
		return n
	end
	for _ = 1, 20 do
		local c = connect(srv.port)
		c:write(upgrade_request("wrong"))
		wait(function()
			return c.closed
		end)
		c:close()
	end
	for _ = 1, 10 do
		connect(srv.port):close() -- connect and vanish
	end
	for _ = 1, 10 do
		local c = open(srv.port)
		c:close()
	end
	local silent = connect(srv.port) -- exercises the handshake timeout path
	assert_eq(
		"all connections released",
		wait(function()
			return live() == 0
		end, 3000),
		true
	)
	silent:close()
end

print("== server: stop ==")
do
	local c = open(srv.port)
	local port = srv.port
	srv:close()
	assert_eq(
		"open client dropped on stop",
		wait(function()
			return c.closed
		end),
		true
	)
	c:close()

	local late = connect(port)
	assert_test("no longer accepting", late.err ~= nil)
	late:close()
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
