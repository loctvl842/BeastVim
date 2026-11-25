---Which features are switched off for a big buffer. `false` keeps the feature on.
---@class Beast.Bigfile.Disable
---@field treesitter? boolean highlight, indentexpr and the sticky context
---@field indent? boolean indent guides and scope
---@field lsp? boolean language servers
---@field git? boolean hunk signs and blame
---@field breadcrumb? boolean winbar symbol trail (the file path stays)
---@field scroll? boolean smooth-scroll animation
---@field matchparen? boolean bracket-pair highlight
---@field fold? boolean folding falls back to manual
---@field conceal? boolean conceallevel 0
---@field signs? boolean statuscolumn shows line numbers only

---@class Beast.Bigfile.Config
---@field enabled? boolean master switch; false means no buffer is ever big
---@field notify? boolean show a toast when a big file opens
---@field size? integer bytes on disk above which a file is big
---@field line_length? integer average characters per line above which a file is big (minified files)
---@field disable? Beast.Bigfile.Disable
local defaults = {
	enabled = true,
	notify = true,
	size = 1.5 * 1024 * 1024,
	line_length = 1000,
	disable = {
		treesitter = true,
		indent = true,
		lsp = true,
		git = true,
		breadcrumb = true,
		scroll = true,
		matchparen = true,
		fold = true,
		conceal = true,
		signs = true,
	},
}

---@type Beast.Bigfile.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? Beast.Bigfile.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(string.format("beast.bigfile.config is read-only; cannot assign '%s' directly. Use setup() instead.", tostring(key)), 2)
	end,
})

return M
