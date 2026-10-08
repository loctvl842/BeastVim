---Status of a blink.cmp source provider.
---Never instantiates a provider (that would call its `source:new()`): a provider
---that hasn't been used yet is just "idle".
---@param name string
---@return "idle"|"loading"|"completed"?
local function source_status(name)
	-- stylua: ignore
	if not package.loaded["blink.cmp.config"] then return nil end
	local sources = require("blink.cmp.sources.lib")
	-- stylua: ignore
	if sources.providers[name] == nil and require("blink.cmp.config").sources.providers[name] == nil then return nil end

	local list = sources.providers[name] and sources.providers[name].list
	-- stylua: ignore
	if not list then return "idle" end
	return list.has_completed and "completed" or "loading"
end

---Statusline component showing one icon per registered blink.cmp source, colored by
---its state: idle (dim), loading (accent), completed (the source's brand color).
---Icons and colors come from `Icon.brain` / `Icon.colors.brain`, keyed by source id.
---@param source_ids string[]
---@return Beast.Statusline.ComponentSpec
return function(source_ids)
	return {
		condition = function(ctx)
			return ctx.is_active
		end,
		scope = "global",
		priority = 60,
		provider = function()
			local fragments = {}
			for _, id in ipairs(source_ids) do
				local status = source_status(id)
				local icon = Icon.brain[id]
				if status and icon then
					local fg = ({
						idle = "dimmed3",
						loading = "accent4",
						completed = Icon.colors.brain[id],
					})[status]
					fragments[#fragments + 1] = { text = icon, hl = { fg = fg } }
				end
			end
			return fragments
		end,
	}
end
