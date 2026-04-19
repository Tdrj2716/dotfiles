return {
  -- Mason for installing LSP servers
  {
    "williamboman/mason.nvim",
    config = function()
      require("mason").setup()
    end,
  },
  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "ts_ls",   -- TypeScript Language Server
          "pyright", -- Python
        },
        automatic_installation = true,
      })
    end,
  },

  -- LSP settings (native vim.lsp.config for Neovim 0.11+)
  {
    "hrsh7th/cmp-nvim-lsp",
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- TypeScript Language Server
      vim.lsp.config("ts_ls", {
        capabilities = capabilities,
      })

      -- Python Language Server
      vim.lsp.config("pyright", {
        capabilities = capabilities,
      })

      -- Enable LSP servers
      vim.lsp.enable("ts_ls")
      vim.lsp.enable("pyright")

      -- LSP keybindings (applies to all LSP servers)
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf, noremap = true, silent = true }
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        end,
      })
    end,
  },
}