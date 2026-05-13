local config = require("beast.libs.tabline.config")
local icons_mod = require("beast.libs.tabline.icons")
local name_mod = require("beast.libs.tabline.name")

local M = {}

local severity_map = {
	[1] = "Error",
	[2] = "Warn",
	[3] = "Info",
	[4] = "Hint",
}

--- Fast display-width: use byte length for ASCII, fallback for multibyte.
---@param s string
---@return integer
local function displaywidth(s)
	-- stylua: ignore
	if not s:find("[\128-\255]") then return #s end
	return vim.fn.strdisplaywidth(s)
end

--- Resolve the buffer state suffix: "Selected", "Visible", or "" (normal).
---@param bufnr integer
---@param ctx Beast.Tabline.Context
---@return string suffix
---@return boolean is_selected
local function resolve_state(bufnr, ctx)
	if bufnr == ctx.effective_active then
		return "Selected", true
	elseif ctx.visible_bufs[bufnr] then
		return "Visible", false
	else
		return "", false
	end
end

--- Resolve the buffer cell highlight group based on state and diagnostics.
---@param state_suffix string "Selected", "Visible", or ""
---@param diag? Beast.Tabline.DiagSummary
---@return string group_name
local function resolve_buffer_hl(state_suffix, diag)
	if diag and config.show_diagnostics then
		local sev = severity_map[diag.severity]
		if sev then
			return "BeastTlBuffer" .. state_suffix .. sev
		end
	end
	return "BeastTlBuffer" .. state_suffix
end

--- Resolve the diagnostic count highlight group.
---@param state_suffix string "Selected", "Visible", or ""
---@param severity integer
---@return string group_name
local function resolve_diag_hl(state_suffix, severity)
	local sev = severity_map[severity] or "Info"
	return "BeastTlDiag" .. sev .. state_suffix
end

--- Render a single buffer cell as a tabline format string.
--- Emits two adjacent, non-nested %@…@…%X regions: body + close button.
---@param bufnr integer
---@param ctx Beast.Tabline.Context
---@return string
function M.render(bufnr, ctx)
	local state_suffix, is_selected = resolve_state(bufnr, ctx)
	local diag = ctx.diag_by_buf[bufnr]
	local buf_hl = resolve_buffer_hl(state_suffix, diag)

	-- File icon (pre-computed in context)
	local icon_info = ctx.icons_by_buf[bufnr]
	local icon = icon_info and icon_info.icon or ""
	local icon_color = icon_info and icon_info.color

	-- Icon highlight (lazy per-color group)
	local icon_part
	if icon_color then
		local is_visible = state_suffix == "Visible"
		local icon_hl = icons_mod.ensure(icon_color, is_selected, is_visible)
		icon_part = "%#" .. icon_hl .. "#" .. icon .. " "
	else
		icon_part = "%#" .. buf_hl .. "#" .. icon .. " "
	end

	-- Display name (truncated)
	local display_name = ctx.names_by_buf[bufnr] or "[No Name]"
	display_name = name_mod.truncate_text(display_name, config.max_name_width)

	-- Status: diagnostic count or modified dot
	local status_part = ""
	local status_visible_w = 0
	if diag and config.show_diagnostics then
		local count = diag.errors[diag.severity] or diag.count
		local count_str = count > 9 and "9+" or tostring(count)
		local diag_hl = resolve_diag_hl(state_suffix, diag.severity)
		status_part = "%#" .. diag_hl .. "# " .. count_str
		status_visible_w = 1 + #count_str -- space + count
	elseif config.show_modified and ctx.modified_by_buf[bufnr] then
		local mod_hl = "BeastTlModified" .. state_suffix
		status_part = "%#" .. mod_hl .. "# ●"
		status_visible_w = 2 -- space + dot
	end

	-- Min-width padding: center content within min_cell_width
	local pad_left = ""
	local pad_right = ""
	if config.min_cell_width > 0 then
		local icon_w = displaywidth(icon) + 1 -- icon + space
		local name_w = displaywidth(display_name)
		local close_w = 3 -- " 󰅖 " or "   "
		local pads = 1 -- leading space in body
		local actual_w = pads + icon_w + name_w + status_visible_w + close_w
		if actual_w < config.min_cell_width then
			local total_pad = config.min_cell_width - actual_w
			local left = math.floor(total_pad / 2)
			local right = total_pad - left
			pad_left = string.rep(" ", left)
			pad_right = string.rep(" ", right)
		end
	end

	local buf_str = tostring(bufnr)
	local hl_open = "%#" .. buf_hl .. "#"

	-- Region 1: Buffer body click region
	local body = "%"
		.. buf_str
		.. "@v:lua.beast_tabline_buffer_click@"
		.. hl_open
		.. pad_left
		.. " "
		.. icon_part
		.. hl_open
		.. display_name
		.. status_part
		.. pad_right
		.. "%X"

	-- Region 2: Close button click region
	local close_part
	if is_selected and config.show_close_button then
		close_part = "%" .. buf_str .. "@v:lua.beast_tabline_close_click@%#BeastTlCloseButton# 󰅖%X "
	else
		-- Placeholder wrapped in buffer click so clicking anywhere on inactive cell switches to it
		close_part = "%" .. buf_str .. "@v:lua.beast_tabline_buffer_click@" .. hl_open .. "   %X"
	end

	return body .. close_part
end

return M
