local config = require("beast.libs.review.config")
local notify = require("beast.libs.review.notify")
local session = require("beast.libs.review.session")

local uv = vim.uv or vim.loop

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "review", description = "Review proposed file changes inline, hunk by hunk." }

---@class Beast.Review.Host
---@field listener Beast.Review.Listener
---@field lock_path string
---@field name string               what `/ide` lists this instance as
---@field clients integer           open WebSocket sessions
---@field last_message_ns? integer  hrtime of the newest inbound message
---@field last_refused? { reason: string, at_ns: integer }  newest failed handshake

---@type Beast.Review.Host?
local host

--- Propose `contents` as the new text of `path`. The file opens in a window
--- (or is created), the change shows as Current vs Incoming hunks, and
--- `on_done` fires once every hunk is decided. Nothing is written until at
--- least one hunk is accepted.
---@param path string
---@param contents string
---@param on_done? fun(outcome: Beast.Review.Outcome, stats: Beast.Review.Stats)
---@param opts? { write?: boolean }  write = false: leave the file to the caller (Claude Code writes it itself)
---@return fun() cancel  abandon this proposal without writing anything
function M.propose(path, contents, on_done, opts)
	local buf = vim.fn.bufadd(vim.fn.fnamemodify(path, ":p"))
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = true
	return session.submit(buf, contents, on_done or function() end, opts)
end

--- Listen for Claude Code on loopback and advertise ourselves in its
--- discovery directory. Returns false (after notifying) when it cannot.
---@return boolean ok
function M.start()
	if host then
		return true
	end
	local server = require("beast.libs.review.server")
	local lockfile = require("beast.libs.review.server.lockfile")
	local jsonrpc = require("beast.libs.review.server.jsonrpc")
	local handlers = require("beast.libs.review.server.mcp").handlers

	local token, terr = lockfile.token()
	if not token then
		notify("cannot start: " .. terr, vim.log.levels.ERROR)
		return false
	end

	lockfile.cleanup_stale()

	---@type Beast.Review.Host
	local h = { clients = 0 }
	local listener, err = server.start({
		token = token,
		on_open = function()
			h.clients = h.clients + 1
		end,
		on_message = function(client, text)
			h.last_message_ns = uv.hrtime()
			jsonrpc.handle(client, text, handlers)
		end,
		on_close = function(client)
			h.clients = h.clients - 1
			jsonrpc.client_closed(client)
		end,
		on_reject = function(reason)
			h.last_refused = { reason = reason, at_ns = uv.hrtime() }
		end,
	})
	if not listener then
		notify("cannot start: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end

	local name = lockfile.name()
	local path, lerr = lockfile.write(listener.port, token, { vim.fn.getcwd() }, name)
	if not path then
		listener:close()
		notify("cannot write lock file: " .. tostring(lerr), vim.log.levels.ERROR)
		return false
	end

	h.listener, h.lock_path, h.name = listener, path, name
	host = h
	return true
end

function M.stop()
	if not host then
		return
	end
	local h = host
	host = nil
	require("beast.libs.review.server.lockfile").remove(h.lock_path)
	h.listener:close()
end

---@class Beast.Review.Status
---@field running boolean
---@field name? string
---@field port? integer
---@field clients integer
---@field last_message_ago_s? number
---@field last_refused? { reason: string, ago_s: number }
---@field lock_path? string

---@return Beast.Review.Status
function M.status()
	if not host then
		return { running = false, clients = 0 }
	end
	return {
		running = true,
		name = host.name,
		port = host.listener.port,
		clients = host.clients,
		last_message_ago_s = host.last_message_ns and (uv.hrtime() - host.last_message_ns) / 1e9 or nil,
		last_refused = host.last_refused and {
			reason = host.last_refused.reason,
			ago_s = (uv.hrtime() - host.last_refused.at_ns) / 1e9,
		} or nil,
		lock_path = host.lock_path,
	}
end

---@return string[]
function M.status_lines()
	local s = M.status()
	if not s.running then
		return { "Review: stopped" }
	end
	local last = s.last_message_ago_s and ("%.0fs ago"):format(s.last_message_ago_s) or "never"
	local sessions = ("connected (%d session%s)"):format(s.clients, s.clients == 1 and "" or "s")
	local lines = {
		("Review: running on 127.0.0.1:%d"):format(s.port),
		("Listed in /ide as: %s"):format(s.name),
		("Claude Code: %s"):format(s.clients > 0 and sessions or "not connected"),
		("Last message: %s"):format(last),
	}
	if s.last_refused then
		lines[#lines + 1] = ("Last refused connection: %s (%.0fs ago)"):format(s.last_refused.reason, s.last_refused.ago_s)
	end
	lines[#lines + 1] = ("Lock file: %s"):format(s.lock_path)
	return lines
end

--- Multi-line query output belongs on the command line: a toast is one
--- truncated row, which would cut off the instance name.
local function show_status()
	local lines, chunks = M.status_lines(), {}
	for i, line in ipairs(lines) do
		chunks[i] = { line .. (i < #lines and "\n" or "") }
	end
	vim.api.nvim_echo(chunks, true, {})
end

local subcommands = {
	start = function()
		if M.start() then
			show_status()
		end
	end,
	stop = function()
		M.stop()
		notify("Review: stopped")
	end,
	status = function()
		show_status()
	end,
	-- Manual driver: treat a local file as the proposal for the current buffer.
	propose = function(arg)
		if not arg then
			return notify("usage: :Review propose <file with proposed contents>", vim.log.levels.ERROR)
		end
		local f, err = io.open(vim.fn.expand(arg), "rb")
		if not f then
			return notify(err, vim.log.levels.ERROR)
		end
		local text = f:read("*a")
		f:close()
		M.propose(vim.api.nvim_buf_get_name(0), text)
	end,
}

--- The review pending on the current buffer, if any. Review keys are global
--- (registered through packer.lazy so they show up in the key lib), so each
--- action says so when there is nothing to act on.
---@return Beast.Review.Session?
local function pending()
	local s = session.get(vim.api.nvim_get_current_buf())
	if not s then
		notify("no review pending in this buffer")
	end
	return s
end

--- Accept the hunk under the cursor.
function M.accept()
	local s = pending()
	if s then
		s:decide_nearest(true)
	end
end

--- Reject the hunk under the cursor.
function M.reject()
	local s = pending()
	if s then
		s:decide_nearest(false)
	end
end

function M.accept_all()
	local s = pending()
	if s then
		s:decide_all(true)
	end
end

function M.reject_all()
	local s = pending()
	if s then
		s:decide_all(false)
	end
end

--- Jump to the next pending hunk.
function M.next_hunk()
	local s = pending()
	if s then
		s:step(1)
	end
end

--- Jump to the previous pending hunk.
function M.prev_hunk()
	local s = pending()
	if s then
		s:step(-1)
	end
end

---@param opts? Beast.Review.Config
function M.setup(opts)
	require("beast").apply_highlights("beast.libs.review.highlights")
	config.setup(opts)

	vim.api.nvim_create_user_command("Review", function(o)
		local run = subcommands[o.fargs[1]]
		if not run then
			return notify("usage: :Review start|stop|status|propose <file>", vim.log.levels.ERROR)
		end
		run(o.fargs[2])
	end, {
		nargs = "+",
		complete = function(_, line)
			if line:match("^%S+%s+propose%s") then
				return vim.fn.getcompletion(line:match("propose%s+(.*)$") or "", "file")
			end
			return vim.tbl_keys(subcommands)
		end,
		desc = "Review proposed file changes",
	})

	-- Always remove our discovery file, even on :qa!.
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("beast_review_host", { clear = true }),
		callback = M.stop,
	})

	if config.enabled then
		M.start()
	end
end

return M
