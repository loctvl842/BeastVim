-- `cond` on a keymap spec: decides whether the keymap is registered at all.
-- A boolean or a function that returns true/false answers at once.

local M = {}

---Name used in messages about a keymap.
---@param spec Beast.KeymapSpec
---@return string
local function name(spec)
	return (spec.desc and spec.desc ~= "") and spec.desc or spec[1]
end

---@param spec Beast.KeymapSpec
---@return "yes"|"no"
function M.resolve(spec)
	local cond = spec.cond
	if type(cond) ~= "function" then
		return cond == false and "no" or "yes"
	end

	local ok, ret = pcall(cond)
	if not ok then
		require("beast.libs.toast")(("%s disabled: cond raised an error: %s"):format(name(spec), ret), "WARN", { title = "key" })
		return "no"
	end
	return ret == true and "yes" or "no"
end

return M
