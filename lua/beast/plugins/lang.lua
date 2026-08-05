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
  }
}
