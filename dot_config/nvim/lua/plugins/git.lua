return {
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("gitsigns").setup({
        signs = {
          add          = { text = "▎" },
          change       = { text = "▎" },
          delete       = { text = "▁" },
          topdelete    = { text = "▔" },
          changedelete = { text = "▎" },
        },
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns
          local map = function(mode, l, r, desc)
            vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
          end

          map("n", "]h", gs.next_hunk,               "Next hunk")
          map("n", "[h", gs.prev_hunk,               "Prev hunk")
          map("n", "<leader>hp", gs.preview_hunk,    "Preview hunk")
          map("n", "<leader>hr", gs.reset_hunk,      "Reset hunk")
          map("n", "<leader>hb", gs.toggle_current_line_blame, "Toggle blame")
        end,
      })
    end,
  },
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "Gdiffsplit", "Gread", "Gwrite", "Gclog" },
    keys = {
      { "<leader>gs", "<cmd>Git<cr>",          desc = "Git status" },
      { "<leader>gl", "<cmd>Git log<cr>",       desc = "Git log" },
      { "<leader>gd", "<cmd>Gdiffsplit<cr>",    desc = "Git diff split" },
      { "<leader>gb", "<cmd>Git blame<cr>",     desc = "Git blame" },
      { "<leader>gc", "<cmd>Git commit<cr>",    desc = "Git commit" },
      { "<leader>gp", "<cmd>Git push<cr>",      desc = "Git push" },
    },
  },
}
