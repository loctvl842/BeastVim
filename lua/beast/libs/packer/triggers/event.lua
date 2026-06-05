local M = {}

---@class Beast.Packer.EventSpec
---@field name string Autocmd event name (e.g. "VimEnter", "BufReadPost")
---@field pattern? string|string[] Optional autocmd pattern (e.g. "*.lua", "User BeastFoo")
---@field defer? boolean Wrap load in `vim.schedule()` (default: false).
---  Use for cosmetic libs that can paint one frame after the event fires.
---  Never set this for keys/cmd/module triggers — those are handled separately.

--- Normalize the user-provided event spec to a list of EventSpec tables.
--- Accepted forms (mix-and-match permitted):
---   "VimEnter"
---   { "BufReadPost", "BufNewFile" }
---   { name = "FileType", pattern = "lua", defer = false }
---   { { name = "VimEnter", defer = true }, "UIEnter", { name = "BufWritePre", defer = false } }
---@param events string|string[]|Beast.Packer.EventSpec|Beast.Packer.EventSpec[]
---@return Beast.Packer.EventSpec[]
local function normalize(events)
	if type(events) == "string" then
		return { { name = events } }
	end
	if type(events) ~= "table" then
		error("event spec must be a string, table, or list of those (got " .. type(events) .. ")", 3)
	end

	-- Single-object form: { name = "X", defer = true }
	if events.name then
		return { events }
	end

	-- List form: walk and normalize each entry
	local out = {}
	for i, e in ipairs(events) do
		if type(e) == "string" then
			out[i] = { name = e }
		elseif type(e) == "table" and e.name then
			out[i] = e
		else
			error(string.format("event spec[%d] must be a string or { name = <str>, ... } table", i), 3)
		end
	end
	if #out == 0 then
		error("event spec list is empty", 3)
	end
	return out
end

--- Setup one-shot autocmd triggers for a plugin / lib.
--- Each event in the spec gets its own autocmd. If `defer = true`, the load
--- callback is wrapped in `vim.schedule()` so the autocmd handler returns
--- immediately and the load runs on the next event-loop tick.
---@param plugin_spec Beast.Packer.PluginSpec Plugin spec with name and optional config
---@param events string|string[]|Beast.Packer.EventSpec|Beast.Packer.EventSpec[]
---@param load_fn fun(name: string, info: { type: string, detail: string })
function M.setup(plugin_spec, events, load_fn)
	for _, e in ipairs(normalize(events)) do
		local fire = function(ev)
			load_fn(plugin_spec.name, { type = "event", detail = ev.event })
		end
		local callback = fire
		if e.defer then
			callback = function(ev)
				vim.schedule(function() fire(ev) end)
			end
		end
		vim.api.nvim_create_autocmd(e.name, {
			pattern = e.pattern,
			once = true,
			callback = callback,
		})
	end
end

return M
