-- Beast.Statusline highlight refresh hook.
-- This is required to ensure that the statusline highlights are always up-to-date.

local hlgroup = require("beast.libs.statusline.hlgroup")
hlgroup.clear_all()

-- Redraw statusline to trigger statusline.render()
-- so that the highlight groups are re-created with the new palette colors.
vim.cmd("redrawstatus")
