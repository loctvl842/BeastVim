-- Beast global registrations. Installs `_G.Util / Palette / Key / View / Icon`
-- (the symbols every lib expects to be available) and calls `Palette.setup()`.
--
-- This is the first thing `beast.setup()` runs after computing `cfg` — every
-- subsequent lib setup assumes these globals exist.

local M = {}

function M.run()
	require("beast.option")

	_G.Util = require("beast.util")
	_G.Palette = Util.mod("beast.palette")
	_G.Key = Util.mod("beast.libs.key")
	_G.View = Util.mod("beast.libs.view")
	_G.Icon = Util.mod("beast.icon")

	Palette.setup()
end

return M
