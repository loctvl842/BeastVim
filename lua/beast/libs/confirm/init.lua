local config = require("beast.libs.confirm.config")
local ui = require("beast.libs.confirm.ui")

---@class Beast.Confirm.Parsed
---@field msg string
---@field labels string[]
---@field hotkeys string[]         -- lowercase hotkey per button (first char if no &)
---@field default integer
---@field opts Beast.Confirm.Opts

---@class Beast.Confirm.Opts
---@field min_width? integer
---@field max_width? integer
---@field button_width? integer
---@field align? BeastConfirmAlign
---@field description? string

---@type Beast.Confirm.Opts
local global_opts = { min_width = 50, max_width = 60, button_width = 12, align = "center" }

--- Parse choices string (same format as vim.fn.confirm).
--- Buttons separated by "\n", "&" marks the hotkey character.
---@param choices_str? string
---@return string[] labels
---@return string[] hotkeys
local function parse_choices(choices_str)
	if not choices_str or choices_str == "" then
		return { "OK" }, { "o" }
	end

	local labels = {}
	local hotkeys = {}

	for btn in choices_str:gmatch("[^\n]+") do
		local hotkey_char = btn:match("&(.)")
		local label = btn:gsub("&", "", 1)
		table.insert(labels, label)
		-- If no & specified, use first char (same as Neovim C source)
		table.insert(hotkeys, (hotkey_char or label:sub(1, 1)):lower())
	end

	return labels, hotkeys
end

--- Normalize and validate inputs.
---@param msg string
---@param choices? string
---@param default? integer
---@return Beast.Confirm.Parsed
local function normalize(msg, choices, default)
	local labels, hotkeys = parse_choices(choices)
	default = default or 1
	if default < 0 or default > #labels then
		default = 1
	end

	return {
		msg = msg or "",
		labels = labels,
		hotkeys = hotkeys,
		default = default,
		opts = vim.deepcopy(global_opts),
	}
end

--- Drop-in replacement for vim.fn.confirm with better UX.
--- Same signature: confirm(msg [, choices [, default [, type]]])
--- UI options are configured globally via confirm.setup() or confirm.set_opts().
---
---@param msg string
---@param choices? string          -- "\n"-separated, "&" marks hotkey (e.g. "&Yes\n&No\n&Cancel")
---@param default? integer         -- 1-based default (0=no default). Default: 1
---@param type? string             -- "Error"|"Question"|"Info"|"Warning"|"Generic" (for compat)
---@return integer                 -- 0=dismissed, 1..N = chosen button index
local function run(msg, choices, default, type)
	local parsed = normalize(msg, choices, default)

	-- Headless/no-UI fallback: delegate to native vim.fn.confirm
	if not vim.api.nvim_list_uis()[1] then
		local fallback_msg = parsed.msg
		if parsed.opts.description and parsed.opts.description ~= "" then
			fallback_msg = fallback_msg .. "\n\n" .. parsed.opts.description
		end
		return vim.fn.confirm(fallback_msg, choices or "&OK", parsed.default, type)
	end

	local view = ui.create(parsed)
	local selected = parsed.default
	ui.render(view, selected)
	vim.cmd("redraw")

	local result = ui.run_modal_loop(view, selected, parsed.hotkeys)
	ui.close(view)
	return result
end

local M = setmetatable({}, {
	__call = function(_, ...)
		if config.disabled then
			return vim.fn.confirm(...)
		end
		return run(...)
	end,
})

---@param opts? Beast.Confirm.Config
function M.setup(opts)
	require("beast").apply_highlights("beast.libs.confirm.highlights")
	config.setup(opts)
end

--- Set global UI options for the confirm dialog.
--- Since only one confirm can be open at a time, this configures all future calls.
---@param opts Beast.Confirm.Opts
function M.set_opts(opts)
	global_opts = opts or {}
end

return M
