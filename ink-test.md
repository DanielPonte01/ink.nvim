# Introduction to Ink.nvim

Welcome to **Ink.nvim**, a *minimalist* EPUB and Markdown reader for Neovim.

This test document demonstrates all supported markdown features.

---

## Features Overview

Ink.nvim supports:

1. Reading EPUB files
2. Reading Markdown files
3. Highlights and annotations
4. Bookmarks
5. Export functionality

### Key Benefits

- **Distraction-free** reading experience
- *Fast* and lightweight
- ~~No heavy dependencies~~
- Built with `Lua` for Neovim

---

# Chapter 1: Text Formatting

## Bold and Italic

You can use **bold text** with double asterisks or __double underscores__.

You can use *italic text* with single asterisks or _single underscores_.

You can even combine them: ***bold and italic*** or ___bold and italic___.

## Strikethrough

Use ~~strikethrough~~ for deleted text.

## Code

Inline code works with `backticks`, like `local foo = "bar"`.

## Links and Images

Here's a [link to the repository](https://github.com/DanielPonte01/ink.nvim).

Internal links work too: [Jump to Chapter 2](#chapter-2-lists-and-blockquotes).

---

# Chapter 2: Lists and Blockquotes

## Unordered Lists

Shopping list:

- Apples
- Bananas
- Oranges
  - Navel oranges
  - Blood oranges
- Grapes

## Ordered Lists

Steps to install:

1. Install Neovim
2. Install a plugin manager
3. Add Ink.nvim to your config
4. Run `:InkOpen test.md`

## Mixed Lists

- First item
  1. Nested ordered
  2. Another ordered
- Second item
  - Nested unordered

## Blockquotes

Simple quote:

> This is a blockquote.
> It can span multiple lines.

Nested quote:

> Level 1 quote
> > Level 2 quote
> > > Level 3 quote

---

# Chapter 3: Code Blocks

## Simple Code Block

```
function hello()
  print("Hello, World!")
end
```

## Lua Code

```lua
local M = {}

function M.setup(opts)
  -- Configuration
  vim.notify("Setup complete!")
end

return M
```

## Horizontal Rules

Three ways to create horizontal rules:

---

***

___

All create the same separator.

---

# Chapter 4: Advanced Features

## Highlights

When you open this file with Ink.nvim, you can:

- Select text in visual mode
- Press `<leader>hy` for yellow highlight
- Press `<leader>hg` for green highlight
- Press `<leader>hr` for red highlight
- Press `<leader>hb` for blue highlight

## Notes

After highlighting text, you can:

- Press `<leader>na` to add a note
- Press `<leader>nd` to remove a note
- Press `<leader>nt` to toggle note display

## Bookmarks

Navigate through the document with bookmarks:

- `<leader>ba` to add a bookmark
- `<leader>bn` to go to next bookmark
- `<leader>bp` to go to previous bookmark
- `<leader>bl` to list all bookmarks

## Search

Find content quickly:

- `<leader>pit` to search chapter titles
- `<leader>pif` to search full text
- `<C-f>` to toggle search mode

---

# Chapter 5: Navigation

## Table of Contents

Press `<leader>t` to toggle the table of contents sidebar.

## Chapter Navigation

- `]c` to go to next chapter
- `[c` to go to previous chapter

## Text Width

Adjust reading width:

- `<leader>+` to increase width
- `<leader>-` to decrease width
- `<leader>=` to reset width

## Text Justification

Toggle text justification with `<leader>jt`.

---

# Conclusion

This document demonstrates all the features supported by Ink.nvim's Markdown parser.

Try opening it with:

```vim
:InkOpen test-markdown.md
```

Enjoy your reading experience!

**Happy Reading!**
