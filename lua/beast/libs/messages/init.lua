-- Message UI: enables Neovim's ui2 (no hit-enter prompt with cmdheight = 0) and
-- diverts selected message kinds (errors, warnings, search wrap) to Toast.
--
-- ui2 looks its handlers up at call time (`M.msg[event]`), so replacing
-- `ui2.messages.msg_show` intercepts every message without a custom cmdline UI.
-- ui2 is experimental; everything here is gated and falls back to ui2's own
-- behavior on any error.

local config = require("beast.libs.messages.config")
local router = require("beast.libs.messages.router")

local M = {}

---@type Beast.Lib.Meta
M.meta = { name = "messages", description = "ui2 message UI with toast routing" }

---@return boolean
function M.available()
	return vim.fn.has("nvim-0.12") == 1 and pcall(require, "vim._core.ui2")
end

---@type boolean
local routed = false

---@return boolean
function M.is_routing()
	return routed
end

---@param kind string
---@param content table[]
---@return boolean handled
local function route(kind, content)
	local resolved = router.resolve(config.routes, kind, router.flatten(content))
	-- stylua: ignore
	if not resolved then return false end
	if resolved.text then
		-- msg_show for internal messages runs in api-fast context.
		vim.schedule(function()
			Toast(resolved.text, resolved.level or vim.log.levels.INFO, { title = resolved.title })
		end)
	end
	return true
end

function M.setup(opts)
	config.setup(opts)
	-- stylua: ignore
	if not M.available() then return end

	require("vim._core.ui2").enable(vim.deepcopy(config.ui2))

	local messages = require("vim._core.ui2.messages")
	local original = messages.msg_show
	messages.msg_show = function(kind, content, ...)
		local ok, handled = pcall(route, kind, content)
		if ok and handled then
			return
		end
		return original(kind, content, ...)
	end
	routed = true
end

return M
