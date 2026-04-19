return {
  {
    "catgoose/nvim-colorizer.lua",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      filetypes = { "*" },
      user_default_options = {
        RGB = true,           -- #RGB
        RRGGBB = true,        -- #RRGGBB
        RRGGBBAA = true,      -- #RRGGBBAA
        names = false,        -- skip named colors like "Blue"
        rgb_fn = true,        -- rgb() and rgba()
        hsl_fn = true,        -- hsl() and hsla()
        css = true,
        css_fn = true,
        mode = "background",  -- show color as background highlight
        virtualtext = "■",
        always_update = false,
      },
    },
  },
}
