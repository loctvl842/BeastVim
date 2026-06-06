---@class Beast.Window.Config
---@field autowidth { enable: boolean, winwidth: number, filetype: table<string, number> }
---@field animation { enable: boolean, duration: integer, easing: string|fun(t:number):number }
---@field ignore { buftype: string[]|table<string,true>, filetype: string[]|table<string,true> }
local defaults = {
	autowidth = {
		enable = true,
		winwidth = 10,
		filetype = { help = 2 },
	},
	animation = {
		enable = true,
		duration = 150,
		easing = "ease_in_out",
	},
	ignore = {
		buftype = { "quickfix", "nofile", "prompt" },
		filetype = {
			"beast-explorer",
			"beast-finder-list",
			"beast-finder-input",
			"beast-finder-preview",
			"beast-key",
			"beast-toast",
			"beast-notify",
			"beast-confirm",
			"qf",
			"NvimTree",
			"neo-tree",
			"Outline",
			"undotree",
			"gundo",
		},
	},
}

local function to_set(list)
	if type(list) ~= "table" then
		return {}
	end
	if list[1] == nil then
		return list
	end
	local set = {}
	for _, v in ipairs(list) do
		set[v] = true
	end
	return set
end

local function normalize(c)
	c.ignore.buftype = to_set(c.ignore.buftype)
	c.ignore.filetype = to_set(c.ignore.filetype)
	return c
end

---@type Beast.Window.Config
local cfg = normalize(vim.deepcopy(defaults))

local methods = {}

---@param opts? Beast.Window.Config
function methods.setup(opts)
	cfg = normalize(vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {}))
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,
	__newindex = function(_, key, _)
		error(string.format("beast.libs.window.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
