--- Builds the GitHub search string sent for the prompt text.
--- The text is the user's query; we only add what GitHub's own pages imply:
--- the current repo as scope and newest-created-first order.

---@class Beast.Finder.Gh.Query
local M = {}

local SCOPE_KEYS = { repo = true, org = true, user = true }

---@alias Beast.Finder.Gh.Kind "pr"|"issue"

--- Prompt text a picker opens with (trailing space so the user can keep typing).
---@param kind Beast.Finder.Gh.Kind
---@return string
function M.default_text(kind)
	return kind == "pr" and "is:pr state:open " or "is:issue state:open "
end

--- Qualifier keys present in the text. A `key:` is only a qualifier at the start of a
--- whitespace-separated token; double quotes protect spaces inside a value.
---@param text string
---@return table<string, boolean>
local function keys(text)
	local found = {}
	local in_quote = false
	local token_start = true
	local i = 1
	while i <= #text do
		local c = text:sub(i, i)
		if c == '"' then
			in_quote = not in_quote
			token_start = false
		elseif c:match("%s") and not in_quote then
			token_start = true
		elseif token_start then
			-- A negated qualifier (`-repo:x`) excludes, it does not scope.
			local neg, key = text:match("^(%-?)([%w_]+):", i)
			if key and neg == "" then
				found[key:lower()] = true
			end
			token_start = false
		end
		i = i + 1
	end
	return found
end

---@param text string prompt text
---@param repo string "owner/name" of the current project
---@return string
function M.build(text, repo)
	local present = keys(text)
	local parts = { vim.trim(text) }
	local scoped = false
	for key in pairs(SCOPE_KEYS) do
		scoped = scoped or present[key] == true
	end
	if not scoped then
		parts[#parts + 1] = "repo:" .. repo
	end
	if not present.sort then
		parts[#parts + 1] = "sort:created-desc"
	end
	return vim.trim(table.concat(parts, " "))
end

return M
