--- Builds the GitHub search string sent for the prompt text.
--- The text is the user's query; we only add what GitHub's own pages imply:
--- the current repo as scope and newest-created-first order.

---@class Beast.Finder.Gh.Query
local M = {}

local SCOPE_KEYS = { "repo", "org", "user" }

---@alias Beast.Finder.Gh.Kind "pr"|"issue"

--- Prompt text a picker opens with (trailing space so the user can keep typing).
---@param kind Beast.Finder.Gh.Kind
---@return string
function M.default_text(kind)
	return kind == "pr" and "is:pr state:open " or "is:issue state:open "
end

--- Split on whitespace; double quotes protect spaces inside a value.
---@param text string
---@return string[]
local function tokens(text)
	local out, cur, in_quote = {}, {}, false
	for c in text:gmatch(".") do
		if c == '"' then
			in_quote = not in_quote
			cur[#cur + 1] = c
		elseif c:match("%s") and not in_quote then
			if #cur > 0 then
				out[#out + 1] = table.concat(cur)
				cur = {}
			end
		else
			cur[#cur + 1] = c
		end
	end
	if #cur > 0 then
		out[#out + 1] = table.concat(cur)
	end
	return out
end

M.tokens = tokens

--- First value of each `key:value` qualifier (keys lowercased). Only a token that starts with
--- `key:` is a qualifier; a negated one (`-repo:x`) excludes, it does not scope.
---@param text string
---@return table<string, string>
local function qualifiers(text)
	local found = {}
	for _, token in ipairs(tokens(text)) do
		local neg, key, value = token:match("^(%-?)([%w_]+):(.*)$")
		if key and neg == "" then
			key = key:lower()
			found[key] = found[key] or value
		end
	end
	return found
end

--- What the search is limited to: the text's own `repo:` / `org:` / `user:`, else the current repo.
---@param text string prompt text
---@param repo string "owner/name" of the current project
---@return string
function M.scope(text, repo)
	local found = qualifiers(text)
	for _, key in ipairs(SCOPE_KEYS) do
		if found[key] and found[key] ~= "" then
			return found[key]
		end
	end
	return repo
end

---@param text string prompt text
---@param repo string "owner/name" of the current project
---@return string
function M.build(text, repo)
	local found = qualifiers(text)
	local parts = { vim.trim(text) }
	local scoped = false
	for _, key in ipairs(SCOPE_KEYS) do
		scoped = scoped or found[key] ~= nil
	end
	if not scoped then
		parts[#parts + 1] = "repo:" .. repo
	end
	if not found.sort then
		parts[#parts + 1] = "sort:created-desc"
	end
	return vim.trim(table.concat(parts, " "))
end

return M
