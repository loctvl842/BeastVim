---@type Beast.Packer.PluginSpec[]
return {
  {
    name = "lua_ls",
    src = gh("BeastVim/lua_ls"),
    lazy = { filetype = "lua" },
    config = function() require("lua_ls").setup() end,
  },
  {
    name = "typescript",
    src = gh("BeastVim/typescript"),
    lazy = { filetype = { "javascript", "javascriptreact", "typescript", "typescriptreact" } },
    config = function() require("typescript").setup() end,
  },
  {
    name = "python",
    src = gh("BeastVim/python"),
    lazy = { filetype = "python" },
    config = function() require("python").setup() end,
  },
  {
    name = "cpp",
    src = gh("BeastVim/cpp"),
    lazy = { filetype = { "c", "cpp", "objc", "objcpp", "cuda" } },
    config = function() require("cpp").setup() end,
  },
  {
    name = "markdown",
    -- Local clone while the plugin is unpublished; switch to gh("BeastVim/markdown") once pushed.
    src = "/Users/loctvl842/Documents/Beast/Developments/neovim_plugins/markdown",
    lazy = { filetype = "markdown" },
    config = function() require("markdown").setup() end,
  },
  {
    name = "json",
    src = gh("BeastVim/json"),
    lazy = { filetype = { "json", "jsonc" } },
    config = function() require("json").setup() end,
  },
}
