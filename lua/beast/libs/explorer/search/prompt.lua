--- Prompt of search mode: the query line at the top of the explorer is the input.
--- Keys are read one by one (`getcharstr`), so there is no cmdline and no insert
--- mode involved; the caller repaints the query line on every change.
local M = {}

-- getcharstr() encodes special keys as "\x80" sequences: <BS> is "\x80kb".
local BACKSPACE = { "\x80kb", "\x08", "\x7f" }

---@param text string
---@return string
local function delete_word(text)
	return (text:gsub("%s*[^%s]*$", ""))
end

--- Read a query. Editing keys: printable characters, <BS>, <C-w> (word), <C-u> (all).
--- <Enter> confirms, <Esc> / <C-c> cancels.
---@param default string text the prompt starts with
---@param on_change fun(text: string) called after every edit
---@return string|nil text confirmed text, or nil when cancelled
function M.ask(default, on_change)
	local text = default
	while true do
		local ok, key = pcall(vim.fn.getcharstr)
		if not ok or key == "\27" or key == "\3" then
			return nil
		elseif key == "\r" or key == "\n" then
			return text
		end

		local before = text
		if vim.tbl_contains(BACKSPACE, key) then
			text = vim.fn.strcharpart(text, 0, math.max(vim.fn.strchars(text) - 1, 0))
		elseif key == "\x17" then
			text = delete_word(text)
		elseif key == "\x15" then
			text = ""
		elseif key:byte(1) >= 32 and key:byte(1) ~= 0x7f and key:byte(1) ~= 0x80 then
			text = text .. key
		end

		if text ~= before then
			on_change(text)
		end
	end
end

return M
