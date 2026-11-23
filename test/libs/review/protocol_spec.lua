local h = require("test.helper")
local t = require("test.testutil")
local n = h.n

t.describe("review MCP protocol", function()
	t.before_each(function()
		h.clear()
		-- Fixture in the child: `_G.fx` holds the paths, the fake client and the helpers.
		n.exec_lua(function()
			package.path = vim.fn.getcwd() .. "/?.lua;" .. package.path
			local uv = vim.uv
			local ws = require("test.libs.review.ws_client")
			local session = require("beast.libs.review.session")

			local fx = { ws = ws, uv = uv, session = session, counter = 0, nextid = 0 }
			_G.fx = fx

			-- Isolate the discovery directory from the real ~/.claude.
			fx.root = vim.fn.tempname()
			fx.work = fx.root .. "/work"
			fx.config_dir = fx.root .. "/claude"
			fx.lock_dir = fx.config_dir .. "/ide"
			vim.fn.mkdir(fx.config_dir, "p")
			vim.fn.mkdir(fx.work, "p")
			vim.env.CLAUDE_CONFIG_DIR = fx.config_dir

			require("beast.libs.toast").toast = function() end
			vim.notify = function()
				error("review must not call vim.notify")
			end

			fx.review = require("beast.libs.review")
			fx.render = require("beast.libs.review.render")

			function fx.make_file(content)
				fx.counter = fx.counter + 1
				local path = fx.work .. "/f" .. fx.counter .. ".txt"
				local f = assert(io.open(path, "wb"))
				f:write(content)
				f:close()
				return path
			end

			function fx.read(path)
				local f = io.open(path, "rb")
				if not f then
					return nil
				end
				local s = f:read("*a")
				f:close()
				return s
			end

			function fx.write_lock(name, data)
				vim.fn.mkdir(fx.lock_dir, "p")
				local f = assert(io.open(fx.lock_dir .. "/" .. name, "wb"))
				f:write(vim.json.encode(data))
				f:close()
			end

			function fx.exists(path)
				return uv.fs_stat(path) ~= nil
			end

			-- A pid that is certainly gone: a child that already exited.
			local job = vim.fn.jobstart({ "true" })
			local dead = vim.fn.jobpid(job)
			vim.fn.jobwait({ job }, 2000)
			local function lock(pid, name)
				return { pid = pid, ideName = name, transport = "ws", authToken = "x", workspaceFolders = {} }
			end
			fx.write_lock("1.lock", lock(dead, "BeastVim"))
			fx.write_lock("2.lock", lock(dead, "VS Code"))
			fx.write_lock("3.lock", lock(uv.os_getpid(), "BeastVim"))
			fx.write_lock("6.lock", lock(dead, "BeastVim (09:00:00, pid 1)"))
			fx.write_lock("4.lock", lock(1, "BeastVim")) -- alive, not ours to signal
			vim.fn.writefile({ "not json" }, fx.lock_dir .. "/5.lock")

			assert(fx.review.start(), "server failed to start")
			fx.status = fx.review.status()
			fx.lock_path = fx.status.lock_path
			fx.lock = vim.json.decode(fx.read(fx.lock_path))

			---Connect and authenticate as Claude Code would.
			function fx.connect()
				return ws.open(fx.status.port, fx.lock.authToken)
			end

			function fx.request(c, method, params)
				fx.nextid = fx.nextid + 1
				ws.send(c, { jsonrpc = "2.0", id = fx.nextid, method = method, params = params })
				return fx.nextid
			end

			---Send a request and wait for its response; the id must match.
			function fx.call(c, method, params)
				local id = fx.request(c, method, params)
				local msg = ws.recv(c)
				assert(msg ~= nil and msg.id == id, "response id does not match request id (" .. method .. ")")
				return msg
			end

			---Replies may arrive in any order; collect `count` of them keyed by id.
			function fx.collect(c, count)
				local by_id = {}
				for _ = 1, count do
					local msg = ws.recv(c)
					if msg then
						by_id[msg.id] = msg
					end
				end
				return by_id
			end

			function fx.tool(c, name, args)
				return fx.call(c, "tools/call", { name = name, arguments = args })
			end

			function fx.tool_text(msg)
				return msg and msg.result and msg.result.content and msg.result.content[1].text
			end

			---Second content item of a reply (the final text for FILE_SAVED, the tab name for DIFF_REJECTED).
			function fx.tool_payload(msg)
				return msg and msg.result and msg.result.content and msg.result.content[2] and msg.result.content[2].text
			end

			---Start an openDiff on `fx.c`-like client `c` and return the request id.
			function fx.open_diff(c, path, contents, tab)
				return fx.request(c, "tools/call", {
					name = "openDiff",
					arguments = {
						old_file_path = path,
						new_file_path = path,
						new_file_contents = contents,
						tab_name = tab or "tab",
					},
				})
			end

			function fx.buf_of(path)
				ws.wait(function()
					return session.get(vim.fn.bufnr(path)) ~= nil
				end)
				return vim.fn.bufnr(path)
			end

			function fx.marks(buf)
				return #vim.api.nvim_buf_get_extmarks(buf, fx.render.namespace, 0, -1, {})
			end
		end)
	end)

	t.after_each(function()
		n.exec_lua(function()
			pcall(function()
				if _G.fx.c then
					_G.fx.c:close()
				end
			end)
			pcall(_G.fx.review.stop)
			vim.fn.delete(_G.fx.root, "rf")
		end)
	end)

	t.describe("stale lock cleanup", function()
		---@param name string
		---@return boolean
		local function exists(name)
			return n.exec_lua(function(f)
				return _G.fx.exists(_G.fx.lock_dir .. "/" .. f)
			end, name)
		end

		t.it("removes a dead BeastVim lock", function()
			t.eq(false, exists("1.lock"))
		end)

		t.it("removes a dead labelled BeastVim lock", function()
			t.eq(false, exists("6.lock"))
		end)

		t.it("keeps another IDE's lock", function()
			t.eq(true, exists("2.lock"))
		end)

		t.it("keeps a live BeastVim lock", function()
			t.eq(true, exists("3.lock"))
		end)

		t.it("keeps the lock of a process it cannot signal", function()
			t.eq(true, exists("4.lock"))
		end)

		t.it("keeps an unparseable lock", function()
			t.eq(true, exists("5.lock"))
		end)
	end)

	t.describe("lock file", function()
		t.it("lives under CLAUDE_CONFIG_DIR/ide/<port>.lock", function()
			t.eq(
				true,
				n.exec_lua(function()
					local fx = _G.fx
					return fx.lock_path == ("%s/%d.lock"):format(fx.lock_dir, fx.status.port)
				end)
			)
		end)

		t.it("records the pid", function()
			t.eq(
				true,
				n.exec_lua(function()
					return _G.fx.lock.pid == _G.fx.uv.os_getpid()
				end)
			)
		end)

		t.it("carries start time and pid in ideName and shows the same name in status", function()
			t.eq(
				{ labelled = true, same = true },
				n.exec_lua(function()
					local fx = _G.fx
					local name = fx.lock.ideName
					return {
						labelled = name == ("BeastVim (%s, pid %d)"):format(name:match("(%d%d:%d%d:%d%d)") or "?", fx.uv.os_getpid()),
						same = fx.status.name == name,
					}
				end)
			)
		end)

		t.it("uses ws transport and the cwd as workspace folder", function()
			t.eq(
				{ transport = "ws", folders = true },
				n.exec_lua(function()
					local fx = _G.fx
					return {
						transport = fx.lock.transport,
						folders = vim.deep_equal(fx.lock.workspaceFolders, { vim.fn.getcwd() }),
					}
				end)
			)
		end)

		t.it("has a 32 char lowercase hex token", function()
			t.eq(
				true,
				n.exec_lua(function()
					local token = _G.fx.lock.authToken
					return token:match("^%x+$") ~= nil and #token == 32 and token == token:lower()
				end)
			)
		end)

		t.it("has file mode 0600 and leaves no temp file behind", function()
			t.eq(
				{ mode = tonumber("600", 8), tmp = false },
				n.exec_lua(function()
					local fx = _G.fx
					return {
						mode = require("bit").band(fx.uv.fs_stat(fx.lock_path).mode, tonumber("777", 8)),
						tmp = fx.exists(fx.lock_path .. ".tmp"),
					}
				end)
			)
		end)

		t.it("keeps one server when started twice", function()
			t.eq(
				true,
				n.exec_lua(function()
					local fx = _G.fx
					return fx.review.start() and fx.review.status().port == fx.status.port
				end)
			)
		end)
	end)

	t.describe("status lines", function()
		t.it("describe the instance", function()
			t.eq(
				{ name = true, port = true, not_connected = true, lock = true },
				n.exec_lua(function()
					local fx = _G.fx
					local text = table.concat(fx.review.status_lines(), "\n")
					return {
						name = text:find("Listed in /ide as: " .. fx.lock.ideName, 1, true) ~= nil,
						port = text:find("127.0.0.1:" .. fx.status.port, 1, true) ~= nil,
						not_connected = text:find("Claude Code: not connected", 1, true) ~= nil,
						lock = text:find(fx.lock_path, 1, true) ~= nil,
					}
				end)
			)
		end)
	end)

	t.describe("authentication", function()
		t.it("refuses a wrong token and never counts the peer as a client", function()
			t.eq(
				{ refused = true, clients = 0 },
				n.exec_lua(function()
					local fx = _G.fx
					local c = fx.ws.connect(fx.status.port)
					c:write(fx.ws.upgrade_request("0000"))
					fx.ws.wait(function()
						return c.closed
					end)
					local out = { refused = c.data:find("401", 1, true) ~= nil, clients = fx.review.status().clients }
					c:close()
					return out
				end)
			)
		end)
	end)

	t.describe("with a connected client", function()
		t.before_each(function()
			n.exec_lua(function()
				local fx = _G.fx
				fx.c = fx.connect()
				fx.ws.wait(function()
					return fx.review.status().clients == 1
				end)
			end)
		end)

		t.describe("MCP handshake", function()
			t.it("counts the client", function()
				t.eq(
					1,
					n.exec_lua(function()
						return _G.fx.review.status().clients
					end)
				)
			end)

			t.it("initializes with the protocol version, tools and an object logging capability", function()
				t.eq(
					{ version = "2024-11-05", tools = true, logging = "{}" },
					n.exec_lua(function()
						local fx = _G.fx
						local init = fx.call(fx.c, "initialize", {
							protocolVersion = "2024-11-05",
							capabilities = {},
							clientInfo = { name = "claude-code", version = "x" },
						})
						return {
							version = init.result.protocolVersion,
							tools = init.result.capabilities.tools ~= nil,
							logging = vim.json.encode(init.result.capabilities.logging),
						}
					end)
				)
			end)

			t.it("sends no response to a notification", function()
				t.eq(
					true,
					n.exec_lua(function()
						local fx = _G.fx
						fx.ws.send(fx.c, { jsonrpc = "2.0", method = "notifications/initialized" })
						local list = fx.call(fx.c, "tools/list", {})
						return list.result ~= nil
					end)
				)
			end)

			t.it("advertises its tools and hides close_tab", function()
				t.eq(
					{
						openDiff = true,
						closeAllDiffTabs = true,
						getOpenEditors = true,
						getWorkspaceFolders = true,
						openFile = true,
						hidden = false,
					},
					n.exec_lua(function()
						local fx = _G.fx
						local list = fx.call(fx.c, "tools/list", {})
						local names = vim.tbl_map(function(tl)
							return tl.name
						end, list.result.tools)
						local out = {}
						for _, name in ipairs({ "openDiff", "closeAllDiffTabs", "getOpenEditors", "getWorkspaceFolders", "openFile" }) do
							out[name] = vim.tbl_contains(names, name)
						end
						out.hidden = vim.tbl_contains(names, "close_tab")
						return out
					end)
				)
			end)

			t.it("gives every tool a description and schema", function()
				t.eq(
					{},
					n.exec_lua(function()
						local fx = _G.fx
						local bad = {}
						for _, tl in ipairs(fx.call(fx.c, "tools/list", {}).result.tools) do
							if tl.description == nil or tl.inputSchema == nil then
								bad[#bad + 1] = tl.name
							end
						end
						return bad
					end)
				)
			end)

			t.it("lists no prompts", function()
				t.eq(
					{},
					n.exec_lua(function()
						local fx = _G.fx
						return fx.call(fx.c, "prompts/list", {}).result.prompts
					end)
				)
			end)
		end)

		t.describe("JSON-RPC errors", function()
			t.it("rejects an unknown method and an unknown tool with -32601", function()
				t.eq(
					{ -32601, -32601 },
					n.exec_lua(function()
						local fx = _G.fx
						return { fx.call(fx.c, "no/such", {}).error.code, fx.tool(fx.c, "nope", {}).error.code }
					end)
				)
			end)

			t.it("answers garbage with a parse error and a null id", function()
				t.eq(
					{ code = -32700, null_id = true },
					n.exec_lua(function()
						local fx = _G.fx
						fx.c:write(fx.ws.client_frame(1, "{not json"))
						local bad = fx.ws.recv(fx.c)
						return { code = bad.error.code, null_id = bad.id == vim.NIL }
					end)
				)
			end)

			t.it("answers a wrong jsonrpc version with invalid request", function()
				t.eq(
					-32600,
					n.exec_lua(function()
						local fx = _G.fx
						fx.ws.send(fx.c, { jsonrpc = "1.0", id = 99, method = "initialize" })
						return fx.ws.recv(fx.c).error.code
					end)
				)
			end)

			t.it("answers a batch array with invalid request", function()
				t.eq(
					-32600,
					n.exec_lua(function()
						local fx = _G.fx
						fx.c:write(fx.ws.client_frame(1, "[]"))
						return fx.ws.recv(fx.c).error.code
					end)
				)
			end)

			t.it("answers openDiff without params with -32602", function()
				t.eq(
					-32602,
					n.exec_lua(function()
						local fx = _G.fx
						return fx.tool(fx.c, "openDiff", {}).error.code
					end)
				)
			end)
		end)

		t.describe("openDiff: hostile paths", function()
			---@param args table
			local function code(args)
				return n.exec_lua(function(a)
					local fx = _G.fx
					if a.new_file_path == "<work>" then
						a.new_file_path = fx.work
					end
					return fx.tool(fx.c, "openDiff", a).error.code
				end, args)
			end

			t.it("rejects an empty path", function()
				t.eq(-32602, code({ new_file_path = "", new_file_contents = "x" }))
			end)

			t.it("rejects a directory path", function()
				t.eq(-32602, code({ new_file_path = "<work>", new_file_contents = "x" }))
			end)

			t.it("rejects the root directory", function()
				t.eq(-32602, code({ new_file_path = "/", new_file_contents = "x" }))
			end)

			t.it("rejects wrong types", function()
				t.eq(-32602, code({ new_file_path = 1, new_file_contents = {} }))
			end)
		end)

		t.describe("simple tools", function()
			t.it("reports the cwd as workspace folder", function()
				t.eq(
					true,
					n.exec_lua(function()
						local fx = _G.fx
						local folders = vim.json.decode(fx.tool_text(fx.tool(fx.c, "getWorkspaceFolders", {})))
						return folders.rootPath == vim.fn.getcwd()
					end)
				)
			end)

			t.it("opens a file", function()
				t.eq(
					{ reply = true, opened = true },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("x\n")
						local opened = fx.tool(fx.c, "openFile", { filePath = path })
						return {
							reply = fx.tool_text(opened) == "Opened file: " .. path,
							opened = vim.api.nvim_buf_get_name(0) == (vim.fn.resolve(path) == path and path or vim.api.nvim_buf_get_name(0)),
						}
					end)
				)
			end)

			t.it("lists the open file in getOpenEditors", function()
				t.eq(
					true,
					n.exec_lua(function()
						local fx = _G.fx
						fx.tool(fx.c, "openFile", { filePath = fx.make_file("x\n") })
						local editors = vim.json.decode(fx.tool_text(fx.tool(fx.c, "getOpenEditors", {})))
						return vim.iter(editors.tabs):any(function(tl)
							return tl.uri == "file://" .. vim.api.nvim_buf_get_name(0)
						end)
					end)
				)
			end)
		end)

		t.describe("openDiff", function()
			t.it("accept: opens a session, holds the reply and leaves disk alone while pending", function()
				t.eq(
					{ session = true, no_reply = true, disk = "a\nb\n" },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\nb\n")
						fx.open_diff(fx.c, path, "a\nX\n")
						local buf = fx.buf_of(path)
						return {
							session = fx.session.get(buf) ~= nil,
							no_reply = fx.ws.next_message(fx.c) == nil,
							disk = fx.read(path),
						}
					end)
				)
			end)

			t.it("accept: replies FILE_SAVED with the final text and does not write the file", function()
				-- Claude Code writes the file from that reply. If we wrote it first, its
				-- own write would fail with "file changed since read".
				t.eq(
					{
						id = true,
						text = "FILE_SAVED",
						payload = "a\nX\n",
						disk = "a\nb\n",
						buffer = { "a", "X" },
						modified = false,
					},
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\nb\n")
						local id = fx.open_diff(fx.c, path, "a\nX\n")
						local buf = fx.buf_of(path)
						fx.session.get(buf):decide_all(true)
						local msg = fx.ws.recv(fx.c)
						return {
							id = msg.id == id,
							text = fx.tool_text(msg),
							payload = fx.tool_payload(msg),
							disk = fx.read(path),
							buffer = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
							modified = vim.bo[buf].modified,
						}
					end)
				)
			end)

			t.it("reject: replies DIFF_REJECTED echoing the tab name and leaves the file", function()
				t.eq(
					{ id = true, text = "DIFF_REJECTED", payload = "tab", disk = "a\nb\n" },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\nb\n")
						local id = fx.open_diff(fx.c, path, "a\nX\n")
						local buf = fx.buf_of(path)
						fx.session.get(buf):decide_all(false)
						local msg = fx.ws.recv(fx.c)
						return {
							id = msg.id == id,
							text = fx.tool_text(msg),
							payload = fx.tool_payload(msg),
							disk = fx.read(path),
						}
					end)
				)
			end)

			t.it("no changes: replies immediately with the unchanged proposal", function()
				t.eq(
					{ id = true, text = "FILE_SAVED", payload = "a\nb\n" },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\nb\n")
						local id = fx.open_diff(fx.c, path, "a\nb\n")
						local msg = fx.ws.recv(fx.c)
						return { id = msg.id == id, text = fx.tool_text(msg), payload = fx.tool_payload(msg) }
					end)
				)
			end)

			t.it("new file: replies with the new text and does not create the file", function()
				t.eq(
					{ text = "FILE_SAVED", payload = "hello\n", created = false },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.work .. "/deep/new.txt"
						fx.open_diff(fx.c, path, "hello\n")
						local buf = fx.buf_of(path)
						fx.session.get(buf):decide_all(true)
						local reply = fx.ws.recv(fx.c)
						return {
							text = fx.tool_text(reply),
							payload = fx.tool_payload(reply),
							created = fx.read(path) ~= nil,
						}
					end)
				)
			end)

			t.it("partial accept: Claude gets exactly what was kept", function()
				t.eq(
					{
						text = "FILE_SAVED",
						payload = "1\nA\n3\n4\n5\n6\n7\n",
						disk = "1\n2\n3\n4\n5\n6\n7\n",
					},
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("1\n2\n3\n4\n5\n6\n7\n")
						fx.open_diff(fx.c, path, "1\nA\n3\n4\n5\nB\n7\n")
						local buf = fx.buf_of(path)
						vim.api.nvim_buf_call(buf, fx.review.accept) -- hunk 1: 2 -> A
						vim.api.nvim_buf_call(buf, fx.review.reject) -- hunk 2: 6 -> B
						local reply = fx.ws.recv(fx.c)
						return {
							text = fx.tool_text(reply),
							payload = fx.tool_payload(reply),
							disk = fx.read(path),
						}
					end)
				)
			end)

			-- No trailing newline stays absent; CRLF stays CRLF.
			for name, case in pairs({
				["preserves a missing trailing newline"] = { old = "a\nb", new = "a\nX" },
				["preserves CRLF"] = { old = "a\r\nb\r\n", new = "a\r\nX\r\n" },
				["can empty a file"] = { old = "a\n", new = "" },
			}) do
				t.it("text fidelity: " .. name, function()
					t.eq(
						case.new,
						n.exec_lua(function(c)
							local fx = _G.fx
							local path = fx.make_file(c.old)
							fx.open_diff(fx.c, path, c.new)
							fx.session.get(fx.buf_of(path)):decide_all(true)
							return fx.tool_payload(fx.ws.recv(fx.c))
						end, case)
					)
				end)
			end

			t.it("closeAllDiffTabs counts the pending review and answers it as rejected", function()
				t.eq(
					{ closed = "CLOSED_1_DIFF_TABS", pending = "DIFF_REJECTED", bands = 0, disk = "a\n" },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\n")
						local id = fx.open_diff(fx.c, path, "A\n", "my-tab")
						local buf = fx.buf_of(path)
						local close_id = fx.request(fx.c, "tools/call", { name = "closeAllDiffTabs", arguments = {} })
						local got = fx.collect(fx.c, 2)
						return {
							closed = fx.tool_text(got[close_id]),
							pending = fx.tool_text(got[id]),
							bands = fx.marks(buf),
							disk = fx.read(path),
						}
					end)
				)
			end)

			t.it("close_tab for another name leaves the review pending", function()
				t.eq(
					{ reply = "TAB_CLOSED", pending = true },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\n")
						fx.open_diff(fx.c, path, "A\n", "tab-two")
						fx.buf_of(path)
						return {
							reply = fx.tool_text(fx.tool(fx.c, "close_tab", { tab_name = "other" })),
							pending = fx.session.get(vim.fn.bufnr(path)) ~= nil,
						}
					end)
				)
			end)

			t.it("close_tab matching the name answers the review as rejected", function()
				t.eq(
					{ closed = "TAB_CLOSED", pending = "DIFF_REJECTED" },
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\n")
						local id = fx.open_diff(fx.c, path, "A\n", "tab-two")
						fx.buf_of(path)
						local match_id = fx.request(fx.c, "tools/call", { name = "close_tab", arguments = { tab_name = "tab-two" } })
						local got = fx.collect(fx.c, 2)
						return { closed = fx.tool_text(got[match_id]), pending = fx.tool_text(got[id]) }
					end)
				)
			end)
		end)

		t.describe("status", function()
			t.it("reports running, one client and the last message time", function()
				t.eq(
					{ running = true, clients = 1, recorded = true },
					n.exec_lua(function()
						local fx = _G.fx
						fx.call(fx.c, "prompts/list", {})
						local s = fx.review.status()
						return {
							running = s.running,
							clients = s.clients,
							recorded = s.last_message_ago_s ~= nil and s.last_message_ago_s >= 0,
						}
					end)
				)
			end)
		end)

		t.describe("disconnect mid-review", function()
			t.it("cancels the session and leaves buffer and file unchanged", function()
				t.eq(
					{
						pending = true,
						cancelled = true,
						bands = 0,
						buffer = { "a", "b" },
						disk = "a\nb\n",
						clients_back_to_zero = true,
					},
					n.exec_lua(function()
						local fx = _G.fx
						local path = fx.make_file("a\nb\n")
						fx.open_diff(fx.c, path, "A\nB\n")
						local buf = fx.buf_of(path)
						local out = { pending = fx.session.get(buf) ~= nil }
						fx.c:close()
						out.cancelled = fx.ws.wait(function()
							return fx.session.get(buf) == nil
						end)
						out.bands = fx.marks(buf)
						out.buffer = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
						out.disk = fx.read(path)
						out.clients_back_to_zero = fx.ws.wait(function()
							return fx.review.status().clients == 0
						end)
						return out
					end)
				)
			end)
		end)

		t.describe("two sessions", function()
			t.it("answers each client separately and survives the other's disconnect", function()
				t.eq(
					{
						second_answered = true,
						first_waiting = true,
						first_survives = true,
						first_answered = true,
					},
					n.exec_lua(function()
						local fx = _G.fx
						fx.c:close()
						fx.ws.wait(function()
							return fx.review.status().clients == 0
						end)
						local c1, c2 = fx.connect(), fx.connect()
						fx.c = c1
						fx.ws.wait(function()
							return fx.review.status().clients == 2
						end)
						local p1, p2 = fx.make_file("1\n"), fx.make_file("2\n")
						local id1 = fx.open_diff(c1, p1, "one\n")
						local id2 = fx.open_diff(c2, p2, "two\n")
						local b1, b2 = fx.buf_of(p1), fx.buf_of(p2)
						fx.session.get(b2):decide_all(true)
						local m2 = fx.ws.recv(c2)
						local out = {
							second_answered = m2.id == id2,
							first_waiting = fx.ws.next_message(c1) == nil,
						}
						c2:close()
						fx.ws.wait(function()
							return fx.review.status().clients == 1
						end)
						out.first_survives = fx.session.get(b1) ~= nil
						fx.session.get(b1):decide_all(true)
						out.first_answered = fx.ws.recv(c1).id == id1
						return out
					end)
				)
			end)
		end)
	end)

	t.describe("stop", function()
		t.it("removes its lock file, keeps unrelated ones and closes the port", function()
			t.eq(
				{ lock_removed = true, unrelated_kept = true, port_closed = true, running = false },
				n.exec_lua(function()
					local fx = _G.fx
					fx.review.stop()
					local late = fx.ws.connect(fx.status.port)
					local out = {
						lock_removed = not fx.exists(fx.lock_path),
						unrelated_kept = fx.exists(fx.lock_dir .. "/2.lock"),
						port_closed = late.err ~= nil,
						running = fx.review.status().running,
					}
					late:close()
					return out
				end)
			)
		end)

		t.it("is idempotent and restarts cleanly", function()
			t.eq(
				{ restarted = true, running = true },
				n.exec_lua(function()
					local fx = _G.fx
					fx.review.stop()
					fx.review.stop()
					local started = fx.review.start()
					return { restarted = started and true or false, running = fx.review.status().running }
				end)
			)
		end)

		-- An unusable lock directory fails cleanly: no throw, no leaked listener.
		t.it("start() fails cleanly when the lock dir is unusable", function()
			t.eq(
				{ no_throw = true, started = false, running = false },
				n.exec_lua(function()
					local fx = _G.fx
					fx.review.stop()
					vim.env.CLAUDE_CONFIG_DIR = "/dev/null/nope"
					local ok, started = pcall(fx.review.start)
					return { no_throw = ok, started = started, running = fx.review.status().running }
				end)
			)
		end)

		-- A directory this lib creates is private; the token file inside is 0600 regardless.
		t.it("creates a fresh lock directory with mode 0700", function()
			t.eq(
				{ started = true, mode = tonumber("700", 8) },
				n.exec_lua(function()
					local fx = _G.fx
					fx.review.stop()
					local fresh = fx.root .. "/fresh"
					vim.env.CLAUDE_CONFIG_DIR = fresh
					local started = fx.review.start()
					return {
						started = started and true or false,
						mode = require("bit").band(fx.uv.fs_stat(fresh .. "/ide").mode, tonumber("777", 8)),
					}
				end)
			)
		end)
	end)
end)
