-- disable netrw (required before nvim-tree loads)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- basic settings
vim.opt.number = true          -- show line numbers
vim.opt.relativenumber = true  -- show relative line numbers
vim.opt.expandtab = true       -- use spaces instead of tabs
vim.opt.shiftwidth = 2         -- indent width
vim.opt.tabstop = 2            -- tab width
vim.opt.smartindent = true     -- smart indent
vim.opt.wrap = false           -- no line wrapping
vim.opt.cursorline = true      -- highlight current line
vim.opt.termguicolors = true   -- enable 24-bit colors
vim.opt.signcolumn = "yes"     -- always show sign column
vim.opt.updatetime = 300       -- reduce update time
vim.opt.completeopt = "menu,menuone,noselect"

-- clipboard sync
vim.opt.clipboard = "unnamedplus"

-- search settings
vim.opt.ignorecase = true
vim.opt.smartcase = true
