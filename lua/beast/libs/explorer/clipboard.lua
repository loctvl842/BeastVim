local M = {}

-- The "+" register is the system clipboard (wired via `unnamedplus`/OSC52 in
-- option.lua), so writing here is what makes copy/cut reach other Neovim
-- sessions. Payload shape: marked paths, one per line, followed by a final
-- "copy"/"cut" line. Anything that doesn't end in that marker line is
-- treated as belonging to someone else (plain text, another app's copy)
-- rather than an explorer clipboard. Paths are assumed newline-free, same
-- assumption the rest of the explorer already makes for filesystem paths.
local REG = "+"

-- Over SSH without a local display, option.lua wires "+" to an OSC52
-- provider whose paste() is intentionally a no-op (most terminals refuse to
-- answer the OSC52 query) — it always returns "", even for a value this same
-- process just wrote a moment ago via setreg(). Querying that register is
-- pointless and, worse, its paste() also fires a "use the terminal's native
-- paste" warning notify on every call. In that one environment, fall back to
-- this session's own last write instead of asking a register that can never
-- honestly answer — that's what keeps same-session copy/cut/paste working
-- there, same as it does everywhere else; cross-session sync simply isn't
-- reachable in that environment, consistent with option.lua's own comment.
---@return boolean
local function provider_can_query()
	return not (vim.g.clipboard and vim.g.clipboard.name == "OSC 52")
end

---@type Beast.Explorer.Clipboard?
local last_local = nil

---@param paths string[]
---@param mode "copy"|"cut"
---@return string
local function encode(paths, mode)
	return table.concat(paths, "\n") .. "\n" .. mode
end

---@param text string?
---@return Beast.Explorer.Clipboard?
local function decode(text)
	-- stylua: ignore
	if not text or text == "" then return nil end

	-- Some clipboard providers/terminals round-trip a trailing newline
	-- (tmux, OSC52) — strip it so it doesn't get parsed as an empty path.
	local lines = vim.split(text:gsub("\n+$", ""), "\n", { plain = true })
	local mode = lines[#lines]
	-- stylua: ignore
	if mode ~= "copy" and mode ~= "cut" then return nil end

	table.remove(lines, #lines)
	-- stylua: ignore
	if #lines == 0 then return nil end

	for _, path in ipairs(lines) do
		-- stylua: ignore
		if path == "" then return nil end
	end

	return { paths = lines, mode = mode }
end

---@param paths string[]
---@param mode "copy"|"cut"
function M.write(paths, mode)
	vim.fn.setreg(REG, encode(paths, mode))
	last_local = { paths = paths, mode = mode }
end

function M.clear()
	vim.fn.setreg(REG, "")
	last_local = nil
end

---@return Beast.Explorer.Clipboard?
function M.read()
	if not provider_can_query() then
		return last_local
	end
	return decode(vim.fn.getreg(REG))
end

--- Marks `paths` with `mode`, unless the clipboard already holds a pending
--- entry with that same mode, in which case it clears it instead.
---@param paths string[]
---@param mode "copy"|"cut"
---@return Beast.Explorer.Clipboard?
function M.toggle(paths, mode)
	local current = M.read()
	if current and current.mode == mode then
		M.clear()
		return nil
	end

	M.write(paths, mode)
	return { paths = paths, mode = mode }
end

return M
