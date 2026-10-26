---@class Beast.Messages.Route
---@field kind string[]                 Message kinds this route applies to (see :help ui-messages)
---@field match? string                 Lua pattern tested against the message text; captures go to `format`
---@field level? integer                vim.log.levels value for the toast
---@field title? string                 Toast title
---@field format? fun(...: string): string  Builds the toast text from the pattern captures (default: the message text)
---@field drop? boolean                 Swallow the message without any output

---@class Beast.Messages.Config
local defaults = {
	-- Options passed to vim._core.ui2.enable().
	ui2 = {
		msg = {
			-- Ephemeral message window (made for cmdheight = 0) instead of the cmdline.
			target = "msg",
			targets = { list_cmd = "pager" },
			msg = { timeout = 4000 },
		},
	},

	-- Ordered; the first matching route wins. Anything not matched is shown by ui2.
	---@type Beast.Messages.Route[]
	routes = {
		{
			kind = { "emsg" },
			match = "^E486: Pattern not found: (.*)",
			level = vim.log.levels.WARN,
			title = "Search",
			format = function(pat)
				return "Pattern not found: " .. pat
			end,
		},
		{
			kind = { "wmsg" },
			match = "^search hit (%u+)",
			level = vim.log.levels.INFO,
			title = "Search wrapped",
			format = function(edge)
				return edge == "BOTTOM" and "Hit BOTTOM, continuing at TOP" or "Hit TOP, continuing at BOTTOM"
			end,
		},
		-- The search-count lib already shows the count.
		{ kind = { "search_count" }, drop = true },
		{ kind = { "emsg", "echoerr", "lua_error", "rpc_error" }, level = vim.log.levels.ERROR },
		{ kind = { "wmsg" }, level = vim.log.levels.WARN },
	},
}

---@type Beast.Messages.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Messages.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.libs.messages.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
