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

## Requirements

- Neovim 0.7+
- `unzip` command (for extracting EPUB files)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for search features)

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
  focused_mode = true,  -- Enable focused reading mode
  image_open = true,    -- Allow opening images in external viewer
  max_width = 120,      -- Maximum text width (for centering)

  -- Navigation keymaps
  keymaps = {
    next_chapter = "]c",            -- Navigate to next chapter
    prev_chapter = "[c",            -- Navigate to previous chapter
    toggle_toc = "<leader>t",       -- Toggle table of contents sidebar
    activate = "<CR>",              -- Activate link/image or jump to TOC entry

    -- Search features (requires telescope.nvim)
    search_toc = "<leader>pit",           -- Search/filter chapters by name
    search_content = "<leader>pif",       -- Search text within all chapters
    search_mode_toggle = "<C-f>",         -- Toggle between TOC and content search
  },

  -- Highlight colors (customize with any hex colors you want)
  highlight_colors = {
    yellow = { bg = "#f9e2af", fg = "#000000" },
    green = { bg = "#a6e3a1", fg = "#000000" },
    red = { bg = "#f38ba8", fg = "#000000" },
    blue = { bg = "#89b4fa", fg = "#000000" },
    -- Add more colors: purple, orange, pink, etc.
    -- purple = { bg = "#cba6f7", fg = "#000000" },  -- Add custom purple
    -- orange = { bg = "#fab387", fg = "#000000" },  -- Add custom orange
  },

  -- Highlight keymaps (visual mode for adding, normal mode for removing)
  highlight_keymaps = {
    yellow = "<leader>hy",  -- Highlight selection in yellow
    green = "<leader>hg",   -- Highlight selection in green
    red = "<leader>hr",     -- Highlight selection in red
    blue = "<leader>hb",    -- Highlight selection in blue
    remove = "<leader>hd"   -- Remove highlight under cursor
    -- Add keymaps for any custom colors you defined above
   -- purple = "<leader>hp",  -- Keymap for purple
   -- orange = "<leader>ho",  -- Keymap for orange
  }
})

-- Optional: Add a keymap to quickly open EPUB files
vim.keymap.set("n", "<leader>eo", ":InkOpen ", { desc = "Open EPUB file" })
```

## Usage

### Opening a Book

```vim
:InkOpen <path/to/book.epub>
```

Or use tab completion:

```vim
:InkOpen <Tab>
```

### Default Keymaps

**Navigation:**
- `]c` - Next chapter
- `[c` - Previous chapter
- `<leader>t` - Toggle table of contents
- `<CR>` - Jump to chapter (in TOC) or open image (in content)

**Search (requires telescope.nvim):**
- `<leader>pit` - Search/filter chapters by name (shows all chapters with preview)
- `<leader>pif` - Search text within all chapters (live grep)
- `<C-f>` - Toggle between chapter search and content search (preserves search text)

**Highlighting:**
- `<leader>hy` - Highlight selection in yellow (visual mode)
- `<leader>hg` - Highlight selection in green (visual mode)
- `<leader>hr` - Highlight selection in red (visual mode)
- `<leader>hb` - Highlight selection in blue (visual mode)
- `<leader>hd` - Remove highlight under cursor (normal mode)

All keymaps can be customized in your configuration.

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

**Workflow Example:**
```
<leader>pit         → Opens TOC list
Type "introduction" → Filters to matching chapters
<C-f>              → Switches to content search with "introduction"
Edit to "chapter 1" → Searches for that text
<CR>               → Jumps to first match
```

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

## License
GPL-3.0
