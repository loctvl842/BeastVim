---@class Beast.Tabline.Config
local defaults = {
	-- Buffer cell appearance
	max_name_width = 24,
	min_cell_width = 0, -- Minimum width per buffer cell (0 = no minimum)
	show_close_button = true,
	show_modified = true,
	show_diagnostics = true,

	-- Sidebar offset
	-- ft → title to render in the offset block.
	-- Empty string keeps the offset width but renders nothing (used by beast-explorer).
	sidebar_filetypes = {
		["neo-tree"] = "EXPLORER",
		["NvimTree"] = "EXPLORER",
		["beast-explorer"] = "",
	},

	-- Toggle button (right side — toggles background dark/light)
	toggle_button_dark_icon = " ", -- shown in dark mode
	toggle_button_light_icon = " ", -- shown in light mode

	-- Icons shown inside truncation markers
	-- Left: " N <icon> " (e.g. " 3 … ")   Right: " <icon> N " (e.g. " … 2 ")
	left_trunc_icon = "",
	right_trunc_icon = "",
}

---@type Beast.Tabline.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Tabline.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	-- Must enable opts
	vim.opt.showtabline = 2 -- always show tabline
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.libs.tabline.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
