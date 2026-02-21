local M = {}

M.managed = require("beastvim.libs.key.core").managed

function M.setup()
  require("beastvim.libs.key.builtin")
end

return M
