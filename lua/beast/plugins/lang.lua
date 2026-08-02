---@type Beast.Packer.PluginSpec[]
return {
  {
    name = "lua_ls",
    src = gh("BeastVim/lua_ls"),
    lazy = { filetype = "lua" },
    config = function() require("lua_ls").setup() end,
  }
}
