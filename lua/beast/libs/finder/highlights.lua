local M = {}

function M.get()
	local p = Theme.get()
	local bg = p.dark1
	return Util.colors.build("BeastFinder", {
		-- Shared
		Backdrop = { bg = bg },
		Border = { fg = p.dimmed3, bg = bg },
		Normal = { bg = bg, fg = p.text },
		-- Input
		InputNormal = { bg = bg, fg = p.text },
		InputPromptPrefix = { bg = bg, fg = p.accent2 },
		InputTitle = { bg = bg, fg = p.accent3, bold = true },
		Spinner = { bg = bg, fg = p.accent2 },
		-- List
		ListCursorLine = { bg = Util.colors.blend(p.dimmed3, 0.3, bg), bold = true },
		ListSelectionPrefix = { fg = p.accent2 },
		ListMatch = { bg = Util.colors.blend(p.text, 0.15, bg), bold = true },
		ListFile = { fg = p.text },
		ListDir = { fg = p.dimmed3 },
		ListSeparator = { fg = p.dimmed4 },
		ListSelected = { fg = p.accent5, bold = true },
		ListSelectedLine = { fg = p.accent5 },
		ListPointer = { fg = p.accent5 },
		-- Card style (colorscheme picker): editor > prompt panel > list panel, getting darker
		CardList = { bg = p.dark2, fg = p.text },
		CardInputNormal = { bg = p.dark1, fg = p.text },
		CardInputBorder = { fg = p.dark1, bg = p.dark1 },
		CardInputPrefix = { bg = p.dark1, fg = p.accent2 },
		SwatchEmpty = { fg = p.dimmed4 },
		ListCursor = { blend = 100, nocombine = true },
		-- Preview
		PreviewBorder = { fg = p.dimmed3, bg = bg },
		PreviewTitle = { bg = bg, fg = p.accent3, bold = true },
		PreviewMatch = { bg = Util.colors.blend(p.accent4, 0.1, bg), bold = true, underline = true },
		PreviewCurrentMatch = { bg = Util.colors.blend(p.accent4, 0.25, bg), bold = true },
	})
end

local frozen_list_ns ---@type integer|nil list-panel namespace while a picker has frozen colors

---@class Beast.Finder.FrozenColors
---@field input integer namespace for the prompt panel window
---@field list integer namespace for the list panel window

--- Snapshot the picker's current colors into one window-local highlight namespace per panel.
--- `:colorscheme` only rewrites global highlights, so windows attached to these namespaces
--- (`nvim_win_set_hl_ns`) keep the colors they had at open time. `winhl` mappings do not
--- resolve through a namespace, so each panel's base groups are defined directly in it.
---@return Beast.Finder.FrozenColors
function M.freeze()
	local groups = M.get()
	local frozen = {
		input = vim.api.nvim_create_namespace("beast-finder-frozen-input"),
		list = vim.api.nvim_create_namespace("beast-finder-frozen-list"),
	}
	---@param ns integer
	---@param panel table highlight def of the panel background
	---@param border table highlight def of the panel's border cells
	local function define(ns, panel, border)
		for name, def in pairs(groups) do
			vim.api.nvim_set_hl(ns, name, def)
		end
		for _, name in ipairs({ "Normal", "NormalFloat", "EndOfBuffer" }) do
			vim.api.nvim_set_hl(ns, name, { bg = panel.bg, fg = panel.fg })
		end
		vim.api.nvim_set_hl(ns, "FloatBorder", { bg = border.bg, fg = border.fg })
	end
	define(frozen.input, groups.BeastFinderCardInputNormal, groups.BeastFinderCardInputBorder)
	define(frozen.list, groups.BeastFinderCardList, groups.BeastFinderCardList)
	frozen_list_ns = frozen.list
	return frozen
end

--- Stop routing swatch groups into the frozen list namespace (picker closed).
function M.unfreeze()
	frozen_list_ns = nil
end

--- Highlight group painting a swatch square in `hex`, defined in the frozen list namespace
--- (global when the picker's colors are not frozen).
---@param hex string "#rrggbb"
---@return string group
function M.swatch(hex)
	local name = "BeastFinderSwatch" .. hex:sub(2)
	vim.api.nvim_set_hl(frozen_list_ns or 0, name, { fg = hex })
	return name
end

return M
