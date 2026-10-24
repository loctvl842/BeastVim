---@class Beast.Theme.BasePalette
---@field dark2 string
---@field dark1 string
---@field background string
---@field text string
---@field accent1 string
---@field accent2 string
---@field accent3 string
---@field accent4 string
---@field accent5 string
---@field accent6 string
---@field dimmed1 string
---@field dimmed2 string
---@field dimmed3 string
---@field dimmed4 string
---@field dimmed5 string
---@class Beast.Theme.Palette: Beast.Theme.BasePalette
---@field red string Semantic: palette color closest in hue to red
---@field yellow string Semantic: palette color closest in hue to yellow
---@field green string Semantic: palette color closest in hue to green

local M = {}

---@alias Beast.Theme.Semantic "red"|"yellow"|"green"

--- Target hue (degrees) and fallback per semantic color.
---@type table<Beast.Theme.Semantic, { hue: number, fallback: string }>
local semantic_targets = {
	red = { hue = 355, fallback = "#ffc0b9" },
	yellow = { hue = 48, fallback = "#fce094" },
	green = { hue = 130, fallback = "#b3f6c0" },
}

--- Palette colors with less chroma than this are treated as neutral (no hue).
local MIN_CHROMA = 0.12

---@type Beast.Theme.BasePalette
M.defaults = {
	dark2 = "#33353a",
	dark1 = "#282a30",
	background = "#14161b",
	text = "#e0e2ea",
	accent1 = "#ffc0b9",
	accent2 = "#fce094",
	accent3 = "#b3f6c0",
	accent4 = "#8cf8f7",
	accent5 = "#a6dbff",
	accent6 = "#ffcaff",
	dimmed1 = "#adafb6",
	dimmed2 = "#84868d",
	dimmed3 = "#66686e",
	dimmed4 = "#47494f",
	dimmed5 = "#282a30",
}

--- Read `attr` of highlight `group`, falling back when it is unset.
---@param group string
---@param attr "fg"|"bg"
---@param fallback string
---@return string
function M.extract(group, attr, fallback)
	return Util.colors.inspect(group)[attr] or fallback
end

--- Build a palette from a `{ key = { group, attr } }` map.
---@param map table<string, { [1]: string, [2]: "fg"|"bg" }>
---@return Beast.Theme.BasePalette
function M.from_groups(map)
	local palette = {}
	for key, default in pairs(M.defaults) do
		local spec = map[key]
		palette[key] = M.extract(spec[1], spec[2], default)
	end
	return palette
end

--- Hue (degrees, 0-360) and chroma (0-1) of a hex color.
---@param hex string
---@return number hue
---@return number chroma
local function hue_chroma(hex)
	local c = Util.colors.hex_to_rgb(hex)
	local r, g, b = c.r / 255, c.g / 255, c.b / 255
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local chroma = max - min
	if chroma == 0 then
		return 0, 0
	end
	local hue
	if max == r then
		hue = ((g - b) / chroma) % 6
	elseif max == g then
		hue = (b - r) / chroma + 2
	else
		hue = (r - g) / chroma + 4
	end
	return hue * 60, chroma
end

--- Add `red`, `yellow` and `green` to `p`: for each, the palette color whose
--- hue is closest to the target, regardless of key names. Neutral colors are
--- skipped and a color is never picked twice (closest pairs are assigned
--- first). Falls back to the default when no chromatic color is left.
---@param base Beast.Theme.BasePalette
---@return Beast.Theme.Palette
function M.with_semantic(base)
	local p = base --[[@as Beast.Theme.Palette]]
	local pairs_ = {}
	for key in pairs(M.defaults) do
		local hue, chroma = hue_chroma(p[key])
		if chroma >= MIN_CHROMA then
			for name, target in pairs(semantic_targets) do
				local d = math.abs(hue - target.hue) % 360
				table.insert(pairs_, { name = name, key = key, dist = math.min(d, 360 - d) })
			end
		end
	end
	table.sort(pairs_, function(a, b)
		if a.dist ~= b.dist then
			return a.dist < b.dist
		end
		return a.key < b.key
	end)

	local used = {}
	for _, c in ipairs(pairs_) do
		if p[c.name] == nil and not used[c.key] then
			p[c.name] = p[c.key]
			used[c.key] = true
		end
	end
	for name, target in pairs(semantic_targets) do
		p[name] = p[name] or target.fallback
	end
	return p
end

--- Nvim/beastvim themes often define StatusLine with reverse or a light bg
--- which clashes with the dark-themed UI. Override with palette-derived colors.
---@param p Beast.Theme.Palette
function M.override_statusline(p)
	vim.api.nvim_set_hl(0, "StatusLine", { fg = p.text, bg = p.dark2 })
	vim.api.nvim_set_hl(0, "StatusLineNC", { fg = p.dimmed3, bg = p.dark1 })
end

return M
