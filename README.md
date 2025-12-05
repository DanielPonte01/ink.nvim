# ink.nvim

A minimalist, distraction-free EPUB reader for Neovim.

## Features
- Read EPUB files inside Neovim buffers
- Continuous scrolling per chapter
- Navigable table of contents
- Telescope integration for searching chapters and content
- Syntax-highlighted text rendered from HTML
- Progress tracking and restoration
- Image extraction and external viewing
- User highlights with customizable colors (persistent across sessions)
- Notes on highlights (add annotations to your highlights)
- Bookmarks with navigation (jump between bookmarks across chapters)
- Text justification (optional)
- Footnote preview with floating windows
- Library management (browse, search, track reading progress, search bookmarks)

## Requirements

- Neovim 0.7+
- `unzip` command (for extracting EPUB files)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for search and library features)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "DanielPonte01/ink.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",  -- Optional: for search features
  },
  config = function()
    require("ink").setup()
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "DanielPonte01/ink.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",  -- Optional: for search features
  },
  config = function()
    require("ink").setup()
  end
}
```

## Configuration

Create a configuration file (e.g., `~/.config/nvim/after/plugin/ink.lua`) with your settings.

Here's the complete default configuration with comments explaining each option:

```lua
require("ink").setup({
  -- Display settings
  focused_mode = true,    -- Enable focused reading mode
  image_open = true,      -- Allow opening images in external viewer
  justify_text = false,   -- Enable text justification (adds spaces between words)
  max_width = 120,        -- Maximum text width (for centering)
  width_step = 10,        -- How much to change width per keypress

  -- Navigation keymaps
  keymaps = {
    next_chapter = "]c",            -- Navigate to next chapter
    prev_chapter = "[c",            -- Navigate to previous chapter
    toggle_toc = "<leader>t",       -- Toggle table of contents sidebar
    activate = "<CR>",              -- Preview footnote or open image/TOC entry
    jump_to_link = "g<CR>",         -- Jump to link target (footnotes, cross-references)

    -- Search features (requires telescope.nvim)
    search_toc = "<leader>pit",           -- Search/filter chapters by name
    search_content = "<leader>pif",       -- Search text within all chapters
    search_mode_toggle = "<C-f>",         -- Toggle between TOC and content search

    -- Width adjustment
    width_increase = "<leader>+",   -- Increase text width
    width_decrease = "<leader>-",   -- Decrease text width
    width_reset = "<leader>=",      -- Reset text width to default

    -- Library (global keymaps)
    library = "<leader>eL",         -- Open library browser
    last_book = "<leader>el",       -- Open last read book
  },

  -- Highlight colors (customize with any hex colors you want)
  highlight_colors = {
    yellow = { bg = "#f9e2af", fg = "#000000" },
    green = { bg = "#a6e3a1", fg = "#000000" },
    red = { bg = "#f38ba8", fg = "#000000" },
    blue = { bg = "#89b4fa", fg = "#000000" },
    -- Add more colors: purple, orange, pink, etc.
    -- purple = { bg = "#cba6f7", fg = "#000000" },
  },

  -- Highlight keymaps (visual mode for adding, normal mode for removing)
  highlight_keymaps = {
    yellow = "<leader>hy",  -- Highlight selection in yellow
    green = "<leader>hg",   -- Highlight selection in green
    red = "<leader>hr",     -- Highlight selection in red
    blue = "<leader>hb",    -- Highlight selection in blue
    remove = "<leader>hd"   -- Remove highlight under cursor
    -- Add more colors: purple, orange, pink, etc.
    -- purple = "<leader>hp",    -- Highlight with your custom highlight
  },

  -- Note keymaps (for annotations on highlights)
  note_keymaps = {
    add = "<leader>na",           -- Add/edit note on highlight under cursor
    remove = "<leader>nd",        -- Remove note from highlight
    toggle_display = "<leader>nt" -- Toggle note display (off/indicator/expanded)
  },

  -- Bookmark keymaps
  bookmark_keymaps = {
    add = "<leader>ba",           -- Add/edit bookmark at paragraph
    remove = "<leader>bd",        -- Remove bookmark at paragraph
    next = "<leader>bn",          -- Go to next bookmark
    prev = "<leader>bp",          -- Go to previous bookmark
    list_all = "<leader>bl",      -- List all bookmarks (global)
    list_book = "<leader>bb",     -- List bookmarks in current book (global)
  },
  bookmark_icon = "📑"             -- Bookmark icon
})

-- Optional: Add a keymap to quickly open EPUB files
vim.keymap.set("n", "<leader>eo", ":InkOpen ", { desc = "Open EPUB file" })
vim.keymap.set("n", "<leader>le", ":InkEditLibrary", { desc = "Edit you library JSON file" })
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:InkOpen <path>` | Open an EPUB file |
| `:InkLibrary` | Browse library of previously opened books |
| `:InkLast` | Reopen last read book at saved position |
| `:InkEditLibrary` | Edit library.json file manually |
| `:InkBookmarks` | Browse all bookmarks (global) |
| `:InkBookmarksBook` | Browse bookmarks in current book |

### Default Keymaps

**Navigation:**
- `]c` - Next chapter
- `[c` - Previous chapter
- `<leader>t` - Toggle table of contents
- `<CR>` - Multiuse: Preview footnote (floating window), Open Image and go to TOC entry
- `g<CR>` - Jump to link target (footnotes, cross-references)

**Search (requires telescope.nvim):**
- `<leader>pit` - Search/filter chapters by name (shows all chapters with preview)
- `<leader>pif` - Search text within all chapters (live grep)
- `<C-f>` - Toggle between chapter search and content search (preserves search text)

**Width Adjustment:**
- `<leader>+` - Increase text width
- `<leader>-` - Decrease text width
- `<leader>=` - Reset text width to default

**Highlighting:**
- `<leader>hy` - Highlight selection in yellow (visual mode)
- `<leader>hg` - Highlight selection in green (visual mode)
- `<leader>hr` - Highlight selection in red (visual mode)
- `<leader>hb` - Highlight selection in blue (visual mode)
- `<leader>hd` - Remove highlight under cursor (normal mode)

**Notes (on highlights):**
- `<leader>na` - Add/edit note on highlight under cursor
- `<leader>nd` - Remove note from highlight
- `<leader>nt` - Toggle note display mode (off/indicator/expanded)

**Bookmarks:**
- `<leader>ba` - Add/edit bookmark at current paragraph
- `<leader>bd` - Remove bookmark at current paragraph
- `<leader>bn` - Go to next bookmark (across chapters)
- `<leader>bp` - Go to previous bookmark (across chapters)
- `<leader>bl` - List all bookmarks (global keymap)
- `<leader>bb` - List bookmarks in current book (global keymap)

**Library (global):**
- `<leader>eL` - Open library browser
- `<leader>el` - Open last read book

All keymaps can be customized in your configuration.

### Footnotes

ink.nvim supports footnotes in two ways:

1. **Preview** (`<CR>`): Shows footnote content in a floating window without leaving your place
2. **Jump** (`g<CR>`): Jumps to the footnote location; use `g<CR>` on the back-link to return

Footnotes are also displayed at the end of each chapter for reference.

### Library

The library tracks all books you've opened with metadata and reading progress:

**Features:**
- Browse all previously opened books
- Search by title or author (with Telescope)
- See reading progress and last opened time
- Preview shows: title, author, language, date, description, progress, path

**Telescope keymaps (in library picker):**
- `<CR>` - Open selected book
- `<C-d>` - Delete book from library
- `<C-e>` - Edit library.json file
- `<C-b>` - Switch to bookmarks view

**Storage:** `~/.local/share/nvim/ink.nvim/library.json`

### Bookmarks

Bookmarks allow you to mark important passages and navigate between them:

**Features:**
- Add bookmarks to any paragraph in a book
- Custom names for each bookmark
- Navigate between bookmarks across chapters
- Global search across all books or within current book
- Visual indicator above bookmarked paragraphs

**Telescope keymaps (in bookmarks picker):**
- `<CR>` - Jump to bookmark location
- `<C-d>` - Delete bookmark
- `<C-e>` - Edit bookmarks.json file
- `<C-f>` - Toggle between all bookmarks and current book bookmarks
- `<C-b>` - Switch to library view

**Storage:** `~/.local/share/nvim/ink.nvim/bookmarks.json`

### Notes

Notes allow you to annotate your highlights with additional text:

**Features:**
- Add notes to any highlight
- Three display modes: off, indicator (shows dot), expanded (shows full note)
- Notes persist across sessions
- Dynamic input window that resizes as you type

**Usage:**
1. Create a highlight on some text
2. Place cursor on the highlight
3. Press `<leader>na` to add/edit a note
4. Type your note and press `<Esc>` to save

**Storage:** Stored alongside highlights in `~/.local/share/nvim/ink.nvim/{book}_highlights.json`

### Search Features

The search features integrate with Telescope to provide powerful book navigation:

**Chapter Search (`<leader>pit`):**
- Shows all chapters immediately with previews
- Type to filter by chapter name
- Press `<CR>` to jump to selected chapter
- Press `<C-f>` to switch to content search

**Content Search (`<leader>pif`):**
- Live grep across all chapter content
- Type to search for text (shows results as you type)
- Press `<CR>` to jump to the exact line in that chapter
- Press `<C-f>` to switch back to chapter search

### Using Highlights

1. Enter visual mode (`v` or `V`)
2. Select text you want to highlight
3. Press a highlight keymap (e.g., `<leader>hy` for yellow)
4. To remove a highlight, place cursor on highlighted text and press `<leader>hd`

**Highlight Features:**
- **Persistent**: Saved across sessions
- **Book-specific**: Each EPUB has its own highlights
- **Non-destructive**: Don't modify the original EPUB file
- **Customizable**: Add unlimited colors in config

**Adding Custom Colors:**
You can add unlimited highlight colors by adding entries to both `highlight_colors` and `highlight_keymaps`:

## Testing

A comprehensive test EPUB (`ink-test.epub`) is included to demonstrate all features:

```vim
:InkOpen ink-test.epub
```

The test book includes:
- **Chapter 1**: Lists (ordered, unordered, nested), text formatting (bold, italic, underline, strikethrough), headings, horizontal rules
- **Chapter 2**: Code blocks, inline code, blockquotes (nested), definition lists
- **Chapter 3**: Links, anchors, images
- **Chapter 4**: User highlights documentation and examples
- **Chapter 5**: Notes feature documentation and examples
- **Chapter 6**: Bookmarks feature documentation and examples

## License
GPL-3.0
