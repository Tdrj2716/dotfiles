return {
  -- auto-completion of parentheses
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      local autopairs = require("nvim-autopairs")
      autopairs.setup({
        check_ts = true, -- treesitter integration
        ts_config = {
          lua = { "string" }, -- disable in lua strings
          javascript = { "template_string" },
          typescript = { "template_string" },
        },
      })

      -- integration with cmp
      local cmp_autopairs = require("nvim-autopairs.completion.cmp")
      local cmp = require("cmp")
      cmp.event:on("confirm_done", cmp_autopairs.on_confirm_done())
    end,
  },
}