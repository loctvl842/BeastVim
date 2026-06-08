local p = Palette.get()

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
	-- Visual styling. Each per-state table is a single style applied to ALL
	-- elements of that state (text, icon underline, modified dot, close button,
	-- separator underline, diagnostic count, tabpage label). Any field left nil
	-- falls back to a value derived from the active Palette.
	--
	---@class Beast.Tabline.StateStyle
	---@field fg?        string  Main accent for the state
	---@field bg?        string  Cell background
	---@field underline? boolean Underline the entire cell row
	---@field sp?        string  Underline color (defaults to fg)
	---@field bold?      boolean
	appearance = {
		selected = { fg = p.text, bg = nil, underline = false, sp = nil, bold = true },
		visible = { fg = nil, bg = nil, underline = true, sp = nil, bold = false },
		normal = { fg = nil, bg = nil, underline = true, sp = nil, bold = false },

		-- Right-side fill (gap between buffers and tabpages). Also drives
		-- TruncMarker and ToggleButton underline so the bottom rule stays continuous.
		fill = {
			bg = nil,
			underline = true,
			sp = nil,
		},

		-- Separator glyph between buffer cells. Underline color is inherited
		-- from each adjacent cell's state; only the glyph `fg` lives here.
		separator = {
			fg = nil, -- normal-state separator
			fg_visible = nil,
			fg_selected = nil,
		},
	},
}

---@type Beast.Tabline.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Tabline.Config
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
		error(string.format("beast.libs.tabline.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
