-- WebSocket server lifecycle. Transport only: it delivers complete text
-- messages and knows nothing about JSON-RPC or MCP.

local tcp = require("beast.libs.review.server.tcp")

local M = {}

local DEFAULTS = {
	max_payload = 16 * 1024 * 1024,
	handshake_timeout_ms = 5000,
	on_open = function() end,
	on_message = function() end,
	on_close = function() end,
}

--- Start listening on 127.0.0.1 (OS-assigned port).
---@param opts { token: string, max_payload?: integer, handshake_timeout_ms?: integer, on_open?: function, on_message?: function, on_close?: function }
---@return Beast.Review.Listener? listener
---@return string? err
function M.start(opts)
	assert(type(opts.token) == "string" and opts.token ~= "", "review.server: token is required")
	return tcp.listen(vim.tbl_extend("keep", opts, DEFAULTS))
end

return M
