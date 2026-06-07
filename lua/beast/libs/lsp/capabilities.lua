-- Capabilities composition for the LSP lib.
--
-- Base capabilities come from `vim.lsp.protocol.make_client_capabilities()`.
-- Completion plugins (blink.cmp, nvim-cmp, etc.) contribute additional caps
-- via `M.add(tbl_or_fn)`. Contributors are deep-merged in registration order
-- on every `M.get()` call so runtime additions are picked up.

local M = {}

---@alias Beast.LSP.CapabilitiesContrib table|fun(): table

---@type Beast.LSP.CapabilitiesContrib[]
M.contributors = {}

---Base capabilities table from Neovim core.
---@return table
function M.base()
	return vim.lsp.protocol.make_client_capabilities()
end

---Register a capabilities contribution. Accepts a table or a function
---returning a table. Functions are evaluated each time `get()` runs.
---@param contrib Beast.LSP.CapabilitiesContrib
function M.add(contrib)
	table.insert(M.contributors, contrib)
end

---Merged capabilities: base + all contributors (deep, force).
---@return table
function M.get()
	local merged = M.base()
	for _, contrib in ipairs(M.contributors) do
		local tbl = type(contrib) == "function" and contrib() or contrib
		if type(tbl) == "table" then
			merged = vim.tbl_deep_extend("force", merged, tbl)
		end
	end
	return merged
end

return M
