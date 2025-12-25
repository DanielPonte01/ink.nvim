# ink.nvim

> A minimalist, distraction-free EPUB and Markdown reader for Neovim.

Read books and documents without leaving your editor. Full support for EPUB files and Markdown documents with persistent highlights, notes, bookmarks, and powerful search capabilities.

**Non-destructive**: All annotations (highlights, notes, bookmarks) are stored separately and never modify your original files.

**Quick Start:**
```vim
:InkOpen book.epub          " Open EPUB
:InkOpen document.md        " Open Markdown
:InkLibrary                 " Browse your library
```

## Features
- **Multiple formats**: Read EPUB (.epub) and Markdown (.md) files inside Neovim
- **Continuous scrolling** per chapter
- **Navigable table of contents**
- **Telescope integration** for searching chapters and content
- **Syntax-highlighted text** rendered from HTML
- **Progress tracking** and restoration
- **Image extraction** and external viewing
- **External links**: Open URLs in browser with confirmation dialog
- **Internal links**: Navigate between sections and chapters (preview or jump)
- **User highlights** with customizable colors (persistent across sessions)
- **Notes on highlights** (add annotations to your highlights)
- **Bookmarks** with navigation (jump between bookmarks across chapters)
- **Text justification** (optional, toggle on/off)
- **Footnote preview** with floating windows
- **Library management** (browse, search, track reading progress)
- **Export highlights** and bookmarks to Markdown or JSON
- **Smart caching** for EPUBs with automatic invalidation
- **Cache management** UI for cleaning up cached files

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

Default configuration:

```lua
require("ink").setup({
  focused_mode = true,
  image_open = true,
  justify_text = false,
  max_width = 120,
  width_step = 10,

  keymaps = {
    next_chapter = "]c",
    prev_chapter = "[c",
    toggle_toc = "<leader>t",
    activate = "<CR>",
    jump_to_link = "g<CR>",
    search_toc = "<leader>pit",
    search_content = "<leader>pif",
    search_mode_toggle = "<C-f>",
    width_increase = "<leader>+",
    width_decrease = "<leader>-",
    width_reset = "<leader>=",
    toggle_justify = "<leader>jt",
    library = "<leader>eL",
    last_book = "<leader>el",
  },

  highlight_colors = {
    yellow = { bg = "#f9e2af", fg = "#000000" },
    green = { bg = "#a6e3a1", fg = "#000000" },
    red = { bg = "#f38ba8", fg = "#000000" },
    blue = { bg = "#89b4fa", fg = "#000000" },
    -- Add more colors: purple, orange, pink, etc.
    -- purple = { bg = "#cba6f7", fg = "#000000" },
  },

  highlight_keymaps = {
    yellow = "<leader>hy",
    green = "<leader>hg",
    red = "<leader>hr",
    blue = "<leader>hb",
    -- purple = "<leader>hp",    -- Highlight with your custom highlight
    remove = "<leader>hd"
  },

  highlight_change_color_keymaps = {
    yellow = "<leader>hcy",
    green = "<leader>hcg",
    red = "<leader>hcr",
    -- purple = "<leader>hcp",    -- Change to your custom color
    blue = "<leader>hcb"
  },

  note_keymaps = {
    add = "<leader>na",
    remove = "<leader>nd",
    toggle_display = "<leader>nt"
  },

  bookmark_keymaps = {
    add = "<leader>ba",
    remove = "<leader>bd",
    next = "<leader>bn",
    prev = "<leader>bp",
    list_all = "<leader>bl",
    list_book = "<leader>bb",
  },
  bookmark_icon = "📑",

  export_keymaps = {
    current_book = "<leader>ex",
  },

  export_defaults = {
    format = "markdown",
    include_bookmarks = false,
    include_context = false,
    export_dir = "~/Documents",
  },
})

-- Optional: Add a keymap to quickly open EPUB files
vim.keymap.set("n", "<leader>eo", ":InkOpen ", { desc = "Open EPUB file" })
vim.keymap.set("n", "<leader>le", ":InkEditLibrary", { desc = "Edit you library JSON file" })
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `:InkOpen <path>` | Open an EPUB (.epub) or Markdown (.md) file |
| `:InkLibrary` | Browse library of previously opened books |
| `:InkLast` | Reopen last read book at saved position |
| `:InkEditLibrary` | Edit library.json file manually |
| `:InkAddLibrary [dir]` | Scan directory for EPUBs and add to library |
| `:InkBookmarks` | Browse all bookmarks (global) |
| `:InkBookmarksBook` | Browse bookmarks in current book |
| `:InkExport` | Export current book highlights/bookmarks |
| `:InkClearCache` | Interactive cache management UI |
| `:InkClearCache --all` | Clear all EPUB cache (with confirmation) |
| `:InkClearCache <slug>` | Clear cache for specific book |
| `:InkCacheInfo` | Show cache information (count, location) |

### Default Keymaps

**Navigation:**
- `]c` - Next chapter
- `[c` - Previous chapter
- `<leader>t` - Toggle table of contents
- `<CR>` - Multiuse: Preview footnote/anchor (floating), open image/URL, navigate TOC
- `g<CR>` - Jump to link target (footnotes, anchors, cross-references)

**Search (requires telescope.nvim):**
- `<leader>pit` - Search/filter chapters by name (shows all chapters with preview)
- `<leader>pif` - Search text within all chapters (live grep)
- `<C-f>` - Toggle between chapter search and content search (preserves search text)

**Width & Formatting:**
- `<leader>+` - Increase text width
- `<leader>-` - Decrease text width
- `<leader>=` - Reset text width to default
- `<leader>jt` - Toggle text justification

**Highlighting:**
- `<leader>hy` - Highlight selection in yellow (visual mode)
- `<leader>hg` - Highlight selection in green (visual mode)
- `<leader>hr` - Highlight selection in red (visual mode)
- `<leader>hb` - Highlight selection in blue (visual mode)
- `<leader>hd` - Remove highlight under cursor (normal mode)
- `<leader>hcy` - Change highlight to yellow (normal mode)
- `<leader>hcg` - Change highlight to green (normal mode)
- `<leader>hcr` - Change highlight to red (normal mode)
- `<leader>hcb` - Change highlight to blue (normal mode)

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

**Export:**
- `<leader>ex` - Export current book highlights and bookmarks

**Library (global):**
- `<leader>eL` - Open library browser
- `<leader>el` - Open last read book

All keymaps can be customized in your configuration.

### Links

ink.nvim supports both internal and external links:

**Internal Links (anchors, footnotes):**
- `<CR>` - Preview in floating window (if in same chapter)
- `<CR>` - Navigate to target (if in different chapter)
- `g<CR>` - Jump directly to target

**External Links (URLs):**
- `<CR>` or `g<CR>` - Shows confirmation dialog: "Link to {URL}\nOpen in browser?"
- Press `y` to open in browser (xdg-open, firefox, chromium, etc.)
- Press `n` or `<Esc>` to cancel

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

### Markdown Support

ink.nvim provides full support for Markdown files with all EPUB features:

**Features:**
- Automatic chapter division by H1 headings (falls back to H2 if no H1)
- Generated table of contents from headings
- All reading features work: highlights, bookmarks, notes, search, export
- Internal links navigate across chapters
- Images and external links supported
- Progress tracking and library management

**Markdown-specific:**
- Virtual chapters created from heading structure
- TOC built from H1-H3 headings
- Internal links work globally (e.g., `[link](#section)` jumps to section anywhere in file)
- Images resolved relative to .md file location

**Usage:**
```vim
:InkOpen ~/notes/book.md
```

All features (highlights, bookmarks, notes, export) work identically to EPUBs.

### Export

Export your highlights, notes, and bookmarks to share or archive:

**Interactive Export:**
```vim
:InkExport
```

Prompts for:
- Format: `md` (Markdown) or `json`
- Options: `-b` (include bookmarks), `-c` (include context)
- Output path (defaults to `~/Documents`)

**Export Format Examples:**

Command: `:InkExport md -bc ~/exports/`
Result: `~/exports/book-title-2024-01-15.md`

**Markdown Export includes:**
- Book metadata (title, author, language, etc.)
- Statistics (highlights count, notes count, bookmarks count)
- Highlights grouped by chapter with color indication
- Optional: Context lines around each highlight
- Optional: Bookmarks with text previews
- Notes displayed inline with highlights

**JSON Export:**
Structured data for programmatic use, includes all metadata and content.

**Keymap:** `<leader>ex` opens export dialog for current book.

### Cache Management

EPUBs are extracted to cache for faster loading. Manage cache with:

**Interactive UI:**
```vim
:InkClearCache
```
Shows list of cached books with Telescope or floating menu. Select a book to clear its cache, or press `<C-a>` (Telescope) or `a` (floating) to clear all.

**Direct Commands:**
```vim
:InkClearCache --all          " Clear all cache (with confirmation)
:InkClearCache book-slug      " Clear specific book
:InkCacheInfo                 " Show cache stats
```

**Cache Features:**
- Automatic invalidation when EPUB is modified
- Extraction flag prevents incomplete cache usage
- Per-book storage in `~/.local/share/nvim/ink.nvim/cache/{slug}/`

### Data Storage

All plugin data is stored in `~/.local/share/nvim/ink.nvim/`:

```
~/.local/share/nvim/ink.nvim/
├── library.json              # Library metadata (all books)
├── cache/                    # Extracted EPUB contents
│   └── {book-slug}/
│       ├── .extracted        # Extraction flag (timestamp)
│       └── ...               # Extracted files (HTML, images, CSS)
└── books/                    # Per-book user data
    └── {book-slug}/
        ├── state.json        # Reading position (chapter, line)
        ├── highlights.json   # User highlights and notes
        ├── bookmarks.json    # Bookmarks for this book
        └── toc_cache.json    # Cached TOC (for EPUBs without built-in TOC)
```

**File Descriptions:**
- **library.json**: Tracks all opened books (EPUB/Markdown) with metadata, format, and progress
- **cache/{slug}/**: Extracted EPUB files (HTML, images, CSS) with automatic invalidation
- **cache/{slug}/.extracted**: Timestamp flag to track cache freshness
- **books/{slug}/state.json**: Reading position (chapter index and line number)
- **books/{slug}/highlights.json**: User highlights with colors, notes, and context
- **books/{slug}/bookmarks.json**: Bookmarks with names and text previews
- **books/{slug}/toc_cache.json**: Generated TOC cache for performance

**Note:** Markdown files don't use cache (no extraction needed). All user data (highlights, bookmarks, notes) is stored the same way for both EPUBs and Markdown files.

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
4. To change color, place cursor on highlight and press change keymap (e.g., `<leader>hcr` for red)
5. To remove a highlight, place cursor on highlighted text and press `<leader>hd`

**Highlight Features:**
- **Persistent**: Saved across sessions
- **Book-specific**: Each EPUB has its own highlights
- **Non-destructive**: Don't modify the original EPUB file
- **Customizable**: Add unlimited colors in config
- **Color changing**: Change highlight color without recreating (preserves notes)

## Testing

A comprehensive test EPUB (and MD) (`ink-test.epub(.md)`) is included to demonstrate all features:

```vim
:InkOpen ink-test.epub
:InkOpen ink-test.md
```

All features (TOC, highlights, bookmarks, notes, search, export) work the same as EPUBs.

## Author

Created by [DanielPonte01](https://github.com/DanielPonte01)

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.
