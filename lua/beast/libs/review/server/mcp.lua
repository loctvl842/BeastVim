-- MCP method table. Every protocol-facing name lives here, so a Claude Code
-- change to the (reverse-engineered) contract is a one-line fix.

local jsonrpc = require("beast.libs.review.server.jsonrpc")
local tools = require("beast.libs.review.server.tools")

local M = {}

M.PROTOCOL_VERSION = "2024-11-05"

---@type table<string, Beast.Review.RpcHandler>
M.handlers = {
	["initialize"] = function()
		return {
			protocolVersion = M.PROTOCOL_VERSION,
			capabilities = {
				logging = vim.empty_dict(),
				prompts = { listChanged = true },
				tools = { listChanged = true },
			},
			serverInfo = { name = "beastvim-review", version = "0.1.0" },
		}
	end,

	["notifications/initialized"] = function() end,

	["prompts/list"] = function()
		return { prompts = {} }
	end,

	["tools/list"] = function()
		return { tools = tools.list() }
	end,

	["tools/call"] = function(params, ctx)
		local tool = type(params.name) == "string" and tools.tools[params.name]
		if not tool then
			return nil, jsonrpc.error(jsonrpc.ERR.NOT_FOUND, "Tool not found", tostring(params.name))
		end
		return tool.handler(type(params.arguments) == "table" and params.arguments or {}, ctx)
	end,
}

return M
