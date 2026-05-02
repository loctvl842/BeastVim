local hlgroup = require("beast.libs.statusline.hlgroup")

local M = {}

---Compute display width of a single fragment.
---Components can pre-compute width (cached) to avoid the vim.fn call.
---@param frag Beast.Statusline.Fragment
---@return integer
function M.fragment_width(frag)
	if frag.width then
		return frag.width
	end
	return vim.fn.strdisplaywidth(frag.text or "")
end

---Sum of all fragment widths in a list.
---@param fragments Beast.Statusline.Fragment[]
---@return integer
function M.fragments_width(fragments)
	local total = 0
	for _, f in ipairs(fragments) do
		total = total + M.fragment_width(f)
	end
	return total
end

---@type integer?
local _cached_sep_width = nil

---@param sep string
---@return integer
function M.sep_width(sep)
	if _cached_sep_width ~= nil then
		return _cached_sep_width
	end
	_cached_sep_width = vim.fn.strdisplaywidth(sep)
	return _cached_sep_width
end

---Compute total display width including inter-component separators.
---@param items Beast.Statusline.VisibleItem[]
---@param default_sep string
---@return integer
function M.total_width(items, default_sep)
	local total = 0
	for i, item in ipairs(items) do
		total = total + M.fragments_width(item.fragments)
		if i < #items then
			local sep = item.spec.separator or default_sep
			if sep and sep ~= "" then
				total = total + M.sep_width(sep)
			end
		end
	end
	return total
end

---Assemble a list of visible components into a statusline format string for one section.
---
---For each fragment we emit `%#GroupName#text%*`. Adjacent fragments within the same
---component share their own highlight; `%*` resets at each fragment boundary, which is
---negligibly more characters but makes truncation safer (no highlight bleed across cuts).
---@param items Beast.Statusline.VisibleItem[]
---@param default_sep string
---@return string
function M.assemble(items, default_sep)
	local parts = {}
	for i, item in ipairs(items) do
		for _, frag in ipairs(item.fragments) do
			local group = hlgroup.ensure(frag.hl)
			if group then
				parts[#parts + 1] = "%#" .. group .. "#"
				parts[#parts + 1] = frag.text or ""
				parts[#parts + 1] = "%*"
			else
				parts[#parts + 1] = frag.text or ""
			end
		end
		if i < #items then
			local sep = item.spec.separator or default_sep
			if sep and sep ~= "" then
				parts[#parts + 1] = sep
			end
		end
	end
	return table.concat(parts)
end

-- =========================================================================
-- Ignored filetypes (transient UI buffers)
-- =========================================================================
-- File-bound components (encoding / shiftwidth / filetype / position) show
-- their last-known value when the focused buffer matches one of these.

---@type table<string, true>
M.IGNORED_FILETYPES = {
	["beast-backdrop"] = true,
	["beast-confirm"] = true,
	["beast-explorer"] = true,
	["beast-key"] = true,
	["beast-key-actions"] = true,
	["beast-notify"] = true,
	["beast-packer"] = true,
	["beast-packer-actions"] = true,
	["beast-toast"] = true,
}

---@param ctx Beast.Statusline.Context
---@return boolean
function M.is_file_buffer(ctx)
	return not M.IGNORED_FILETYPES[ctx.filetype]
end

---Create a provider that is bound to the last real file buffer.
---
---The `compute` function only runs when the current buffer is a file (not a transient
---beast-* UI buffer). Its return value is remembered. When focus moves to an ignored
---buffer (explorer, toast, etc.), the last known value is returned so the component
---stays visible with meaningful content instead of going blank.
---
---Return values from `compute`:
---  string → update the stored value
---  false  → clear the stored value (component will hide)
---  nil    → keep the previous stored value unchanged
---
---Returns nil until a real file buffer is seen for the first time.
---@param compute fun(ctx: Beast.Statusline.Context): string|false|nil
---@return fun(ctx: Beast.Statusline.Context): string?
function M.file_bound(compute)
	local last_value = nil
	return function(ctx)
		if M.is_file_buffer(ctx) then
			local val = compute(ctx)
			if val == false then
				last_value = nil
			elseif val then
				last_value = val
			end
		end
		return last_value
	end
end

return M
