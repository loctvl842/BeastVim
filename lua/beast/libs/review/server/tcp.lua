-- Loopback TCP listener and per-connection WebSocket state machine.
--
-- libuv callbacks run outside the main loop, where most of the Neovim API is
-- off limits, so every user-facing callback is wrapped in vim.schedule.

local frame = require("beast.libs.review.server.frame")
local handshake = require("beast.libs.review.server.handshake")

local uv = vim.uv or vim.loop

local M = {}

local OP, CLOSE = frame.OP, frame.CLOSE

---@class Beast.Review.Client
---@field handle uv.uv_tcp_t
---@field buf string
---@field state "handshake"|"open"|"closing"|"closed"  closing: final frame queued, input ignored
---@field opened boolean  completed the handshake (on_close only fires for these)
---@field fragments? string[]
---@field fragment_bytes integer
---@field timer? uv.uv_timer_t
---@field teardown fun()
---@field write_and_close fun(data: string)
---@field send fun(self: Beast.Review.Client, text: string)
---@field close fun(self: Beast.Review.Client, code?: integer)

---@class Beast.Review.ListenOpts
---@field token string
---@field max_payload integer
---@field handshake_timeout_ms integer
---@field on_open fun(client: Beast.Review.Client)
---@field on_message fun(client: Beast.Review.Client, text: string)
---@field on_close fun(client: Beast.Review.Client)

---@class Beast.Review.Listener
---@field port integer
---@field clients table<Beast.Review.Client, true>  every live connection, handshake included
---@field close fun(self: Beast.Review.Listener)

---@param opts Beast.Review.ListenOpts
---@param handle uv.uv_tcp_t
---@param clients table<Beast.Review.Client, true>  live connections; teardown removes its own entry
---@return Beast.Review.Client
local function new_client(opts, handle, clients)
	---@type Beast.Review.Client
	local client = { handle = handle, buf = "", state = "handshake", opened = false, fragment_bytes = 0 }

	local function teardown()
		if client.state == "closed" then
			return
		end
		client.state = "closed"
		clients[client] = nil
		if client.timer then
			client.timer:stop()
			client.timer:close()
			client.timer = nil
		end
		if not handle:is_closing() then
			handle:close()
		end
		if client.opened then
			vim.schedule(function()
				opts.on_close(client)
			end)
		end
	end

	--- Write then close, so the peer sees our final frame / response.
	--- Close is terminal: nothing more is read or delivered after this.
	local function write_and_close(data)
		if client.state == "closing" or client.state == "closed" or handle:is_closing() then
			return
		end
		client.state = "closing"
		handle:read_stop()
		handle:write(data, teardown)
	end

	function client:send(text)
		if self.state ~= "open" or handle:is_closing() then
			return
		end
		handle:write(frame.encode(OP.TEXT, text))
	end

	function client:close(code)
		if self.state == "open" then
			write_and_close(frame.encode(OP.CLOSE, frame.close_payload(code or CLOSE.NORMAL)))
		else
			teardown()
		end
	end

	client.teardown = teardown
	client.write_and_close = write_and_close
	return client
end

--- Consume buffered bytes while in the open state.
---@param opts Beast.Review.ListenOpts
---@param client Beast.Review.Client
local function pump(opts, client)
	while client.state == "open" do
		local f, consumed = frame.decode(client.buf, opts.max_payload)
		if not f then
			if consumed ~= 0 then
				client:close(consumed --[[@as integer]])
			end
			return
		end
		client.buf = client.buf:sub(consumed --[[@as integer]] + 1)

		if f.opcode == OP.CLOSE then
			client:close(CLOSE.NORMAL)
		elseif f.opcode == OP.PING then
			client.handle:write(frame.encode(OP.PONG, f.payload))
		elseif f.opcode == OP.PONG then
			-- ignored: we never ping
		elseif f.opcode == OP.TEXT or f.opcode == OP.CONT then
			if (f.opcode == OP.TEXT) == (client.fragments ~= nil) then
				return client:close(CLOSE.PROTOCOL) -- TEXT mid-message, or CONT with nothing to continue
			end
			client.fragments = client.fragments or {}
			client.fragment_bytes = client.fragment_bytes + #f.payload
			if client.fragment_bytes > opts.max_payload then
				return client:close(CLOSE.TOO_BIG)
			end
			table.insert(client.fragments, f.payload)
			if f.fin then
				local text = table.concat(client.fragments)
				client.fragments, client.fragment_bytes = nil, 0
				vim.schedule(function()
					if client.state == "open" then
						opts.on_message(client, text)
					end
				end)
			end
		elseif f.opcode == OP.BINARY then
			client:close(CLOSE.UNSUPPORTED)
		else
			client:close(CLOSE.PROTOCOL) -- reserved opcode
		end
	end
end

---@param opts Beast.Review.ListenOpts
---@param client Beast.Review.Client
---@param chunk string
local function on_data(opts, client, chunk)
	client.buf = client.buf .. chunk
	if client.state == "open" then
		return pump(opts, client)
	end
	if client.state ~= "handshake" then
		return
	end

	local req, rest, err = handshake.parse(client.buf)
	if err then
		return client.write_and_close("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
	end
	if not req then
		return
	end

	local ok, response = handshake.respond(req, opts.token)
	if not ok then
		return client.write_and_close(response)
	end

	client.state, client.opened = "open", true
	if client.timer then
		client.timer:stop()
		client.timer:close()
		client.timer = nil
	end
	client.handle:write(response)
	client.buf = rest or ""
	vim.schedule(function()
		opts.on_open(client)
	end)
	pump(opts, client)
end

--- Bind 127.0.0.1 on an OS-assigned port and start accepting.
---@param opts Beast.Review.ListenOpts
---@return Beast.Review.Listener? listener
---@return string? err
function M.listen(opts)
	local server = uv.new_tcp()
	local ok, err = server:bind("127.0.0.1", 0)
	if not ok then
		server:close()
		return nil, err
	end

	---@type table<Beast.Review.Client, true>
	local clients = {}

	local listening, lerr = server:listen(128, function(accept_err)
		if accept_err then
			return
		end
		local handle = uv.new_tcp()
		server:accept(handle)
		local client = new_client(opts, handle, clients)
		clients[client] = true

		client.timer = uv.new_timer()
		client.timer:start(opts.handshake_timeout_ms, 0, function()
			if client.state == "handshake" then
				client.teardown()
			end
		end)

		handle:read_start(function(read_err, chunk)
			if read_err or not chunk then
				return client.teardown()
			end
			on_data(opts, client, chunk)
		end)
	end)
	if not listening then
		server:close()
		return nil, lerr
	end

	local port = server:getsockname().port
	return {
		port = port,
		clients = clients,
		close = function()
			if not server:is_closing() then
				server:close()
			end
			for c in pairs(clients) do
				c.teardown()
			end
		end,
	}
end

return M
