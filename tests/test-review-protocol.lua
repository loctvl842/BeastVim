-- =========================================================================
-- Test: review MCP protocol (lock file, JSON-RPC, openDiff round trip)
-- =========================================================================
-- Run as: nvim --clean --headless -l tests/test-review-protocol.lua
-- Exit code: 0 = PASS, 1 = FAIL
-- =========================================================================

vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = "./lua/?.lua;./lua/?/init.lua;./tests/?.lua;" .. package.path

local ws = require("review_ws_client")
local wait = ws.wait

local uv = vim.uv or vim.loop

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

vim.notify = function() end

-- Isolate the discovery directory from the real ~/.claude.
local root = vim.fn.tempname()
local config_dir = root .. "/claude"
local work = root .. "/work"
vim.fn.mkdir(config_dir, "p")
vim.fn.mkdir(work, "p")
vim.env.CLAUDE_CONFIG_DIR = config_dir
local lock_dir = config_dir .. "/ide"

local render = require("beast.libs.review.render")
local review = require("beast.libs.review")
local session = require("beast.libs.review.session")

local counter = 0
local function make_file(content)
	counter = counter + 1
	local path = work .. "/f" .. counter .. ".txt"
	local f = assert(io.open(path, "wb"))
	f:write(content)
	f:close()
	return path
end

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function write_lock(name, data)
	vim.fn.mkdir(lock_dir, "p")
	local f = assert(io.open(lock_dir .. "/" .. name, "wb"))
	f:write(vim.json.encode(data))
	f:close()
end

local function exists(path)
	return uv.fs_stat(path) ~= nil
end

print("== stale lock cleanup ==")
do
	-- A pid that is certainly gone: a child that already exited.
	local job = vim.fn.jobstart({ "true" })
	local dead = vim.fn.jobpid(job)
	vim.fn.jobwait({ job }, 2000)

	write_lock("1.lock", { pid = dead, ideName = "Neovim", transport = "ws", authToken = "x", workspaceFolders = {} })
	write_lock("2.lock", { pid = dead, ideName = "VS Code", transport = "ws", authToken = "x", workspaceFolders = {} })
	write_lock("3.lock", { pid = uv.os_getpid(), ideName = "Neovim", transport = "ws", authToken = "x", workspaceFolders = {} })
	write_lock("4.lock", { pid = 1, ideName = "Neovim", transport = "ws", authToken = "x", workspaceFolders = {} }) -- alive, not ours to signal
	vim.fn.writefile({ "not json" }, lock_dir .. "/5.lock")
end

assert(review.start(), "server failed to start")
local status = review.status()
local lock_path = status.lock_path

print("== stale lock cleanup (result) ==")
do
	assert_test("dead Neovim lock removed", not exists(lock_dir .. "/1.lock"))
	assert_test("other IDE's lock kept", exists(lock_dir .. "/2.lock"))
	assert_test("live Neovim lock kept", exists(lock_dir .. "/3.lock"))
	assert_test("lock of a process we cannot signal kept", exists(lock_dir .. "/4.lock"))
	assert_test("unparseable lock kept", exists(lock_dir .. "/5.lock"))
end

print("== lock file ==")
local lock
do
	assert_eq("lives under CLAUDE_CONFIG_DIR/ide/<port>.lock", lock_path, ("%s/%d.lock"):format(lock_dir, status.port))
	lock = vim.json.decode(read(lock_path))
	assert_eq("pid", lock.pid, uv.os_getpid())
	assert_eq("ideName", lock.ideName, "Neovim")
	assert_eq("transport", lock.transport, "ws")
	assert_eq("workspaceFolders", lock.workspaceFolders, { vim.fn.getcwd() })
	assert_test(
		"token is 32 lowercase hex",
		lock.authToken:match("^%x+$") ~= nil and #lock.authToken == 32 and lock.authToken == lock.authToken:lower()
	)
	assert_eq("file mode 0600", bit.band(uv.fs_stat(lock_path).mode, tonumber("777", 8)), tonumber("600", 8))
	assert_test("no temp file left behind", not exists(lock_path .. ".tmp"))
	assert_test("starting twice keeps one server", review.start() and review.status().port == status.port)
end

--- Connect and authenticate as Claude Code would.
local function connect()
	return ws.open(status.port, lock.authToken)
end

local nextid = 0
local function request(c, method, params)
	nextid = nextid + 1
	ws.send(c, { jsonrpc = "2.0", id = nextid, method = method, params = params })
	return nextid
end

--- Send a request and wait for its response.
local function call(c, method, params)
	local id = request(c, method, params)
	local msg = ws.recv(c)
	assert_test("response id matches request id (" .. method .. ")", msg ~= nil and msg.id == id)
	return msg
end

--- Replies may arrive in any order; collect `n` of them keyed by id.
local function collect(c, n)
	local by_id = {}
	for _ = 1, n do
		local msg = ws.recv(c)
		if msg then
			by_id[msg.id] = msg
		end
	end
	return by_id
end

local function tool(c, name, args)
	return call(c, "tools/call", { name = name, arguments = args })
end

local function tool_text(msg)
	return msg and msg.result and msg.result.content and msg.result.content[1].text
end

print("== authentication ==")
do
	local c = ws.connect(status.port)
	c:write(ws.upgrade_request("0000"))
	wait(function()
		return c.closed
	end)
	assert_test("wrong token refused", c.data:find("401", 1, true) ~= nil)
	c:close()
	assert_eq("refused peer never counted as a client", review.status().clients, 0)
end

local c = connect()
wait(function()
	return review.status().clients == 1
end)

print("== MCP handshake ==")
do
	assert_eq("client counted", review.status().clients, 1)
	local init = call(c, "initialize", { protocolVersion = "2024-11-05", capabilities = {}, clientInfo = { name = "claude-code", version = "x" } })
	assert_eq("protocol version", init.result.protocolVersion, "2024-11-05")
	assert_test("advertises tools", init.result.capabilities.tools ~= nil)
	assert_eq("logging capability is an object", vim.json.encode(init.result.capabilities.logging), "{}")

	ws.send(c, { jsonrpc = "2.0", method = "notifications/initialized" })
	local list = call(c, "tools/list", {})
	assert_test("notification got no response (next message was tools/list)", list.result ~= nil)
	local names = vim.tbl_map(function(t)
		return t.name
	end, list.result.tools)
	for _, n in ipairs({ "openDiff", "closeAllDiffTabs", "getOpenEditors", "getWorkspaceFolders", "openFile" }) do
		assert_test("advertises " .. n, vim.tbl_contains(names, n))
	end
	assert_test("hidden tool not advertised", not vim.tbl_contains(names, "close_tab"))
	for _, t in ipairs(list.result.tools) do
		assert_test(t.name .. " has description and schema", t.description ~= nil and t.inputSchema ~= nil)
	end
	assert_eq("prompts/list is empty", call(c, "prompts/list", {}).result.prompts, {})
end

print("== JSON-RPC errors ==")
do
	assert_eq("unknown method", call(c, "no/such", {}).error.code, -32601)
	assert_eq("unknown tool", tool(c, "nope", {}).error.code, -32601)

	c:write(ws.client_frame(1, "{not json"))
	local bad = ws.recv(c)
	assert_eq("garbage -> parse error", bad.error.code, -32700)
	assert_eq("parse error id is null", bad.id, vim.NIL)

	ws.send(c, { jsonrpc = "1.0", id = 99, method = "initialize" })
	assert_eq("wrong jsonrpc version -> invalid request", ws.recv(c).error.code, -32600)

	c:write(ws.client_frame(1, "[]"))
	assert_eq("batch/array -> invalid request", ws.recv(c).error.code, -32600)

	assert_eq("openDiff without params", tool(c, "openDiff", {}).error.code, -32602)
end

print("== openDiff: hostile paths ==")
do
	assert_eq("empty path", tool(c, "openDiff", { new_file_path = "", new_file_contents = "x" }).error.code, -32602)
	assert_eq("directory path", tool(c, "openDiff", { new_file_path = work, new_file_contents = "x" }).error.code, -32602)
	assert_eq("root directory", tool(c, "openDiff", { new_file_path = "/", new_file_contents = "x" }).error.code, -32602)
	assert_eq("wrong types", tool(c, "openDiff", { new_file_path = 1, new_file_contents = {} }).error.code, -32602)
end

print("== simple tools ==")
do
	local folders = vim.json.decode(tool_text(tool(c, "getWorkspaceFolders", {})))
	assert_eq("workspace folder is cwd", folders.rootPath, vim.fn.getcwd())

	local path = make_file("x\n")
	local opened = tool(c, "openFile", { filePath = path })
	assert_eq("openFile reply", tool_text(opened), "Opened file: " .. path)
	assert_eq("openFile opened it", vim.api.nvim_buf_get_name(0), vim.fn.resolve(path) == path and path or vim.api.nvim_buf_get_name(0))

	local editors = vim.json.decode(tool_text(tool(c, "getOpenEditors", {})))
	assert_test(
		"getOpenEditors lists the file",
		vim.iter(editors.tabs):any(function(t)
			return t.uri == "file://" .. vim.api.nvim_buf_get_name(0)
		end)
	)
end

--- Start an openDiff and return the request id and buffer.
local function open_diff(path, contents, tab)
	local id = request(c, "tools/call", {
		name = "openDiff",
		arguments = { old_file_path = path, new_file_path = path, new_file_contents = contents, tab_name = tab or "tab" },
	})
	return id
end

local function buf_of(path)
	local b = vim.fn.bufnr(path)
	wait(function()
		return session.get(vim.fn.bufnr(path)) ~= nil
	end)
	return vim.fn.bufnr(path)
end

print("== openDiff: accept ==")
do
	local path = make_file("a\nb\n")
	local id = open_diff(path, "a\nX\n")
	local buf = buf_of(path)
	assert_test("review session opened", session.get(buf) ~= nil)
	assert_eq("no reply while the user is deciding", ws.next_message(c), nil)
	assert_eq("disk untouched while pending", read(path), "a\nb\n")
	session.get(buf):decide_all(true)
	local msg = ws.recv(c)
	assert_eq("reply id", msg.id, id)
	assert_eq("FILE_SAVED", tool_text(msg), "FILE_SAVED")
	assert_eq("file has the proposal", read(path), "a\nX\n")
end

print("== openDiff: reject ==")
do
	local path = make_file("a\nb\n")
	local id = open_diff(path, "a\nX\n")
	local buf = buf_of(path)
	session.get(buf):decide_all(false)
	local msg = ws.recv(c)
	assert_eq("reply id", msg.id, id)
	assert_eq("DIFF_REJECTED", tool_text(msg), "DIFF_REJECTED")
	assert_eq("file unchanged", read(path), "a\nb\n")
end

print("== openDiff: no changes ==")
do
	local path = make_file("a\nb\n")
	local id = open_diff(path, "a\nb\n")
	local msg = ws.recv(c)
	assert_eq("immediate reply", msg.id, id)
	assert_eq("FILE_SAVED", tool_text(msg), "FILE_SAVED")
end

print("== openDiff: new file ==")
do
	local path = work .. "/deep/new.txt"
	open_diff(path, "hello\n")
	local buf = buf_of(path)
	session.get(buf):decide_all(true)
	assert_eq("FILE_SAVED", tool_text(ws.recv(c)), "FILE_SAVED")
	assert_eq("created with parents", read(path), "hello\n")
end

print("== openDiff: closeAllDiffTabs / close_tab ==")
do
	local path = make_file("a\n")
	local id = open_diff(path, "A\n", "my-tab")
	local buf = buf_of(path)
	local close_id = request(c, "tools/call", { name = "closeAllDiffTabs", arguments = {} })
	local got = collect(c, 2)
	assert_eq("closeAllDiffTabs counts the pending review", tool_text(got[close_id]), "CLOSED_1_DIFF_TABS")
	assert_eq("pending openDiff answered as rejected", tool_text(got[id]), "DIFF_REJECTED")
	assert_eq("bands gone", #vim.api.nvim_buf_get_extmarks(buf, render.namespace, 0, -1, {}), 0)
	assert_eq("file unchanged", read(path), "a\n")

	local path2 = make_file("a\n")
	local id2 = open_diff(path2, "A\n", "tab-two")
	buf_of(path2)
	assert_eq("close_tab for another name", tool_text(tool(c, "close_tab", { tab_name = "other" })), "TAB_CLOSED")
	assert_test("other tab name leaves it pending", session.get(vim.fn.bufnr(path2)) ~= nil)
	local match_id = request(c, "tools/call", { name = "close_tab", arguments = { tab_name = "tab-two" } })
	got = collect(c, 2)
	assert_eq("close_tab matching", tool_text(got[match_id]), "TAB_CLOSED")
	assert_eq("closed review answered as rejected", tool_text(got[id2]), "DIFF_REJECTED")
end

print("== status ==")
do
	local s = review.status()
	assert_eq("running", s.running, true)
	assert_eq("one client", s.clients, 1)
	assert_test("last message recorded", s.last_message_ago_s ~= nil and s.last_message_ago_s >= 0)
end

print("== disconnect mid-review ==")
do
	local path = make_file("a\nb\n")
	open_diff(path, "A\nB\n")
	local buf = buf_of(path)
	assert_test("review pending", session.get(buf) ~= nil)
	c:close()
	assert_eq(
		"session cancelled on disconnect",
		wait(function()
			return session.get(buf) == nil
		end),
		true
	)
	assert_eq("bands gone", #vim.api.nvim_buf_get_extmarks(buf, render.namespace, 0, -1, {}), 0)
	assert_eq("buffer unchanged", vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "a", "b" })
	assert_eq("file unchanged", read(path), "a\nb\n")
	assert_eq(
		"client count back to 0",
		wait(function()
			return review.status().clients == 0
		end),
		true
	)
end

print("== two sessions ==")
do
	local c1, c2 = connect(), connect()
	wait(function()
		return review.status().clients == 2
	end)
	local p1, p2 = make_file("1\n"), make_file("2\n")
	c = c1
	local id1 = open_diff(p1, "one\n")
	c = c2
	local id2 = open_diff(p2, "two\n")
	local b1, b2 = buf_of(p1), buf_of(p2)
	session.get(b2):decide_all(true)
	local m2 = ws.recv(c2)
	assert_eq("second client answered", m2.id, id2)
	assert_eq("first client still waiting", ws.next_message(c1), nil)
	c2:close()
	wait(function()
		return review.status().clients == 1
	end)
	assert_test("other client's review survives a disconnect", session.get(b1) ~= nil)
	session.get(b1):decide_all(true)
	assert_eq("first client answered", ws.recv(c1).id, id1)
	c1:close()
end

print("== stop ==")
do
	review.stop()
	assert_test("lock file removed", not exists(lock_path))
	assert_test("unrelated lock files untouched", exists(lock_dir .. "/2.lock"))
	local late = ws.connect(status.port)
	assert_test("port closed", late.err ~= nil)
	late:close()
	assert_eq("status stopped", review.status().running, false)
	review.stop() -- idempotent
	assert_test("restart works", review.start() and review.status().running)
	review.stop()

	-- An unusable lock directory fails cleanly: no throw, no leaked listener.
	vim.env.CLAUDE_CONFIG_DIR = "/dev/null/nope"
	local ok, started = pcall(review.start)
	assert_test("start() does not throw when the lock dir is unusable", ok)
	assert_eq("and reports failure", started, false)
	assert_eq("and is not running", review.status().running, false)

	-- A directory this lib creates is private; the token file inside is 0600 regardless.
	local fresh = root .. "/fresh"
	vim.env.CLAUDE_CONFIG_DIR = fresh
	assert_test("fresh start", review.start())
	assert_eq("created directory mode 0700", bit.band(uv.fs_stat(fresh .. "/ide").mode, tonumber("777", 8)), tonumber("700", 8))
	review.stop()
end

print(string.format("\n%d passed, %d failed", passed, failed))
vim.fn.delete(root, "rf")
os.exit(failed == 0 and 0 or 1)
