-- stylua: ignore
local mode_names = {
	n = "NORMAL", no = "O-PENDING", nov = "O-PENDING", noV = "O-PENDING", ["no\22"] = "O-PENDING",
	niI = "NORMAL", niR = "NORMAL", niV = "NORMAL", nt = "NORMAL", ntT = "NORMAL",
	v = "VISUAL", vs = "VISUAL", V = "V-LINE", Vs = "V-LINE",
	["\22"] = "V-BLOCK", ["\22s"] = "V-BLOCK",
	s = "SELECT", S = "S-LINE", ["\19"] = "S-BLOCK",
	i = "INSERT", ic = "INSERT", ix = "INSERT",
	R = "REPLACE", Rc = "REPLACE", Rx = "REPLACE",
	Rv = "V-REPLACE", Rvc = "V-REPLACE", Rvx = "V-REPLACE",
	c = "COMMAND", cv = "EX", ce = "EX",
	r = "REPLACE", rm = "MORE", ["r?"] = "CONFIRM",
	["!"] = "SHELL", t = "TERMINAL",
}

-- stylua: ignore
local mode_colors = {
	n = "accent1", i = "accent4",
	v = "accent5", V = "accent5", ["\22"] = "accent5",
	c = "accent2", R = "accent2", r = "accent2",
	s = "accent6", S = "accent6", ["\19"] = "accent6",
	t = "accent4", ["!"] = "accent1",
}

---@type Beast.Statusline.ComponentSpec
return {
	condition = function(ctx)
		return ctx.is_active
	end,
	update = { "ModeChanged" },
	scope = "global",
	priority = 90,
	provider = function(ctx)
		local key = mode_names[ctx.mode] and ctx.mode or ctx.mode:sub(1, 1)
		local name = mode_names[key] or "NORMAL"
		local color = mode_colors[ctx.mode:sub(1, 1)] or "accent1"
		return {
			{ text = name, hl = { fg = color, bold = true } },
			{ text = " ", hl = { fg = "text" } },
		}
	end,
}
