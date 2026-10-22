-- JSON-RPC 2.0 envelope over the WebSocket text channel.
--
-- Handlers answer synchronously by returning `result` (or `nil, err`), or ask
-- for a deferred answer by returning DEFERRED and calling `ctx.reply` later
-- (openDiff blocks until the user decides). Requests still pending when a
-- client disconnects are cancelled through `ctx.on_cancel`, so nothing is left
-- waiting on a socket that no longer exists.

local M = {}

M.DEFERRED = {}

M.ERR = {
	PARSE = -32700,
	INVALID = -32600,
	NOT_FOUND = -32601,
	PARAMS = -32602,
	INTERNAL = -32603,
}

---@class Beast.Review.RpcCtx
---@field client Beast.Review.Client
---@field id string|number
---@field reply fun(result?: table, err?: table)
---@field on_cancel fun(fn: fun())

---@alias Beast.Review.RpcHandler fun(params: table, ctx: Beast.Review.RpcCtx): table?, table?

---@type table<Beast.Review.Client, table<string|number, fun()?>>
local pending = {}

---@param client Beast.Review.Client
---@param id any
---@param result? table
---@param err? table
local function send(client, id, result, err)
	local msg = { jsonrpc = "2.0", id = id }
	if err then
		msg.error = err
	else
		msg.result = result
	end
	client:send(vim.json.encode(msg))
end

---@param code integer
---@param message string
---@param data? string
---@return table
function M.error(code, message, data)
	return { code = code, message = message, data = data }
end

---@param client Beast.Review.Client
---@param text string
---@param handlers table<string, Beast.Review.RpcHandler>
function M.handle(client, text, handlers)
	local ok, msg = pcall(vim.json.decode, text)
	if not ok then
		return send(client, vim.NIL, nil, M.error(M.ERR.PARSE, "Parse error"))
	end
	-- Batches and non-objects are not part of the MCP transport.
	if type(msg) ~= "table" or vim.islist(msg) or msg.jsonrpc ~= "2.0" or type(msg.method) ~= "string" then
		local id = type(msg) == "table" and msg.id or nil
		return send(client, id == nil and vim.NIL or id, nil, M.error(M.ERR.INVALID, "Invalid Request"))
	end

	local id, handler = msg.id, handlers[msg.method]
	local params = type(msg.params) == "table" and msg.params or {}

	if id == nil then -- notification: never answered
		if handler then
			pcall(handler, params, { client = client })
		end
		return
	end
	if not handler then
		return send(client, id, nil, M.error(M.ERR.NOT_FOUND, "Method not found", msg.method))
	end

	local done = false
	local reqs = pending[client]
	if not reqs then
		reqs = {}
		pending[client] = reqs
	end

	local ctx
	ctx = {
		client = client,
		id = id,
		reply = function(result, err)
			if done then
				return
			end
			done, reqs[id] = true, nil
			send(client, id, result, err)
		end,
		on_cancel = function(fn)
			if not done then
				reqs[id] = fn
			end
		end,
	}

	local pok, result, err = pcall(handler, params, ctx)
	if not pok then
		return ctx.reply(nil, M.error(M.ERR.INTERNAL, "Internal error", tostring(result)))
	end
	if result == M.DEFERRED then
		return
	end
	ctx.reply(result, err)
end

--- A client went away: abandon everything it was still waiting on.
---@param client Beast.Review.Client
function M.client_closed(client)
	local reqs = pending[client]
	pending[client] = nil
	for _, cancel in pairs(reqs or {}) do
		pcall(cancel)
	end
end

return M
