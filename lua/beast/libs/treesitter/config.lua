---@class Beast.Treesitter.Config
local defaults = {
	---@type string[]
	ensure_installed = {},
	highlight = {
		enable = true,
	},
	fold = {
		enable = false,
	},
	-- Sticky context header: a floating overlay pinned to the top of the
	-- window that shows the enclosing treesitter scopes (function, class,
	-- conditional, loop, …) of the node under the cursor once their header
	-- scrolls out of view. Cursor mode only; no separator.
	context = {
		enable = false,
		-- Keep a context overlay in every eligible split simultaneously, so it
		-- persists in unfocused windows. Set false to only show it in the
		-- currently focused window.
		multiwindow = true,
		-- Max context lines to draw. 0 means no limit (capped only by the
		-- distance between the viewport top and the cursor).
		max_lines = 0,
		-- Minimum window height required to draw context. 0 disables the check.
		min_window_height = 0,
		-- Mirror the window's line-number / sign column in the sticky overlay
		-- so it covers the statuscolumn instead of leaving a bare gutter.
		line_numbers = true,
		-- Max lines to show for a single multi-line header (e.g. long
		-- function signatures).
		multiline_threshold = 20,
		-- Which contexts to discard first when `max_lines` is exceeded.
		---@type "outer"|"inner"
		trim_scope = "inner",
		zindex = 20,
	},
}

---@type Beast.Treesitter.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Treesitter.Config
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
		error(string.format("beast.treesitter.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
