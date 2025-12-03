# ink.nvim

A minimalist, distraction-free EPUB reader for Neovim.

## Features
- Read EPUB files inside Neovim buffers
- Continuous scrolling per chapter
- Navigable table of contents
- Syntax-highlighted text rendered from HTML
- Progress tracking and restoration
- Image extraction and external viewing
- User highlights with customizable colors (persistent across sessions)

## Requirements

- Neovim 0.7+
- `unzip` command (for extracting EPUB files)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "DanielPonte01/ink.nvim",
  config = function()
    require("ink").setup({
      -- Optional configuration (these are the defaults)
      focused_mode = true,
      image_open = true,
      max_width = 120,
      keymaps = {
        next_chapter = "]c",
        prev_chapter = "[c",
        toggle_toc = "<leader>t",
        activate = "<CR>"
      },
      highlight_colors = {
        yellow = { bg = "#fabd2f", fg = "#000000" },
        green = { bg = "#b8bb26", fg = "#000000" },
        red = { bg = "#fb4934", fg = "#000000" }
      },
      highlight_keymaps = {
        yellow = "<leader>hy",
        green = "<leader>hg",
        red = "<leader>hr",
        remove = "<leader>hd"
      }
    })
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "DanielPonte01/ink.nvim",
  config = function()
    require("ink").setup({
      -- Optional configuration (these are the defaults)
      focused_mode = true,
      image_open = true,
      max_width = 120,
      keymaps = {
        next_chapter = "]c",
        prev_chapter = "[c",
        toggle_toc = "<leader>t",
        activate = "<CR>"
      },
      highlight_colors = {
        yellow = { bg = "#fabd2f", fg = "#000000" },
        green = { bg = "#b8bb26", fg = "#000000" },
        red = { bg = "#fb4934", fg = "#000000" }
      },
      highlight_keymaps = {
        yellow = "<leader>hy",
        green = "<leader>hg",
        red = "<leader>hr",
        remove = "<leader>hd"
      }
    })
  end
}
```

## Configuration

### Default Configuration

```lua
require("ink").setup({
  focused_mode = true,
  image_open = true,
  max_width = 120,
  keymaps = {
    next_chapter = "]c",      -- Navigate to next chapter
    prev_chapter = "[c",       -- Navigate to previous chapter
    toggle_toc = "<leader>t",  -- Toggle table of contents
    activate = "<CR>"          -- Activate link/image or TOC entry
  },
  highlight_colors = {
    yellow = { bg = "#fabd2f", fg = "#000000" },  -- Yellow highlight
    green = { bg = "#b8bb26", fg = "#000000" },   -- Green highlight
    red = { bg = "#fb4934", fg = "#000000" }      -- Red highlight
  },
  highlight_keymaps = {
    yellow = "<leader>hy",    -- Highlight selection in yellow (visual mode)
    green = "<leader>hg",     -- Highlight selection in green (visual mode)
    red = "<leader>hr",       -- Highlight selection in red (visual mode)
    remove = "<leader>hd"     -- Remove highlight under cursor (normal mode)
  }
})
```

**Note:** You can add as many custom colors as you want! Just add them to both `highlight_colors` and `highlight_keymaps` with any color name you choose.

### Sample Configuration with Custom Colors

Here's a more complete example showing custom colors. You can add unlimited colors with any names you want:

```lua
require("ink").setup({
  focused_mode = true,
  image_open = true,
  max_width = 100,
  keymaps = {
    next_chapter = "<C-j>",    -- Custom: use Ctrl+j for next chapter
    prev_chapter = "<C-k>",    -- Custom: use Ctrl+k for previous chapter
    toggle_toc = "<leader>e",  -- Custom: use <leader>e instead of <leader>t
    activate = "<CR>"          -- Keep default Enter key
  },
  highlight_colors = {
    yellow = { bg = "#ffeb3b", fg = "#000000" },    -- Custom yellow
    green = { bg = "#8bc34a", fg = "#ffffff" },     -- Custom green
    red = { bg = "#f44336", fg = "#ffffff" },       -- Custom red
    blue = { bg = "#2196f3", fg = "#ffffff" },      -- Add custom blue
    purple = { bg = "#9c27b0", fg = "#ffffff" }     -- Add custom purple
  },
  highlight_keymaps = {
    yellow = "<leader>hy",
    green = "<leader>hg",
    red = "<leader>hr",
    blue = "<leader>hb",       -- Custom blue keymap
    purple = "<leader>hp",     -- Custom purple keymap
    remove = "<leader>hd"
  }
})

vim.keymap.set("n", "<leader>eo", ":InkOpen ", { desc = "Open EPUB file" })

```

## Usage

- `:InkOpen <path/to/book.epub>`: Open an EPUB file.

### Default Keymaps

**Navigation:**
- `]c`: Next chapter
- `[c`: Previous chapter
- `<leader>t`: Toggle TOC
- `<CR>`: In TOC, jump to chapter; on image, open in viewer

**Highlighting:**
- `<leader>hy`: Highlight selection in yellow (visual mode)
- `<leader>hg`: Highlight selection in green (visual mode)
- `<leader>hr`: Highlight selection in red (visual mode)
- `<leader>hd`: Remove highlight under cursor (normal mode)

All keymaps are customizable through the `setup()` configuration (see Configuration section above).

### Using Highlights

1. Enter visual mode (`v` or `V`)
2. Select text you want to highlight
3. Press a highlight keymap (e.g., `<leader>hy` for yellow)
4. To remove a highlight, place cursor on highlighted text and press `<leader>hd`

Highlights are:
- **Persistent**: Saved across sessions
- **Book-specific**: Each EPUB has its own highlights
- **Non-destructive**: Don't modify the original EPUB file
- **Customizable**: Add your own colors and keymaps in config

## Testing

A comprehensive test EPUB (`ink-test.epub`) is included to demonstrate all features:

The test book includes:
- **Chapter 1**: Lists (ordered, unordered, nested, mixed), text formatting (bold, italic, underline, strikethrough, highlight), all heading levels, horizontal rules
- **Chapter 2**: Code blocks, inline code, blockquotes (simple and nested), definition lists
- **Chapter 3**: Links, anchors, images
- **Chapter 4**: User highlights feature documentation and examples
