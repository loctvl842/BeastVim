-- Capabilities composition for the LSP lib.
--
-- Base capabilities come from `vim.lsp.protocol.make_client_capabilities()`.
-- Completion plugins (blink.cmp, nvim-cmp, etc.) contribute additional caps
-- via `M.add(tbl_or_fn)`. Contributors are deep-merged in registration order
-- on every `M.get()` call so runtime additions are picked up.

local M = {}

---@alias Beast.Lsp.CapabilitiesContrib table|fun(): table

---@type Beast.Lsp.CapabilitiesContrib[]
M.contributors = {}

---Set true by the dispatcher on the first LspAttach. Used by `M.add` to
---warn callers that contributors added after this point won't reach
---already-connected clients.
M.first_client_seen = false

---Base capabilities table from Neovim core.
---@return table
function M.base()
	return vim.lsp.protocol.make_client_capabilities()
end

---Register a capabilities contribution. Accepts a table or a function
---returning a table. Functions are evaluated each time `get()` runs.
---@param contrib Beast.Lsp.CapabilitiesContrib
function M.add(contrib)
	table.insert(M.contributors, contrib)
	if M.first_client_seen then
		vim.notify(
			"beast.libs.lsp: capabilities contributor added after a client connected; "
				.. "already-attached clients won't see it (servers started later still will, via before_init). "
				.. "Register contributors before the first LspAttach (typically in beast/init.lua).",
			vim.log.levels.WARN
		)
	end
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
