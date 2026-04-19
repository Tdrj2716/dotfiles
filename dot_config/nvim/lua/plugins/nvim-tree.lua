return {
  "nvim-tree/nvim-tree.lua",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    require("nvim-tree").setup({
      view = {
        width = 30,
        number = true,
        relativenumber = true,
      },
      filters = {
        dotfiles = false,
      },
      git = {
        enable = true,
        ignore = false,
      },
    })

    -- auto-open on startup
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = function(data)
        if vim.fn.isdirectory(data.file) == 1 then
          vim.cmd.cd(data.file)
        end
        require("nvim-tree.api").tree.open()
      end,
    })
  end,
  keys = {
    { "<leader>e", "<cmd>NvimTreeToggle<cr>",   desc = "Toggle file explorer" },
    { "<leader>E", "<cmd>NvimTreeFindFile<cr>", desc = "Find current file in explorer" },
  },
}
