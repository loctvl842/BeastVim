-- Pure message routing: decides whether a message becomes a toast, is dropped,
-- or is left to ui2. No Neovim state, so it is unit-testable.

local M = {}

local MAX_LINES = 1

---@class Beast.Messages.Resolved
---@field drop? boolean
---@field text? string
---@field level? integer
---@field title? string

---Flatten ui-messages `content` chunks (`{ attr_id, text, hl_id }`) into text.
---@param content table[]
---@return string
function M.flatten(content)
	local parts = {}
	for _, chunk in ipairs(content) do
		parts[#parts + 1] = chunk[2]
	end
	return (table.concat(parts):gsub("^%s+", ""):gsub("%s+$", ""))
end

---Keep a toast readable: first line only, with the number of hidden lines.
---@param text string
---@return string
local function spill(text)
	local lines = vim.split(text, "\n", { plain = true })
	if #lines <= MAX_LINES then
		return text
	end
	return table.concat(vim.list_slice(lines, 1, MAX_LINES), "\n") .. string.format(" [+%d]", #lines - MAX_LINES)
end

---@param routes Beast.Messages.Route[]
---@param kind string
---@param text string
---@return Beast.Messages.Resolved?
function M.resolve(routes, kind, text)
	for _, route in ipairs(routes) do
		if vim.tbl_contains(route.kind, kind) then
			local caps = route.match and { text:match(route.match) } or {}
			if not route.match or #caps > 0 then
				if route.drop then
					return { drop = true }
				end
				local out = route.format and route.format(unpack(caps)) or spill(text)
				return { text = out, level = route.level, title = route.title }
			end
		end
	end
	return nil
end

return M
