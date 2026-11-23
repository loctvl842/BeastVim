local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

local TOKEN = "a3f1c2d4e5f60718293a4b5c6d7e8f90"
local SRV = "beast.libs.review.server"

t.describe("review server", function()
	t.before_each(function()
		h.clear()
		-- Fixture in the child: `_G.fx` holds the fake client, the lib modules and the helpers.
		n.exec_lua(function(token, srv_mod)
			package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path
			local fx = {
				ws = require("test.libs.review.ws_client"),
				frame = require(srv_mod .. ".frame"),
				handshake = require(srv_mod .. ".handshake"),
				server = require(srv_mod),
				sha1 = require(srv_mod .. ".sha1"),
				token = token,
			}
			_G.fx = fx

			---A handshake request with `overrides` applied; a `false` value removes the header.
			function fx.req(overrides)
				local headers = {
					upgrade = "websocket",
					connection = "Upgrade",
					["sec-websocket-key"] = "dGhlIHNhbXBsZSBub25jZQ==",
					["sec-websocket-version"] = "13",
					["x-claude-code-ide-authorization"] = token,
				}
				for k, v in pairs(overrides or {}) do
					headers[k] = v or nil
				end
				return { method = "GET", path = "/", headers = headers }
			end

			fx.wait = fx.ws.wait

			---Start the echo server the wire tests talk to.
			function fx.start()
				local events = { open = 0, closed = 0, messages = {}, rejected = {} }
				fx.events = events
				local srv, serr = fx.server.start({
					token = token,
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
					on_reject = function(reason)
						events.rejected[#events.rejected + 1] = reason
					end,
				})
				assert(srv, serr)
				fx.srv = srv
				return srv
			end

			---Open an authenticated client.
			function fx.open()
				return fx.ws.open(fx.srv.port, token)
			end

			---Connect, send `bytes`, wait for the server to close; return the client.
			function fx.send_until_closed(bytes, opener)
				local c = (opener or fx.open)()
				c:write(bytes)
				fx.wait(function()
					return c.closed
				end)
				return c
			end
		end, TOKEN, SRV)
	end)

	t.after_each(function()
		n.exec_lua(function()
			if _G.fx.srv then
				pcall(function()
					_G.fx.srv:close()
				end)
			end
		end)
	end)

	t.describe("sha1 (RFC 3174 vectors)", function()
		---@param s string
		---@param rep? integer
		local function hex(s, rep)
			return n.exec_lua(function(str, r)
				return _G.fx.sha1.hex(string.rep(str, r))
			end, s, rep or 1)
		end

		t.it("hashes the empty string", function()
			t.eq("da39a3ee5e6b4b0d3255bfef95601890afd80709", hex(""))
		end)

		t.it("hashes abc", function()
			t.eq("a9993e364706816aba3e25717850c26c9cd0d89d", hex("abc"))
		end)

		t.it("hashes the two-block message", function()
			t.eq("84983e441c3bd26ebaae4aa1f95129e5e54670f1", hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
		end)

		t.it("hashes a million a", function()
			t.eq("34aa973cd4c4daa4f61eeb2bdbad27316534016f", hex("a", 1000000))
		end)

		t.it("handles the padding edges (55 and 56 bytes)", function()
			t.eq(40, #hex("x", 55))
			t.eq(40, #hex("x", 56))
		end)

		t.it("returns a 20 byte raw digest", function()
			t.eq(
				20,
				n.exec_lua(function()
					return #_G.fx.sha1.sha1("abc")
				end)
			)
		end)
	end)

	t.describe("handshake", function()
		---@param overrides? table
		---@return { ok: boolean, resp: string, reason?: string }
		local function respond(overrides)
			return n.exec_lua(function(o)
				local ok, resp, reason = _G.fx.handshake.respond(_G.fx.req(o), _G.fx.token)
				return { ok = ok and true or false, resp = resp, reason = reason }
			end, overrides)
		end

		---@param s string
		---@param needle string
		local function has(s, needle)
			return s:find(needle, 1, true) ~= nil
		end

		t.it("computes the RFC 6455 accept key", function()
			t.eq(
				"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
				n.exec_lua(function()
					return _G.fx.handshake.accept_key("dGhlIHNhbXBsZSBub25jZQ==")
				end)
			)
		end)

		t.it("accepts a good request and carries the accept key", function()
			local r = respond()
			t.eq(true, r.ok)
			t.eq(true, has(r.resp, "101 Switching Protocols"))
			t.eq(true, has(r.resp, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="))
		end)

		t.it("answers no subprotocol when none is offered", function()
			t.eq(false, has(respond().resp, "Sec-WebSocket-Protocol"))
		end)

		t.it("echoes an offered mcp", function()
			t.eq(true, has(respond({ ["sec-websocket-protocol"] = "mcp" }).resp, "Sec-WebSocket-Protocol: mcp\r\n"))
		end)

		t.it("prefers mcp from a list", function()
			t.eq(true, has(respond({ ["sec-websocket-protocol"] = "foo, mcp, bar" }).resp, "Sec-WebSocket-Protocol: mcp\r\n"))
		end)

		t.it("otherwise chooses exactly one offered protocol", function()
			local resp = respond({ ["sec-websocket-protocol"] = "foo, bar" }).resp
			t.eq(true, has(resp, "Sec-WebSocket-Protocol: foo\r\n"))
			t.eq(false, has(resp, "bar"))
		end)

		t.it("refuses a wrong token with 401 and a reason", function()
			local r = respond({ ["x-claude-code-ide-authorization"] = "wrong" })
			t.eq("wrong auth token", r.reason)
			t.eq(false, r.ok)
			t.eq(true, has(r.resp, "401"))
		end)

		t.it("refuses a missing token with 401 and a reason", function()
			local r = respond({ ["x-claude-code-ide-authorization"] = false })
			t.eq("missing auth token", r.reason)
			t.eq(false, r.ok)
			t.eq(true, has(r.resp, "401"))
		end)

		t.it("refuses a longer token with 401", function()
			local r = respond({ ["x-claude-code-ide-authorization"] = TOKEN .. "0" })
			t.eq(false, r.ok)
			t.eq(true, has(r.resp, "401"))
		end)

		t.it("checks auth before anything else", function()
			local r = respond({ ["x-claude-code-ide-authorization"] = false, upgrade = false })
			t.eq(false, r.ok)
			t.eq(true, has(r.resp, "401"))
		end)

		t.it("refuses a missing key with 400", function()
			local r = respond({ ["sec-websocket-key"] = false })
			t.eq(false, r.ok)
			t.eq(true, has(r.resp, "400"))
		end)

		t.it("refuses a wrong version with 400", function()
			local r = respond({ ["sec-websocket-version"] = "8" })
			t.eq(false, r.ok)
			t.eq(true, has(r.resp, "400"))
		end)

		t.it("refuses a non-upgrade with 400", function()
			local r = respond({ upgrade = "h2c" })
			t.eq(false, r.ok)
			t.eq(true, has(r.resp, "400"))
		end)

		t.it("parses a request head, trimming and lower-casing headers and keeping trailing bytes", function()
			t.eq(
				{ path = "/x", foo = "bar", rest = "EXTRA" },
				n.exec_lua(function()
					local parsed, rest = _G.fx.handshake.parse("GET /x HTTP/1.1\r\nHost: a\r\nX-Foo:  bar \r\n\r\nEXTRA")
					return { path = parsed and parsed.path, foo = parsed and parsed.headers["x-foo"], rest = rest }
				end)
			)
		end)

		t.it("returns nil for an incomplete head", function()
			t.eq(
				true,
				n.exec_lua(function()
					return (_G.fx.handshake.parse("GET / HTTP/1.1\r\nHost: a\r\n")) == nil
				end)
			)
		end)

		t.it("errors on an oversized head", function()
			t.eq(
				"headers too large",
				n.exec_lua(function()
					local _, _, err = _G.fx.handshake.parse(string.rep("A", 9000))
					return err
				end)
			)
		end)

		t.it("errors on a malformed request line", function()
			t.eq(
				"malformed request line",
				n.exec_lua(function()
					local _, _, err = _G.fx.handshake.parse("NOT HTTP\r\n\r\n")
					return err
				end)
			)
		end)
	end)

	t.describe("frame", function()
		---Run `fn` in the child with the frame module, the client frame builder and the opcodes.
		---@param body string
		local function lua(body, ...)
			return n.exec_lua("local fx = _G.fx; local frame, cf = fx.frame, fx.ws.client_frame; " .. body, ...)
		end

		t.it("decodes a text frame", function()
			t.eq(
				{ payload = "hello", used = 11, fin = true },
				lua([[
					local f, used = frame.decode(cf(frame.OP.TEXT, "hello"), 1000)
					return { payload = f and f.payload, used = used, fin = f and f.fin }
				]])
			)
		end)

		t.it("waits on a partial frame", function()
			t.eq(
				{ nothing = true, used = 0 },
				lua([[
					local pf, pused = frame.decode(cf(frame.OP.TEXT, "hello"):sub(1, 7), 1000)
					return { nothing = pf == nil, used = pused }
				]])
			)
		end)

		t.it("decodes back-to-back frames", function()
			t.eq(
				{ "a", "b" },
				lua([[
					local two = cf(frame.OP.TEXT, "a") .. cf(frame.OP.TEXT, "b")
					local f1, u1 = frame.decode(two, 1000)
					local f2 = frame.decode(two:sub(u1 + 1), 1000)
					return { f1.payload, f2.payload }
				]])
			)
		end)

		t.it("decodes 16-bit and 64-bit lengths", function()
			t.eq(
				{ big = true, huge = true },
				lua([[
					local big = string.rep("x", 300)
					local huge = string.rep("y", 70000)
					return {
						big = frame.decode(cf(frame.OP.TEXT, big), 1000).payload == big,
						huge = frame.decode(cf(frame.OP.TEXT, huge), 100000).payload == huge,
					}
				]])
			)
		end)

		t.it("closes 1009 over the limit", function()
			t.eq(
				true,
				lua([[
					local _, code = frame.decode(cf(frame.OP.TEXT, string.rep("y", 70000)), 1000)
					return code == frame.CLOSE.TOO_BIG
				]])
			)
		end)

		t.it("closes 1002 on an unmasked client frame", function()
			t.eq(
				true,
				lua([[
					local _, code = frame.decode(cf(frame.OP.TEXT, "hi", { unmasked = true }), 1000)
					return code == frame.CLOSE.PROTOCOL
				]])
			)
		end)

		t.it("closes 1002 on a fragmented control frame", function()
			t.eq(
				true,
				lua([[
					local _, code = frame.decode(cf(frame.OP.PING, "x", { fin = false }), 1000)
					return code == frame.CLOSE.PROTOCOL
				]])
			)
		end)

		t.it("encodes short, 16-bit and 64-bit headers", function()
			t.eq(
				{ short = "\129\2hi", mid = "\129\126\1\44", long = "\129\127\0\0\0\0\0\1\17\112" },
				lua([[
					return {
						short = frame.encode(frame.OP.TEXT, "hi"),
						mid = frame.encode(frame.OP.TEXT, string.rep("x", 300)):sub(1, 4),
						long = frame.encode(frame.OP.TEXT, string.rep("y", 70000)):sub(1, 10),
					}
				]])
			)
		end)
	end)

	t.describe("server", function()
		t.before_each(function()
			n.exec_lua(function()
				_G.fx.start()
			end)
		end)

		---Run `body` in the child with `fx`, `ws`, `frame`, `srv`, `events`, `wait` and the opcodes in scope.
		---@param body string
		local function lua(body, ...)
			return n.exec_lua(
				"local fx = _G.fx; local ws, frame, srv, events, wait = fx.ws, fx.frame, fx.srv, fx.events, fx.wait; "
					.. "local cf, OP = ws.client_frame, fx.frame.OP; "
					.. body,
				...
			)
		end

		t.describe("lifecycle", function()
			t.it("binds an OS-assigned port and accepts a TCP connection on loopback", function()
				t.eq(
					{ bound = true, err_free = true },
					lua([[
						local c = ws.connect(srv.port)
						local out = { bound = srv.port > 0, err_free = c.err == nil }
						c:close()
						return out
					]])
				)
			end)
		end)

		t.describe("authentication", function()
			t.it("answers a bad token with 401 and drops the connection", function()
				t.eq(
					{ unauthorized = true, closed = true },
					lua([[
						local c = ws.connect(srv.port)
						c:write(ws.upgrade_request("wrong-token"))
						wait(function() return c.closed end)
						local out = {
							unauthorized = c.data:find("401 Unauthorized", 1, true) ~= nil,
							closed = c.closed,
						}
						c:close()
						return out
					]])
				)
			end)

			t.it("answers a missing token with 401", function()
				t.eq(
					true,
					lua([[
						local c = ws.connect(srv.port)
						c:write(ws.upgrade_request(nil))
						wait(function() return c.closed end)
						local ok = c.data:find("401", 1, true) ~= nil
						c:close()
						return ok
					]])
				)
			end)

			t.it("reports refusals with a reason and never reaches on_open", function()
				t.eq(
					{ open = 0, reached = true, reasons = { "wrong auth token", "missing auth token" } },
					lua([[
						local c = ws.connect(srv.port)
						c:write(ws.upgrade_request("wrong-token"))
						wait(function() return c.closed end)
						c:close()
						c = ws.connect(srv.port)
						c:write(ws.upgrade_request(nil))
						wait(function() return c.closed end)
						c:close()
						return {
							open = events.open,
							reached = wait(function() return #events.rejected == 2 end),
							reasons = events.rejected,
						}
					]])
				)
			end)

			t.it("echoes Sec-WebSocket-Protocol: mcp on the wire", function()
				t.eq(
					true,
					lua([[
						local c = ws.connect(srv.port)
						c:write(ws.upgrade_request(fx.token, { "Sec-WebSocket-Protocol: mcp" }))
						wait(function() return c.data:find("\r\n\r\n", 1, true) ~= nil end)
						local ok = c.data:find("101", 1, true) ~= nil
							and c.data:find("Sec-WebSocket-Protocol: mcp\r\n", 1, true) ~= nil
						c:close()
						return ok
					]])
				)
			end)
		end)

		t.describe("messages", function()
			t.it("fires on_open once", function()
				t.eq(
					true,
					lua([[
						local c = fx.open()
						local ok = wait(function() return events.open == 1 end)
						c:close()
						return ok
					]])
				)
			end)

			t.it("receives text and replies with an unmasked text frame", function()
				t.eq(
					{ "hello", "\129\6echo:5" },
					lua([[
						local c = fx.open()
						c:write(cf(OP.TEXT, "hello"))
						wait(function() return #events.messages == 1 end)
						wait(function() return #c.data >= 8 end)
						local out = { events.messages[1], c.data:sub(1, 8) }
						c:close()
						return out
					]])
				)
			end)

			t.it("keeps a 70 KB message intact", function()
				t.eq(
					true,
					lua([[
						local c = fx.open()
						local big = string.rep("z", 70000)
						c:write(cf(OP.TEXT, big))
						wait(function() return #events.messages == 1 end)
						local ok = events.messages[1] == big
						c:close()
						return ok
					]])
				)
			end)

			t.it("reassembles a fragmented message", function()
				t.eq(
					"hello",
					lua([[
						local c = fx.open()
						c:write(cf(OP.TEXT, "hel", { fin = false }) .. cf(OP.CONT, "lo"))
						wait(function() return #events.messages == 1 end)
						local out = events.messages[1]
						c:close()
						return out
					]])
				)
			end)

			t.it("answers a ping with a pong", function()
				t.eq(
					"\138\2pp",
					lua([[
						local c = fx.open()
						c:write(cf(OP.PING, "pp"))
						wait(function() return #c.data >= 4 end)
						local out = c.data:sub(1, 4)
						c:close()
						return out
					]])
				)
			end)

			t.it("parses a frame delivered one byte at a time", function()
				t.eq(
					"slow",
					lua([[
						local c = fx.open()
						local f = cf(OP.TEXT, "slow")
						for i = 1, #f do
							c:write(f:sub(i, i))
							vim.wait(2)
						end
						wait(function() return #events.messages == 1 end)
						local out = events.messages[1]
						c:close()
						return out
					]])
				)
			end)

			t.it("closes the connection on a close frame and fires on_close", function()
				t.eq(
					{ closed = true, on_close = true },
					lua([[
						local c = fx.open()
						wait(function() return events.open == 1 end)
						c:write(cf(OP.CLOSE, "\3\232"))
						wait(function() return c.closed end)
						local out = {
							closed = c.closed,
							on_close = wait(function() return events.closed == 1 end),
						}
						c:close()
						return out
					]])
				)
			end)
		end)

		t.describe("protocol violations", function()
			---Open a client, send `bytes` (a Lua expression), and return the first 4 bytes of the reply and `closed`.
			---@param expr string
			local function violate(expr)
				return lua("local c = fx.send_until_closed(" .. expr .. "); local out = { c.data:sub(1, 4), c.closed }; c:close(); return out")
			end

			t.it("closes 1009 on an oversize message", function()
				t.eq({ "\136\2\3\241", true }, violate('cf(OP.TEXT, string.rep("q", 200000))'))
			end)

			t.it("closes 1002 on an unmasked frame", function()
				t.eq({ "\136\2\3\234", true }, violate('cf(OP.TEXT, "x", { unmasked = true })'))
			end)

			t.it("closes 1002 on a stray continuation", function()
				t.eq({ "\136\2\3\234", true }, violate('cf(OP.CONT, "x")'))
			end)

			t.it("closes 1003 on a binary frame", function()
				t.eq({ "\136\2\3\235", true }, violate('cf(OP.BINARY, "x")'))
			end)

			t.it("closes 1002 on a reserved opcode", function()
				t.eq({ "\136\2\3\234", true }, violate('cf(3, "x")'))
			end)

			t.it("closes 1002 when an rsv bit is set", function()
				t.eq({ "\136\2\3\234", true }, violate('(function() local r = cf(OP.TEXT, "x"); return string.char(r:byte(1) + 0x40) .. r:sub(2) end)()'))
			end)

			t.it("delivers nothing and sends one close frame after a close is initiated", function()
				t.eq(
					{ delivered = 0, close_frames = 1 },
					lua([[
						local c = fx.send_until_closed(cf(OP.TEXT, string.rep("q", 200000)) .. cf(OP.TEXT, "late"))
						vim.wait(50)
						local out = {
							delivered = #events.messages,
							close_frames = select(2, c.data:gsub("\136\2\3\241", "")),
						}
						c:close()
						return out
					]])
				)
			end)

			t.it("allows a ping between fragments", function()
				t.eq(
					"abcd",
					lua([[
						local c = fx.open()
						c:write(cf(OP.TEXT, "ab", { fin = false }) .. cf(OP.PING, "p") .. cf(OP.CONT, "cd"))
						wait(function() return #events.messages == 1 end)
						local out = events.messages[#events.messages]
						c:close()
						return out
					]])
				)
			end)
		end)

		t.describe("hostile handshakes", function()
			t.it("drops an endless header with a 400", function()
				t.eq(
					true,
					lua([[
						local c = ws.connect(srv.port)
						c:write(string.rep("A", 20000))
						wait(function() return c.closed end)
						local ok = c.closed and c.data:find("400", 1, true) ~= nil
						c:close()
						return ok
					]])
				)
			end)

			t.it("drops a silent peer after the handshake timeout", function()
				t.eq(
					true,
					lua([[
						local c = ws.connect(srv.port)
						local ok = wait(function() return c.closed end, 1500)
						c:close()
						return ok
					]])
				)
			end)
		end)

		t.describe("connection leaks", function()
			t.it("releases every connection", function()
				t.eq(
					true,
					lua([[
						local function live()
							local count = 0
							for _ in pairs(srv.clients) do
								count = count + 1
							end
							return count
						end
						for _ = 1, 20 do
							local c = ws.connect(srv.port)
							c:write(ws.upgrade_request("wrong"))
							wait(function() return c.closed end)
							c:close()
						end
						for _ = 1, 10 do
							ws.connect(srv.port):close() -- connect and vanish
						end
						for _ = 1, 10 do
							fx.open():close()
						end
						local silent = ws.connect(srv.port) -- exercises the handshake timeout path
						local ok = wait(function() return live() == 0 end, 3000)
						silent:close()
						return ok
					]])
				)
			end)
		end)

		t.describe("stop", function()
			t.it("drops open clients and stops accepting", function()
				t.eq(
					{ dropped = true, refuses = true },
					lua([[
						local c = fx.open()
						local port = srv.port
						srv:close()
						local out = { dropped = wait(function() return c.closed end) }
						c:close()
						local late = ws.connect(port)
						out.refuses = late.err ~= nil
						late:close()
						return out
					]])
				)
			end)
		end)

		t.describe("fixed port", function()
			t.it("refuses a held port and rebinds a released one", function()
				t.eq(
					{ clash_refused = true, rebound = true },
					lua([[
						local first = assert(fx.server.start({ token = fx.token }))
						local port = first.port
						local clash, cerr = fx.server.start({ token = fx.token, port = port })
						local out = { clash_refused = clash == nil and cerr ~= nil }
						first:close()
						local again = fx.server.start({ token = fx.token, port = port })
						out.rebound = again ~= nil and again.port == port
						if again then
							again:close()
						end
						return out
					]])
				)
			end)
		end)
	end)
end)
