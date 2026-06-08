--- Pure helpers for the autopairs pair registry.
---
--- This module owns the "should we fire here?" primitive (neighborhood
--- pattern matching) and shape queries on pair specs. No state; all
--- functions are pure.

local M = {}

--- Match a neighborhood pattern against a 2-character context.
---
--- The pattern is anchored on both sides — it must match the full 2-char
--- string `before .. after`. At BOL/EOL the corresponding side is `""`;
--- we substitute a single space so 2-char anchored patterns still match.
--- Space is never wordy in the default quote pattern and never a
--- backslash in the default bracket pattern, so the substitution is safe.
---
---@param neigh_pattern string  Lua pattern, exactly 2 characters wide after anchoring
---@param before string         single char to the left of cursor, or ""
---@param after string          single char to the right of cursor, or ""
---@return boolean
function M.neigh_matches(neigh_pattern, before, after)
	if before == "" then
		before = " "
	end
	if after == "" then
		after = " "
	end
	return (before .. after):match("^" .. neigh_pattern .. "$") ~= nil
end

--- A pair is symmetric when its open and close characters are identical
--- (quotes, backticks). Symmetric pairs use `closeopen` as their single
--- action; asymmetric pairs split into `open` (on the opener) and `close`
--- (on the closer).
---
---@param spec Beast.Autopairs.Pair
---@param open_char string
---@return boolean
function M.is_symmetric(spec, open_char)
	return spec.close == open_char
end

--- Iterate `(open_char, spec)` over all configured pairs in deterministic
--- order. Sorted for stable test output and predictable mapping order.
---
---@param cfg Beast.Autopairs.Config
---@return fun(): string?, Beast.Autopairs.Pair?
function M.iter_active(cfg)
	local keys = {}
	for k in pairs(cfg.pairs) do
		keys[#keys + 1] = k
	end
	table.sort(keys)

	local i = 0
	return function()
		i = i + 1
		local k = keys[i]
		if k == nil then
			return nil
		end
		return k, cfg.pairs[k]
	end
end

return M
