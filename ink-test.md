# Introduction to Ink.nvim

Welcome to **Ink.nvim**, a *minimalist* EPUB and Markdown reader for Neovim.

This test document demonstrates all supported markdown features and reading capabilities.

---

## Features Overview

Ink.nvim supports:

1. Reading EPUB files
2. Reading Markdown files
3. Highlights and annotations
4. Bookmarks with navigation
5. Glossary system with relationships
6. Parallel notes (padnotes)
7. Collections and dashboard
8. Export functionality
9. Smart caching

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

# Chapter 4: Highlights, Notes, and Bookmarks

## Highlights

When you open this file with Ink.nvim, you can:

- Select text in visual mode
- Press `<leader>hy` for yellow highlight
- Press `<leader>hg` for green highlight
- Press `<leader>hr` for red highlight
- Press `<leader>hb` for blue highlight

## Changing Highlight Colors

Change the color of existing highlights without recreating them:

- Place cursor on a highlight
- Press `<leader>hcy` to change to yellow
- Press `<leader>hcg` to change to green
- Press `<leader>hcr` to change to red
- Press `<leader>hcb` to change to blue

This preserves any notes attached to the highlight!

## Notes on Highlights

After highlighting text, you can add annotations:

- Press `<leader>na` to add or edit a note
- Press `<leader>nd` to remove a note
- Press `<leader>nt` to toggle note display mode (off/indicator/expanded)

Notes are stored with timestamps and persist across sessions.

## Bookmarks

Navigate through the document with bookmarks:

- `<leader>ba` to add a bookmark at current paragraph
- `<leader>be` to edit bookmark name
- `<leader>bd` to remove bookmark
- `<leader>bn` to go to next bookmark
- `<leader>bp` to go to previous bookmark
- `<leader>bl` to list all bookmarks (global)
- `<leader>bb` to list bookmarks in current book

Multiple bookmarks can exist on the same paragraph!

---

# Chapter 5: Glossary System

The glossary system allows you to build a wiki-like knowledge base for your book.

## Adding Terms

Define important terms and concepts:

- Place cursor on a word
- Press `<leader>ga` to add to glossary
- Enter term, definition, and optional aliases

## Browsing and Previewing

- Press `<leader>gp` on a term to preview definition
- Press `<leader>gl` to browse all glossary terms
- Press `<leader>gt` to toggle glossary visibility

## Relationships

Define relationships between terms:

- `<leader>gg` - Show related terms
- `<leader>gG` - Visualize relationship graph

Relationship types:
- **see_also**: Related concepts
- **contrast**: Opposing ideas
- **broader**: Parent concept
- **narrower**: Child concept

All relationships sync bidirectionally!

## Auto-Detection

Once defined, terms are automatically detected and underlined in the text with an icon indicator. This helps you recognize important concepts while reading.

---

# Chapter 6: Parallel Notes (Padnotes)

Padnotes let you take chapter-specific notes in separate markdown files.

## Using Padnotes

- `<leader>pn` - Smart toggle (create/open/close/switch)
- `<leader>po` - Force open padnote for current chapter
- `<leader>pc` - Close and save current padnote
- `<leader>pa` - List all padnotes with preview

## Features

- One markdown file per chapter
- Auto-save every 2 minutes
- Preview in floating window
- Header includes book title and chapter info

Perfect for maintaining reading journals or study notes!

---

# Chapter 7: Collections and Dashboard

## Collections

Organize your books into collections:

- Create themed collections (Fiction, Non-Fiction, Technical, etc.)
- Add books to multiple collections
- Filter library view by collection

## Dashboard

Press `<leader>ed` to open the dashboard:

### Library Dashboard (default)

- Minimalist table view with pagination
- Shows: Title, Author, Collection, Last Read, Progress
- Filter by collection with `c` key
- Manage collections with `C` (create) and `D` (delete)
- Add/remove books from collections with `a`/`r`

### Statistics Dashboard

Toggle to stats with `s` key:

- Reading statistics (total, completed, in progress)
- Time tracking (total, weekly, monthly, daily average)
- Progress bars and completion rates
- Top collections

---

# Chapter 8: Export

Export your highlights, notes, bookmarks, and glossary.

## Interactive Export

Press `<leader>ex` or run `:InkExport`:

```vim
:InkExport md -bcg ~/exports/
```

## Export Flags

- `md` or `json` - Format
- `-b` - Include bookmarks
- `-c` - Include context around highlights
- `-g` - Include glossary terms

## Output

Markdown exports include:
- Book metadata
- Statistics (highlights, notes, bookmarks)
- Highlights grouped by chapter with colors
- Notes inline with highlights
- Bookmarks with text previews
- Glossary terms with definitions and relationships

Perfect for sharing your reading notes or creating study guides!

---

# Chapter 9: Cache Management

EPUBs are extracted to cache for faster loading.

## Cache Commands

- `:InkClearCache` - Interactive cache management UI
- `:InkClearCache --all` - Clear all cache (with confirmation)
- `:InkClearCache <slug>` - Clear specific book cache
- `:InkCacheInfo` - Show cache statistics

## Cache Structure

```
~/.local/share/nvim/ink.nvim/
├── cache/          # Temporary (safe to delete)
└── books/          # User data (never delete)
```

The cache automatically invalidates when EPUB files are modified.

---

# Chapter 10: Search and Navigation

## Search Features

Find content quickly:

- `<leader>pit` - Search chapter titles
- `<leader>pif` - Search full text across all chapters
- `<C-f>` - Toggle between search modes

Search is powered by Telescope with live previews!

## Table of Contents

Press `<leader>t` to toggle the table of contents sidebar.

Use `:InkRebuildTOC` or `<leader>tr` to rebuild TOC from headings if the EPUB has a malformed TOC.

## Chapter Navigation

- `]c` - Next chapter
- `[c` - Previous chapter

## Text Width

Adjust reading width for comfort:

- `<leader>+` - Increase width
- `<leader>-` - Decrease width
- `<leader>=` - Reset to default width

## Text Justification

Toggle text justification with `<leader>jt`.

Justification distributes spaces evenly across lines for a polished reading experience.

---

# Chapter 11: Library Management

## Opening Books

- `:InkOpen <path>` - Open EPUB or Markdown file
- `:InkLibrary` or `<leader>eL` - Browse library
- `:InkLast` or `<leader>el` - Open last read book

## Scanning Directories

Add multiple books at once:

```vim
:InkAddLibrary ~/Documents/Books
```

This scans the directory asynchronously and adds all EPUBs to your library.

## Library Features

- Automatic progress tracking
- Reading session history
- Metadata extraction (title, author, language, date)
- Search and filter with Telescope
- Status tracking (to-read, reading, completed)

---

# Conclusion

This document demonstrates all the features supported by Ink.nvim for both EPUB and Markdown files.

Try opening it with:

```vim
:InkOpen ink-test.md
```

Or test the EPUB version:

```vim
:InkOpen ink-test.epub
```

## Quick Tips

1. **Customize colors** - Add unlimited highlight colors in config
2. **Use glossary** - Build a knowledge base while reading
3. **Take padnotes** - Keep chapter-specific journals
4. **Export regularly** - Back up your annotations
5. **Organize collections** - Group books by theme or project

Enjoy your distraction-free reading experience!

**Happy Reading!**

