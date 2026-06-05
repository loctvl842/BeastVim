---@class Beast.Window.AutowidthFiletype : table<string, number>

---@class Beast.Window.AutowidthConfig
---@field enable boolean
---@field winwidth number Padding beyond textwidth (or fraction if 0<w<1 or 1<w<2).
---@field filetype Beast.Window.AutowidthFiletype Per-ft override of `winwidth`.

---@class Beast.Window.AnimationConfig
---@field enable boolean
---@field duration integer Total duration in ms.
---@field easing string|fun(t:number):number One of: linear|ease_in|ease_out|ease_in_out, or a function.

---@class Beast.Window.IgnoreConfig
---@field buftype table<string, true>|string[]
---@field filetype table<string, true>|string[]

---@class Beast.Window.Config
---@field autowidth Beast.Window.AutowidthConfig
---@field animation Beast.Window.AnimationConfig
---@field ignore Beast.Window.IgnoreConfig

---@type Beast.Window.Config
local defaults = {
	autowidth = {
		enable = true,
		winwidth = 5,
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

---@param list string[]|table<string,true>
---@return table<string,true>
local function to_set(list)
	if type(list) ~= "table" then
		return {}
	end
	-- Already a set? leave alone.
	if next(list) and type(next(list)) == "string" and list[1] == nil then
		return list --[[@as table<string,true>]]
	end
	local set = {}
	for _, item in ipairs(list) do
		set[item] = true
	end
	return set
end

local M = vim.deepcopy(defaults)
M.ignore.buftype = to_set(M.ignore.buftype)
M.ignore.filetype = to_set(M.ignore.filetype)

local initialized = false

---@param opts? Beast.Window.Config
---@return Beast.Window.Config
function M.setup(opts)
	if initialized then
		return M
	end
	opts = opts or {}
	local merged = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
	M.autowidth = merged.autowidth
	M.animation = merged.animation
	M.ignore = {
		buftype = to_set(merged.ignore.buftype),
		filetype = to_set(merged.ignore.filetype),
	}
	initialized = true
	return M
end

return M
