---@class Beast.Git.PreviewConfig
---@field context_size? integer Lines of unchanged context shown around the hunk in the preview float (default 3)
---@field width? "full"|"fit" Float sizing: "full" (full width of current window) or "fit" (snug around content). Default "full".
---@field max_height? number Max float height. Integer = absolute rows, float in (0,1] = fraction of `vim.o.lines`. Default 0.4.
---@field adjacent_gap? integer Max unchanged lines between two hunks for them to be auto-merged in the preview. 0 = only touching hunks merge. Default 0.

---@class Beast.Git.BlameConfig
---@field enabled? boolean Master switch for current-line blame virt_text.
---@field delay_ms? integer Debounce window (ms) for cursor-driven blame updates.
---@field virt_text_pos? "eol"|"right_align" Where to anchor the virt_text. `right_align` falls back to `eol` when content would overflow.
---@field ignore_whitespace? boolean Pass `--ignore-whitespace` to git blame.
---@field formatter? string Format string for committed lines. Placeholders: <author>, <author_mail>, <author_time:%R>, <summary>, <abbrev_sha>.
---@field formatter_nc? string Format string for "Not Committed Yet" lines.
---@field max_summary_length? integer Truncate `<summary>` to N display cells with a `…` suffix. 0 disables. Default 50 (matches VSCode GitLens).
---@field use_focus? boolean Trigger updates on FocusGained as well.

---@class Beast.Git.Config
local defaults = {
	---@type integer Debounce window (ms) for on_lines re-diffs.
	debounce_ms = 200,

	---@type Beast.Git.PreviewConfig
	preview = {
		context_size = 3,
		width = "full",
		max_height = 0.4,
		adjacent_gap = 0,
	},

	---@type Beast.Git.BlameConfig
	blame = {
		enabled = true,
		delay_ms = 500,
		virt_text_pos = "eol",
		ignore_whitespace = false,
		formatter = "      <author>, <author_time:%R> • <summary>",
		formatter_nc = "      <author>",
		max_summary_length = 50,
		use_focus = true,
	},

	---@type string[] Filetypes that never attach.
	ft_ignore = {
		"help",
		"alpha",
		"dashboard",
		"lazy",
		"mason",
		"netrw",
		"NvimTree",
		"beast-explorer",
		"TelescopePrompt",
		"toggleterm",
		"trouble",
		"qf",
		"man",
		"checkhealth",
	},

	---@type string[] Buftypes that never attach.
	bt_ignore = {
		"nofile",
		"prompt",
		"quickfix",
		"terminal",
		"help",
	},
}

---@type Beast.Git.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Git.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

--- Mutate a config value at runtime. Necessary because the public
--- metatable below makes direct assignment an error (frozen surface),
--- but features like `toggle_current_line_blame` need to flip flags.
--- `path` is dot-separated, e.g. `"blame.enabled"`.
---@param path string
---@param value any
function methods.set(path, value)
	local parts = vim.split(path, ".", { plain = true })
	local node = cfg
	for i = 1, #parts - 1 do
		local key = parts[i]
		if type(node[key]) ~= "table" then
			error(string.format("beast.libs.git.config.set: '%s' is not a table at '%s'", path, key), 2)
		end
		node = node[key]
	end
	node[parts[#parts]] = value
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.libs.git.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
