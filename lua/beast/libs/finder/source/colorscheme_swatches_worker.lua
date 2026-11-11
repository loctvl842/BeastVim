--- Headless worker: applies each colorscheme once and prints its ten swatch colors as JSON.
--- Run as: nvim --headless -u NONE -l colorscheme_swatches_worker.lua <runtimepath> <name>...
--- Output: { [name] = (string|false)[10] } - hex colors in role order, false when a theme leaves a role unset.

local rtp = arg[1]
vim.o.runtimepath = rtp

-- Skip ColorScheme hooks: only the highlight groups matter here.
vim.o.eventignore = "ColorScheme"

---Role order of the swatch strip. Each role lists groups to try, first one with the attribute wins.
---@type { attr: "fg"|"bg", groups: string[] }[]
local roles = {
	{ attr = "bg", groups = { "Normal" } },
	{ attr = "fg", groups = { "Normal" } },
	{ attr = "fg", groups = { "ErrorMsg", "DiagnosticError" } },
	{ attr = "fg", groups = { "Number", "Constant" } },
	{ attr = "fg", groups = { "WarningMsg", "DiagnosticWarn" } },
	{ attr = "fg", groups = { "String" } },
	{ attr = "fg", groups = { "Special", "Type" } },
	{ attr = "fg", groups = { "Function" } },
	{ attr = "fg", groups = { "Keyword", "Statement" } },
	{ attr = "fg", groups = { "Comment" } },
}

---@param role { attr: "fg"|"bg", groups: string[] }
---@return string|false
local function read(role)
	for _, group in ipairs(role.groups) do
		local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
		if hl[role.attr] then
			return string.format("#%06x", hl[role.attr])
		end
	end
	return false
end

local out = {}
for i = 2, #arg do
	local name = arg[i]
	local ok = pcall(vim.cmd.colorscheme, name)
	local colors = {}
	for r, role in ipairs(roles) do
		colors[r] = ok and read(role) or false
	end
	out[name] = colors
end

io.stdout:write(vim.json.encode(out))
