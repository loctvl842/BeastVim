-- User-facing notices for the review lib. Everything goes through Toast so
-- messages share the app's look; callers never touch vim.notify directly.

---@param message string|string[]
---@param level? integer  vim.log.levels.*
return function(message, level)
	require("beast.libs.toast")(message, level or vim.log.levels.INFO, { title = require("beast.libs.review").meta.name })
end
