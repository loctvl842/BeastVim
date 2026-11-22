---@type Beast.Packer.PluginSpec[]
return {
	{
		name = "lua",
		src = gh("BeastVim/lua.bvim"),
		lazy = { filetype = "lua" },
		config = function()
			require("lua").setup()
		end,
	},
	{
		name = "typescript",
		src = gh("BeastVim/typescript.bvim"),
		lazy = { filetype = { "javascript", "javascriptreact", "typescript", "typescriptreact" } },
		config = function()
			require("typescript").setup()
		end,
	},
	{
		name = "python",
		src = gh("BeastVim/python.bvim"),
		lazy = { filetype = "python" },
		config = function()
			require("python").setup()
		end,
	},
	{
		name = "cpp",
		src = gh("BeastVim/cpp.bvim"),
		lazy = { filetype = { "c", "cpp", "objc", "objcpp", "cuda" } },
		config = function()
			require("cpp").setup()
		end,
	},
	{
		name = "markdown",
		src = gh("BeastVim/markdown.bvim"),
		lazy = { filetype = "markdown" },
		config = function()
			require("markdown").setup()
		end,
	},
	{
		name = "json",
		src = gh("BeastVim/json.bvim"),
		lazy = { filetype = { "json", "jsonc" } },
		config = function()
			require("json").setup()
		end,
	},
}
