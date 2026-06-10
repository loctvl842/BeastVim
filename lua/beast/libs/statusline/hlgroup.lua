local PREFIX = "BeastStl_"

---Module-local caches. These survive across renders and are cleared by `clear_all()`.
---
---`name_cache`: spec_hash -> group_name. Avoids re-hashing the same spec table.
---`created`:    group_name -> true. Avoids re-issuing nvim_set_hl for already-created groups.
local name_cache = {}
local created = {}

local M = {}

---Resolve a palette alias (e.g. "accent1") to a hex string. Hex strings pass through.
---@param value string?
---@return string?
local function resolve_color(value)
	if value == nil then
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end
	if value:sub(1, 1) == "#" then
		return value
	end
	if value == "NONE" or value == "none" then
		return "NONE"
	end
	-- Theme alias lookup. Theme.get() returns a frozen snapshot.
	local ok, palette = pcall(function()
		return Theme.get()
	end)
	if not ok or not palette then
		return value
	end
	return palette[value] or value
end

---Build a deterministic hash for a hl spec. The order of keys in Lua tables is undefined,
---so we serialize into a sorted key=val string.
---@param spec Beast.Statusline.HighlightSpec
---@return string
local function hash_spec(spec)
	local parts = {}
	-- Stable, manually-ordered keys for predictability.
	local keys = { "fg", "bg", "bold", "italic", "underline", "reverse", "link" }
	for _, k in ipairs(keys) do
		local v = spec[k]
		if v ~= nil then
			parts[#parts + 1] = k .. "=" .. tostring(v)
		end
	end
	return table.concat(parts, ";")
end

---Build a group name from a hash. Group names must be valid Vim identifiers, so we strip
---characters Vim doesn't accept.
---@param hash string
---@return string
local function group_name_from_hash(hash)
	-- Replace anything that isn't a-z A-Z 0-9 or '_' with '_'. Vim allows ASCII letters,
	-- digits and underscore in highlight group names.
	local sanitized = hash:gsub("[^%w]", "_")
	return PREFIX .. sanitized
end

---Ensure a highlight group exists for the given spec; return the group name to reference.
---
---String specs (e.g. "Comment", "BeastStlGitBranch") are passed through unchanged — the
---caller is responsible for ensuring the group exists in the colorscheme.
---@param spec string|Beast.Statusline.HighlightSpec|nil
---@return string? group_name nil if spec is nil
function M.ensure(spec)
	if spec == nil then
		return nil
	end
	if type(spec) == "string" then
		return spec
	end

	local hash = hash_spec(spec)
	if hash == "" then
		return nil
	end

	local cached_name = name_cache[hash]
	if cached_name and created[cached_name] then
		return cached_name
	end

	local name = cached_name or group_name_from_hash(hash)
	name_cache[hash] = name

	if spec.link then
		vim.api.nvim_set_hl(0, name, { link = spec.link })
	else
		vim.api.nvim_set_hl(0, name, {
			fg = resolve_color(spec.fg),
			bg = resolve_color(spec.bg),
			bold = spec.bold or nil,
			italic = spec.italic or nil,
			underline = spec.underline or nil,
			reverse = spec.reverse or nil,
		})
	end

	created[name] = true
	return name
end

---Clear all created groups. Used by ColorScheme handler so that fresh palette colors
---are picked up on next render.
function M.clear_all()
	for name in pairs(created) do
		pcall(vim.api.nvim_set_hl, 0, name, {})
	end
	name_cache = {}
	created = {}
end

return M
