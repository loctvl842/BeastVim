---@class beast.util.colors
local M = {}

-- =============================================================================
-- Converter
-- =============================================================================

---@class Beast.RGB
---@field r number Red component (0-255)
---@field g number Green component (0-255)
---@field b number Blue component (0-255)

--- Convert hex color to RGB
---@param hex string Hex color string (e.g., "#ff6188")
---@return Beast.RGB
function M.hex_to_rgb(hex)
	if hex == nil or hex == "NONE" then
		return { r = 0, g = 0, b = 0 }
	end
	hex = string.lower(hex)
	return {
		r = tonumber(hex:sub(2, 3), 16) or 0,
		g = tonumber(hex:sub(4, 5), 16) or 0,
		b = tonumber(hex:sub(6, 7), 16) or 0,
	}
end

--- Convert RGB to hex color
---@param rgb Beast.RGB
---@return string Hex color string
function M.rgb_to_hex(rgb)
	local r = math.max(0, math.min(255, math.floor(rgb.r + 0.5)))
	local g = math.max(0, math.min(255, math.floor(rgb.g + 0.5)))
	local b = math.max(0, math.min(255, math.floor(rgb.b + 0.5)))
	return string.format("#%02x%02x%02x", r, g, b)
end

--- Parse a hex8 color (with alpha) and return hex6 + alpha
---@param hex8 string Hex color with alpha (e.g., "#ff618880")
---@return string hex6 Hex color without alpha
---@return number alpha Alpha value (0-1)
function M.parse_hex8(hex8)
	if hex8 == nil or #hex8 ~= 9 then
		return hex8 or "#000000", 1.0
	end
	local hex6 = hex8:sub(1, 7)
	local alpha = tonumber(hex8:sub(8, 9), 16) / 255
	return hex6, alpha
end

-- =============================================================================
-- Blend
-- =============================================================================

--- Blend a foreground color with a background color
---@param foreground string Hex color for foreground
---@param alpha number Alpha value (0-1), where 0 is fully background and 1 is fully foreground
---@param background string Hex color for background (defaults to black)
---@return string Blended hex color
function M.blend(foreground, alpha, background)
	if foreground == "NONE" then
		return "NONE"
	end

	background = background or "#000000"
	if background == "NONE" then
		background = "#000000"
	end

	local fg = M.hex_to_rgb(foreground)
	local bg = M.hex_to_rgb(background)

	local blended = {
		r = (1 - alpha) * bg.r + alpha * fg.r,
		g = (1 - alpha) * bg.g + alpha * fg.g,
		b = (1 - alpha) * bg.b + alpha * fg.b,
	}

	return M.rgb_to_hex(blended)
end

--- Lighten a color by adding to RGB values
---@param hex string Hex color
---@param amount number Amount to add (positive = lighter, negative = darker)
---@return string Lightened hex color
function M.lighten(hex, amount)
	if hex == "NONE" then
		return hex
	end

	local rgb = M.hex_to_rgb(hex)

	return M.rgb_to_hex({
		r = rgb.r + amount,
		g = rgb.g + amount,
		b = rgb.b + amount,
	})
end

--- Darken a color by subtracting from RGB values
---@param hex string Hex color
---@param amount number Amount to subtract (positive = darker)
---@return string Darkened hex color
function M.darken(hex, amount)
	return M.lighten(hex, -amount)
end

--- Blend RGBA color with background
---@param r number Red (0-255)
---@param g number Green (0-255)
---@param b number Blue (0-255)
---@param alpha number Alpha (0-1)
---@param background string Hex color for background
---@return string Blended hex color
function M.rgba(r, g, b, alpha, background)
	local bg = M.hex_to_rgb(background or "#000000")

	local blended = {
		r = (1 - alpha) * bg.r + alpha * r,
		g = (1 - alpha) * bg.g + alpha * g,
		b = (1 - alpha) * bg.b + alpha * b,
	}

	return M.rgb_to_hex(blended)
end

--- Extend a hex8 color (with embedded alpha) to a solid hex6 color
---@param hex8 string Hex color with alpha (e.g., "#ff618880")
---@param background string Background color to blend against
---@return string Solid hex6 color
function M.extend_hex8(hex8, background)
	if hex8 == nil or #hex8 ~= 9 then
		return hex8 or "#000000"
	end
	local hex6, alpha = M.parse_hex8(hex8)
	return M.blend(hex6, alpha, background)
end

-- =============================================================================

---@param prefix string Prefix for highlight groups e.g. "BeastNotify" -> will create "BeastNotifyInfo", "BeastNotifyWarn", etc.
---@param groups table<string, vim.api.keyset.highlight> Map of highlight group names to their definition.
function M.set_hl(prefix, groups)
	for name, def in pairs(groups) do
		local group = prefix .. name
		if def.link then
			vim.api.nvim_command("hi! link " .. group .. " " .. def.link)
		else
			vim.api.nvim_set_hl(0, group, def)
		end
	end
end

--- Build a prefixed highlights table without applying it. Used by
--- `<lib>/highlights.lua` `M.get()` functions feeding the central dispatcher.
---@param prefix string Prefix for highlight groups (e.g. "BeastFinder"). Empty for unprefixed (e.g. treesitter captures).
---@param groups table<string, vim.api.keyset.highlight|{link:string}>
---@return table<string, vim.api.keyset.highlight|{link:string}>
function M.build(prefix, groups)
	if prefix == "" then
		return groups
	end
	local out = {}
	for name, def in pairs(groups) do
		out[prefix .. name] = def
	end
	return out
end

---@class Beast.HighlightValue
---@field fg? string
---@field bg? string

---Get the color of a highlight group
---@param group string The name of the highlight group
---@return Beast.HighlightValue
function M.inspect(group)
	---@param name string
	local function get_hl_by_name(name)
		local hl = vim.api.nvim_get_hl(0, { name = name })
		local fg = hl and hl.fg
		local bg = hl and hl.bg
		return { fg = fg, bg = bg }
	end
	local success, hl = pcall(get_hl_by_name, group)
	if not success then
    -- stylua: ignore
    return setmetatable({}, { __index = function() return nil end, })
	end

	return setmetatable({}, {
		__index = function(_, key)
			return rawget(hl, key) and string.format("#%06x", rawget(hl, key)) or nil
		end,
	})
end

return M
