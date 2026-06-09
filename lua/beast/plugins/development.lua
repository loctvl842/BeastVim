---@type Beast.Packer.PluginSpec[]
return {
  {
    name = "lazydev.nvim",
    src = gh("folke/lazydev.nvim"),
    lazy = {
      filetype = "lua",
      cmd = "LazyDev",
    },
    config = function()
      require("lazydev").setup({
        library = {
          { path = "${3rd}/luv/library", words = { "vim%.uv" } },
          { path = "snacks.nvim", words = { "Snacks" } },
        },
      })
    end
  },
}
