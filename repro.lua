-- repro.lua
-- Run with: nvim -u repro.lua

-- Add current directory to runtime path
vim.opt.rtp:prepend(".")

-- Setup the plugin
require("ink").setup()

print("ink.nvim loaded! Try :InkOpen <epub_file>")
