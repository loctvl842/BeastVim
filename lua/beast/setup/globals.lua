-- Beast global registrations. Installs `_G.Util / Palette / Key / View / Icon`
-- (the symbols every lib expects to be available) and calls `Palette.setup()`.
--
-- This is the first thing `beast.setup()` runs after computing `cfg` — every
-- subsequent lib setup assumes these globals exist.

local M = {}

function M.run()
	require("beast.option")

	_G.Util = require("beast.util") ---@type Beast.Util
	_G.Palette = Util.mod("beast.theme") ---@type Beast.Theme
	_G.Key = Util.mod("beast.libs.key") ---@type Beast.Key
	_G.View = Util.mod("beast.libs.view") ---@type Beast.View
	_G.Icon = Util.mod("beast.icon") ---@type Beast.Icon
	_G.Lsp = Util.mod("beast.libs.lsp") ---@type Beast.Lsp

	Palette.setup()
end

return M
