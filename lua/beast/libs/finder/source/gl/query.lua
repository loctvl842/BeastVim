--- Turns the prompt text of the GitLab pickers into the parameters of one list request.
--- GitLab has no search-box syntax, so the text holds `flag:value` pairs and free words: the pairs become
--- request parameters, the words become the `search` text, `project:` chooses another project.

---@class Beast.Finder.Gl.Query
local M = {}

local tokens = require("beast.libs.finder.source.gh.query").tokens

---@alias Beast.Finder.Gl.Kind "mr"|"issue"

---@class Beast.Finder.Gl.Parsed
---@field params? table<string, string> request parameters; a value of "@me" is the logged-in user, resolved by the api
---@field project? string path of another project (`project:`)
---@field words? string free words, sent as `search`
---@field users? { flag: string, name: string }[] usernames the text names, to explain an empty answer
---@field error? string what is wrong with the text; no request is made
---@field hint? string more lines for `error`, joined with "\n"

--- Prompt text a picker opens with (trailing space so the user can keep typing).
---@param _ Beast.Finder.Gl.Kind
---@return string
function M.default_text(_)
	return "state:opened "
end

local STATES = { open = "opened", opened = "opened", closed = "closed", merged = "merged", all = "all" }
local DRAFT = { yes = "yes", ["true"] = "yes", no = "no", ["false"] = "no" }
local ORDER = { created = "created_at", updated = "updated_at" }

--- Flags in the order they are listed to the user; `mr` marks the ones that only apply to merge requests.
local FLAGS = {
	{ "state" },
	{ "author" },
	{ "assignee" },
	{ "reviewer", mr = true },
	{ "label" },
	{ "milestone" },
	{ "draft", mr = true },
	{ "source", mr = true },
	{ "target", mr = true },
	{ "sort" },
	{ "project" },
}

---@param kind Beast.Finder.Gl.Kind
---@return table<string, boolean>
local function applicable(kind)
	local set = {}
	for _, flag in ipairs(FLAGS) do
		set[flag[1]] = not flag.mr or kind == "mr"
	end
	return set
end

-- Message rows do not wrap, so the list of flags is broken into lines this wide.
local HINT_WIDTH = 46

--- "Available: state, author, ..." as lines of at most `HINT_WIDTH` columns, joined with "\n".
---@param kind Beast.Finder.Gl.Kind
---@return string
local function available(kind)
	local lines, line = {}, "Available:"
	local names = {}
	for _, flag in ipairs(FLAGS) do
		if not flag.mr or kind == "mr" then
			names[#names + 1] = flag[1]
		end
	end
	for i, name in ipairs(names) do
		local word = i < #names and (name .. ",") or name
		if #line + 1 + #word > HINT_WIDTH then
			lines[#lines + 1] = line
			line = " "
		end
		line = line .. " " .. word
	end
	lines[#lines + 1] = line
	return table.concat(lines, "\n")
end

---@param value string
---@return string
local function unquote(value)
	return (value:gsub('"', ""))
end

---@param kind Beast.Finder.Gl.Kind
---@param text string prompt text
---@return Beast.Finder.Gl.Parsed
function M.parse(text, kind)
	local ok_flags = applicable(kind)
	local params, words, users, labels = {}, {}, {}, {}
	local project ---@type string?

	---@param flag string
	---@param value string
	---@return string? err
	local function set(flag, value)
		if value == "" then
			return ('"%s:" needs a value'):format(flag)
		end
		if flag == "state" then
			local state = STATES[value:lower()]
			if not state or (state == "merged" and kind == "issue") then
				return ('"%s" is not a valid value for state:'):format(value)
			end
			params.state = state
		elseif flag == "author" then
			params.author_username = value
		elseif flag == "assignee" then
			if value:lower() == "none" then
				params.assignee_id = "None"
			else
				params.assignee_username = value
			end
		elseif flag == "reviewer" then
			if value:lower() == "none" then
				params.reviewer_id = "None"
			else
				params.reviewer_username = value
			end
		elseif flag == "label" then
			labels[#labels + 1] = value
		elseif flag == "milestone" then
			params.milestone = value
		elseif flag == "draft" then
			local draft = DRAFT[value:lower()]
			if not draft then
				return ('"%s" is not a valid value for draft: (yes or no)'):format(value)
			end
			params.draft = draft
		elseif flag == "source" then
			params.source_branch = value
		elseif flag == "target" then
			params.target_branch = value
		elseif flag == "sort" then
			local field, dir = value:lower():match("^(%a+)(-?%a*)$")
			if not ORDER[field or ""] or (dir ~= "" and dir ~= "-asc") then
				return ('"%s" is not a valid value for sort: (created or updated, optionally with -asc)'):format(value)
			end
			params.order_by = ORDER[field]
			params.sort = dir == "-asc" and "asc" or "desc"
		elseif flag == "project" then
			project = value
		end
	end

	for _, token in ipairs(tokens(text)) do
		local flag, value = token:match("^(%a+):(.*)$")
		if flag then
			flag = flag:lower()
			if not ok_flags[flag] then
				return { error = ('Unknown filter "%s:".'):format(flag), hint = available(kind) }
			end
			value = unquote(value)
			local err = set(flag, value)
			if err then
				return { error = err }
			end
			if (flag == "author" or flag == "assignee" or flag == "reviewer") and value:lower() ~= "none" and value ~= "@me" then
				users[#users + 1] = { flag = flag, name = value }
			end
		else
			words[#words + 1] = unquote(token)
		end
	end

	if #labels > 0 then
		params.labels = labels[1]:lower() == "none" and "None" or table.concat(labels, ",")
	end
	if #words > 0 then
		params.search = table.concat(words, " ")
		if kind == "issue" then
			params["in"] = "title,description"
		end
	end
	params.state = params.state or "opened"
	return { params = params, project = project, words = params.search, users = users }
end

--- What the search is limited to, for the title bar: the text's own `project:`, else the current project.
---@param text string prompt text
---@param slug string path of the current project
---@return string
function M.scope(text, slug)
	for _, token in ipairs(tokens(text)) do
		local value = token:match("^[pP][rR][oO][jJ][eE][cC][tT]:(.+)$")
		if value then
			return unquote(value)
		end
	end
	return slug
end

return M
