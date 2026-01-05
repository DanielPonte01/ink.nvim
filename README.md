# ink.nvim

> A minimalist, distraction-free EPUB and Markdown reader for Neovim.

Read books and documents without leaving your editor. Full support for EPUB files and Markdown documents with persistent highlights, notes, bookmarks, glossary system, and powerful search capabilities.

**Non-destructive**: All annotations (highlights, notes, bookmarks, glossary) are stored separately and never modify your original files.

**Quick Start:**
```vim
:InkOpen book.epub          " Open EPUB
:InkOpen document.md        " Open Markdown
:InkLibrary                 " Browse your library
:InkDashboard               " View reading statistics
```

## Features

### Reading
- **Multiple formats**: EPUB (.epub) and Markdown (.md) files
- **Continuous scrolling** per chapter with table of contents navigation
- **Smart caching**: EPUBs extracted once, automatically invalidated on file changes
- **Syntax highlighting** for code blocks and formatted text
- **Text justification** (optional, toggle on/off)
- **Adaptive width**: Automatically adjusts text width based on window size (manual override supported)
- **Progress tracking** with automatic session restoration

### Annotations
- **Highlights** with customizable colors (yellow, green, red, blue by default)
- **Change highlight colors** without recreating (preserves notes)
- **Notes on highlights** with timestamps and multiple display modes
- **Bookmarks** with custom names (multiple per paragraph)
- **Glossary system** with terms, definitions, aliases, and relationships
- **Parallel notes (padnotes)**: Chapter-specific markdown files with auto-save

### Organization
- **Library management**: Browse, search, and track reading progress
- **Collections**: Organize books into themed groups
- **Dashboard**: Minimalist interface showing library and statistics
- **Reading sessions**: Track time spent reading with detailed statistics
- **Status tracking**: Auto-categorize books (to-read, reading, completed)

### Navigation & Search
- **Telescope integration** for searching chapters and content
- **Internal links**: Navigate between sections with preview or jump
- **External links**: Open URLs in browser with confirmation
- **Footnote preview**: Floating windows for footnotes and anchors
- **Full-text search**: Live grep across all chapters

### Export & Sharing
- **Export to Markdown or JSON**: Highlights, notes, bookmarks, and glossary
- **Context inclusion**: Optional surrounding text for highlights
- **Glossary export**: Include terms and relationships
- **Timestamped filenames**: Organized export history

### Advanced
- **Image extraction** and external viewing
- **TOC rebuild**: Generate table of contents from headings
- **Relationship graphs**: Visualize glossary term connections (ASCII/HTML)
- **Cache management**: Interactive UI for cleaning up cached files

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

Default configuration with all available options:

```lua
require("ink").setup({
  focused_mode = true,
  image_open = true,
  justify_text = false,
  max_width = 120,
  width_step = 10,
  adaptive_width = true,              -- Automatically adjust text width based on window size
  adaptive_width_margin = 0.8,        -- Use 80% of window width (0.1 to 1.0, maintains 10% margin on each side)

  -- All keymaps are customizable
  keymaps = {
    next_chapter = "]c",
    prev_chapter = "[c",
    toggle_toc = "<leader>t",
    activate = "<CR>",              -- Preview/open: footnote, link, image, TOC
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
    dashboard = "<leader>ed",
  },

  highlight_colors = {
    yellow = { bg = "#f9e2af", fg = "#000000" },
    green = { bg = "#a6e3a1", fg = "#000000" },
    red = { bg = "#f38ba8", fg = "#000000" },
    blue = { bg = "#89b4fa", fg = "#000000" },
    -- Add custom colors: purple, orange, pink, etc.
  },

  highlight_keymaps = {
    yellow = "<leader>hy",
    green = "<leader>hg",
    red = "<leader>hr",
    blue = "<leader>hb",
    remove = "<leader>hd"
  },

  highlight_change_color_keymaps = {
    yellow = "<leader>hcy",
    green = "<leader>hcg",
    red = "<leader>hcr",
    blue = "<leader>hcb"
  },

  note_keymaps = {
    add = "<leader>na",
    remove = "<leader>nd",
    toggle_display = "<leader>nt"
  },

  bookmark_keymaps = {
    add = "<leader>ba",
    edit = "<leader>be",
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
    format = "markdown",              -- "markdown" | "json"
    include_bookmarks = false,
    include_context = false,
    include_glossary = false,
    export_dir = "~/Documents",
  },

  glossary_visible = true,
  glossary_keymaps = {
    add = "<leader>ga",
    edit = "<leader>ge",
    remove = "<leader>gd",
    preview = "<leader>gp",
    browser = "<leader>gl",
    show_related = "<leader>gg",
    show_graph = "<leader>gG",
    toggle_display = "<leader>gt",
  },

  padnotes = {
    enabled = true,
    auto_save_interval = 120,         -- Auto-save every 2 minutes
    position = "right",                -- "right" | "left" | "top" | "bottom"
    size = 0.5,                        -- < 1 for percentage (0.5 = 50%), >= 1 for absolute (80 = 80 cols)
  },

  padnotes_keymaps = {
    toggle = "<leader>pa",
    open = "<leader>po",
    close = "<leader>pc",
    list_all = "<leader>pl",
  },

  dashboard_keymaps = {
    open = "<leader>ed",
  },
})
```

## Usage

### Commands

**Book Management:**
- `:InkOpen <path>` - Open EPUB or Markdown file
- `:InkLibrary` - Browse library with search and filters
- `:InkLast` - Reopen last read book at saved position
- `:InkAddLibrary [dir]` - Scan directory for EPUBs (async)
- `:InkEditLibrary` - Edit library.json manually
- `:InkDashboard [type]` - Open dashboard (library or stats)

**Annotations:**
- `:InkBookmarks` - Browse all bookmarks globally
- `:InkBookmarksBook` - Browse bookmarks in current book
- `:InkExport` - Export highlights, notes, bookmarks, glossary
- `:InkRebuildTOC` - Rebuild table of contents from headings

**Cache Management:**
- `:InkClearCache` - Interactive cache management UI
- `:InkClearCache --all` - Clear all cache (with confirmation)
- `:InkClearCache <slug>` - Clear specific book cache
- `:InkCacheInfo` - Show cache statistics

See the [default configuration](#configuration) above for all keymaps and options.

### Features in Detail

#### Highlights & Notes
1. Select text in visual mode
2. Press `<leader>hy` (or hg/hr/hb) to highlight
3. Press `<leader>na` to add a note on the highlight
4. Change color with `<leader>hcy` (preserves notes)
5. Toggle display modes: off, indicator (•), expanded

#### Adaptive Width
Text width automatically adapts to your window size for optimal reading comfort:

- **Automatic adjustment**: When enabled (default), text width uses 80% of window width
- **Window resize**: Text reflows when you open/close TOC, padnotes, or resize windows
- **Per-book isolation**: Each book/tab maintains independent width settings
- **Manual override**: Adjust width manually with `<leader>+` and `<leader>-`
  - Disables adaptive width with notification: "Width: 90 (adaptive disabled)"
  - Prevents automatic adjustments until reset
- **Reset adaptive**: Press `<leader>=` to restore adaptive behavior
  - Notification: "Width reset: 72 (adaptive enabled)"
  - Recalculates width based on current window size

#### Bookmarks
- Add multiple bookmarks per paragraph with `<leader>ba`
- Navigate with `<leader>bn` and `<leader>bp` across chapters
- Edit or remove with `<leader>be` and `<leader>bd`
- Visual indicator shows bookmark names above paragraphs

#### Glossary
- Add terms with `<leader>ga` on any word
- Auto-detection underlines terms in text
- Preview definitions with `<leader>gp`
- Define relationships: see_also, contrast, broader, narrower
- Visualize with ASCII or HTML graphs (`<leader>gG`)

#### Parallel Notes (Padnotes)
- `<leader>pa` - Smart toggle (create/open/close/switch chapters)
- One markdown file per chapter with auto-save (2min interval)
- `<leader>pl` - Browse all padnotes with preview
- Configurable position (right/left/top/bottom) and size
- Perfect for reading journals and study notes

#### Collections & Dashboard
- Organize books into themed collections
- Dashboard shows library table with pagination (15 books/page)
- Filter by collection, view statistics, manage collections
- Track reading time, completion rates, and progress

#### Export
```vim
:InkExport md -bcg ~/exports/
```
- Formats: `md` (Markdown) or `json`
- Flags: `-b` (bookmarks), `-c` (context), `-g` (glossary)
- Timestamped filenames: `book-title-2024-01-15.md`

#### Markdown Support
- Full support for `.md` files with all EPUB features
- Automatic chapter division by H1 headings (or H2 fallback)
- Generated table of contents from heading structure
- All features work: highlights, bookmarks, notes, glossary, search

### Links & Navigation

**Internal Links (anchors, footnotes):**
- `<CR>` - Preview in floating window or navigate to different chapter
- `g<CR>` - Jump directly to target

**External Links (URLs):**
- `<CR>` or `g<CR>` - Confirmation dialog to open in browser

### Search

**Chapter Search (`<leader>pit`):**
- Shows all chapters with previews
- Type to filter by name
- `<C-f>` to switch to content search

**Content Search (`<leader>pif`):**
- Live grep across all chapters
- Results as you type
- `<C-f>` to switch to chapter search

### Data Storage

All plugin data stored in `~/.local/share/nvim/ink.nvim/`:

```
~/.local/share/nvim/ink.nvim/
├── library.json              # Library metadata (all books)
├── collections.json          # Book collections
│
├── cache/                    # ⚡ Temporary (safe to delete)
│   └── {book-slug}/
│       ├── epub/             # Extracted EPUB files
│       ├── toc.json          # Generated TOC
│       ├── css.json          # Parsed styles
│       ├── search_index.json # Search index
│       └── glossary_matches.json  # Term detection cache
│
└── books/                    # 💾 User data (permanent)
    └── {book-slug}/
        ├── state.json        # Reading position
        ├── highlights.json   # Highlights and notes
        ├── bookmarks.json    # Bookmarks
        ├── glossary.json     # Terms and relationships
        ├── padnotes/         # Chapter-specific notes
        └── sessions.json     # Reading history
```

## Testing

A comprehensive test file (`ink-test.epub` and `ink-test.md`) demonstrates all features:

```vim
:InkOpen ink-test.epub
:InkOpen ink-test.md
```

The test file includes examples of:
- Text formatting and lists
- Code blocks and blockquotes
- Highlights, notes, and bookmarks
- Glossary usage
- Padnotes documentation
- Collections and dashboard
- Export functionality
- Cache management

## Author

Created by [DanielPonte01](https://github.com/DanielPonte01)

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.
