# ink.nvim

A minimalist EPUB, Markdown, and web reader for Neovim with powerful annotation and organization features.

**Quick Start:**
```vim
:InkOpen book.epub
:InkOpen document.md
:InkOpen https://example.com/article
:InkLibrary
```

## Features

**Reading**
- Multiple formats: EPUB, Markdown, web pages
- Smart caching with automatic invalidation
- Adaptive text width based on window size
- Continuous scrolling with TOC navigation
- Customizable typography (line/paragraph spacing, justification)
- Syntax highlighting for code blocks

**Annotations**
- Highlights with customizable colors
- Notes on highlights with multiple display modes (off/indicator/margin/expanded)
- Bookmarks with custom names (multiple per paragraph)
- Glossary system with term types, relationships, and graph visualization
- Padnotes: chapter-specific markdown files with auto-save

**Organization**
- Library with collections and search
- Reading session tracking with statistics and streaks
- Dashboard with progress visualization
- Related resources: link books together with reciprocal relations
- Auto-categorization (to-read, reading, completed)

**Navigation & Search**
- Telescope integration for chapters and full-text search
- Internal links with preview or direct jump
- Footnote floating windows
- External links with confirmation

**Export**
- Export to Markdown or JSON
- Includes highlights, notes, bookmarks, and glossary
- Optional context and relationships
- Timestamped filenames

**Advanced**
- Image extraction and viewing
- TOC rebuild from headings
- Relationship graphs (ASCII/HTML)
- Cache management UI
- Web page version tracking and updates

## Requirements

- Neovim 0.7+
- `unzip` (for EPUB files)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) (optional, for search features)

## Installation

**Using [lazy.nvim](https://github.com/folke/lazy.nvim)**

```lua
{
  "DanielPonte01/ink.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("ink").setup()
  end
}
```

**Using [packer.nvim](https://github.com/wbthomason/packer.nvim)**

```lua
use {
  "DanielPonte01/ink.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("ink").setup()
  end
}
```

## Configuration

Default configuration (all options commented in code):

```lua
require("ink").setup({
    -- Display settings
    focused_mode = true,           -- Hide distractions (statusline, etc.) when reading
    image_open = true,             -- Allow opening images in external viewer
    justify_text = false,          -- Enable text justification (adds spaces between words, affects copying)
    max_width = 120,               -- Maximum text width in columns
    width_step = 10,               -- Width change amount per keypress (+/-)
    adaptive_width = true,         -- Auto-adjust width based on window size
    adaptive_width_margin = 0.8,   -- Use 80% of window width (0.1-1.0, maintains margins on sides)

    -- Navigation and interaction keymaps
    keymaps = {
        next_chapter = "]c",
        prev_chapter = "[c",
        toggle_toc = "<leader>t",
        toggle_floating_toc = "<leader>T", -- Experimental floating TOC
        activate = "<CR>",                  -- Preview/open footnote, link, image, or TOC item
        jump_to_link = "g<CR>",             -- Jump directly to link target
        search_toc = "<leader>pit",
        search_content = "<leader>pif",
        search_mode_toggle = "<C-f>",       -- Switch between TOC and content search in Telescope
        width_increase = "<leader>+",
        width_decrease = "<leader>-",
        width_reset = "<leader>=",          -- Reset to adaptive width
        toggle_justify = "<leader>jt",
        library = "<leader>eL",
        last_book = "<leader>el",
        dashboard = "<leader>ed",
        related_resources = "<leader>er",   -- List related books
    }
    -- Highlight colors (add custom colors: purple, orange, pink, etc.)
    highlight_colors = {
        yellow = { bg = "#E8C89F", fg = "#000000" },
        green = { bg = "#8BB894", fg = "#000000" },
        red = { bg = "#D97B73", fg = "#000000" },
        blue = { bg = "#7BA3D0", fg = "#000000" },
       -- purple = { bg = "#5A3B7A", fg = "#000000" }, -- Custom Color
        none = { bg = "NONE", fg = "NONE" },
    },

    -- Highlight keymaps (in visual mode)
    highlight_keymaps = {
        yellow = "<leader>hy",
        green = "<leader>hg",
        red = "<leader>hr",
        blue = "<leader>hb",
        remove = "<leader>hd",
       -- purple = "<leader>hp", -- Custom Color

    },

    -- Change highlight color (preserves notes)
    highlight_change_color_keymaps = {
        yellow = "<leader>hcy",
        green = "<leader>hcg",
        red = "<leader>hcr",
        blue = "<leader>hcb",
     --   purple = "<leader>hcp", -- Custom Color

    },

    -- Notes keymaps
    note_keymaps = {
        add = "<leader>na",           -- Add/edit note on highlight
        remove = "<leader>nd",
        toggle_display = "<leader>nt", -- Cycle: off → indicator → margin → expanded
    },
    note_display_mode = "margin",      -- Default display mode: "off" | "indicator" | "margin" | "expanded"
    margin_note_width = 35,            -- Max width of margin notes (chars)
    margin_min_space = 30,             -- Min margin space required for margin mode (chars)
    notes_list_keymaps = {
        list_all = "<leader>nla",      -- List notes from all books
        list_book = "<leader>nlb",
    },

    -- Bookmarks keymaps
    bookmark_keymaps = {
        add = "<leader>ba",
        edit = "<leader>be",
        remove = "<leader>bd",
        next = "<leader>bn",           -- Navigate across chapters
        prev = "<leader>bp",
        list_all = "<leader>bl",       -- Global bookmarks list
        list_book = "<leader>bb",      -- Current book bookmarks
    },
    bookmark_icon = "📑",

    -- Export keymaps
    export_keymaps = {
        current_book = "<leader>ex",
    },
    export_defaults = {
        format = "markdown",       -- "markdown" | "json"
        include_bookmarks = false, -- Include bookmarks in export
        include_context = false,   -- Include surrounding text for highlights
        include_glossary = false,  -- Include glossary terms and relationships
        export_dir = "~/Documents",
    },

    -- Typography settings
    typography = {
        line_spacing = 1,      -- Lines between text lines (1 = normal, 2 = double space)
        paragraph_spacing = 1, -- Lines between paragraphs
        indent_size = 4,       -- Indent for blockquotes, code blocks, definitions
        list_indent = 2,       -- Indent for nested lists
    },
    typography_keymaps = {
        line_spacing_increase = "<leader>l+",
        line_spacing_decrease = "<leader>l-",
        line_spacing_reset = "<leader>l=",
        paragraph_spacing_increase = "<leader>p+",
        paragraph_spacing_decrease = "<leader>p-",
        paragraph_spacing_reset = "<leader>p=",
    },

    -- Reading session tracking
    tracking = {
        enabled = true,           -- Track reading time and sessions
        auto_save_interval = 300, -- Save interval in seconds (5 min)
        cleanup_after_days = 365, -- Clean old sessions (0 = never)
        grace_period = 1,         -- Days of grace for streak continuation
    },

    -- Glossary term types (customize icons and colors)
    glossary_types = {
        character = { icon = "👤", color = "InkGlossaryCharacter" },
        place = { icon = "📍", color = "InkGlossaryPlace" },
        concept = { icon = "💡", color = "InkGlossaryConcept" },
        organization = { icon = "🏛️", color = "InkGlossaryOrg" },
        object = { icon = "⚔️", color = "InkGlossaryObject" },
        event = { icon = "⚡", color = "InkGlossaryEvent" },
        foreign_word = { icon = "🌐", color = "InkGlossaryForeign" },
        other = { icon = "📝", color = "InkGlossary" }
    },
    glossary_visible = true, -- Show glossary terms underlined in text
    glossary_keymaps = {
        add = "<leader>ga",
        edit = "<leader>ge",
        remove = "<leader>gd",
        preview = "<leader>gp",        -- Show definition in floating window
        browser = "<leader>gl",        -- Browse all entries with Telescope
        show_related = "<leader>gg",   -- Show related terms (relationships)
        show_graph = "<leader>gG",     -- Visualize term relationships (ASCII/HTML)
        toggle_display = "<leader>gt", -- Toggle term underlining on/off
    },

    -- TOC configuration
    force_content_toc = false, -- Build TOC from content headings instead of EPUB metadata

    -- Padnotes configuration (chapter-specific markdown notes)
    padnotes = {
        enabled = true,
        path = "default",         -- "default" or custom with {slug}, {author}, {title} placeholders
        auto_save_interval = 120, -- Auto-save interval in seconds
        template = "default",     -- Custom template (future feature)
        position = "right",       -- "right" | "left" | "top" | "bottom"
        size = 0.5,               -- < 1: percentage (0.5 = 50%), >= 1: absolute columns/lines
    },
    padnotes_keymaps = {
        toggle = "<leader>pa",   -- Smart toggle: create/open/close/switch chapters
        open = "<leader>po",
        close = "<leader>pc",
        list_all = "<leader>pl", -- Browse all padnotes with Telescope
    },

    -- Related resources (link books together)
    related_resources = {
        position = "right", -- Where to open related book
        show_toc = false,   -- Show TOC when opening (false to avoid clutter)
    },
})
```

## Usage

### Commands

**Book Management**
```vim
:InkOpen <path>           " Open EPUB/Markdown/URL
:InkLibrary               " Browse library
:InkLast                  " Reopen last book
:InkAddLibrary [dir]      " Scan directory for EPUBs
:InkDashboard [type]      " Open dashboard (library/stats)
```

**Annotations**
```vim
:InkBookmarks             " Browse all bookmarks
:InkBookmarksBook         " Browse current book bookmarks
:InkNotes                 " List all notes
:InkNotesBook             " List current book notes
:InkExport                " Export annotations
```

**Glossary**
```vim
:InkGlossary              " Browse glossary with Telescope
:InkGlossaryAdd [term]    " Add entry
:InkGlossaryGraph         " Visualize relationships
```

**Related Resources**
```vim
:InkAddRelated            " Link related book
:InkListRelated           " Show related books (Ctrl-d to remove)
:InkCleanupRelated        " Clean orphan references
```

**Cache**
```vim
:InkClearCache            " Interactive cache UI
:InkClearCache --all      " Clear all cache
:InkClearCache <slug>     " Clear specific book
:InkCacheInfo             " Show cache stats
```

**Web-Specific**
```vim
:InkWebToggleVersion      " Switch between versions
:InkWebChangelog          " Show version changelog
:InkWebCheckUpdates       " Check for updates
:InkWebUpdateSafe         " Update with backup
```

**Other**
```vim
:InkRebuildTOC            " Rebuild TOC from content
:InkHealth                " Run diagnostics
:InkResetStats            " Reset reading statistics
```

### Key Features

**Highlights & Notes**
- Select text in visual mode, press `<leader>hy` (yellow/green/red/blue)
- Add notes with `<leader>na`
- Change color with `<leader>hcy` (preserves notes)
- Toggle display: `<leader>nt` (off → indicator → margin → expanded)

**Adaptive Width**
- Auto-adjusts to window size (80% by default)
- Manual adjust: `<leader>+` / `<leader>-` (disables adaptive)
- Reset: `<leader>=` (re-enables adaptive)

**Bookmarks**
- Add: `<leader>ba`, navigate: `<leader>bn` / `<leader>bp`
- Multiple bookmarks per paragraph supported

**Glossary**
- Add terms: `<leader>ga`, preview: `<leader>gp`
- Auto-detection underlines terms in text
- Define relationships: see_also, contrast, broader, narrower
- Visualize: `<leader>gG` (ASCII/HTML graph)

**Padnotes**
- Smart toggle: `<leader>pa` (create/open/close/switch)
- One markdown file per chapter with auto-save
- Browse all: `<leader>pl`

**Related Resources**
- Link books together with reciprocal relations
- Open in split (configurable position)
- Manage via Telescope (Ctrl-d to remove)

**Typography**
- Adjust line spacing: `<leader>l+` / `<leader>l-`
- Adjust paragraph spacing: `<leader>p+` / `<leader>p-`
- Reset: `<leader>l=` / `<leader>p=`

**Export**
```vim
:InkExport md -bcg ~/exports/
```
Formats: `md` (Markdown) or `json`. Flags: `-b` (bookmarks), `-c` (context), `-g` (glossary).

**Search**
- TOC: `<leader>pit`, Content: `<leader>pif`
- Toggle modes: `<C-f>` in Telescope

**Links**
- Internal: `<CR>` (preview), `g<CR>` (jump)
- External: Opens in browser with confirmation

### Data Storage

```
~/.local/share/nvim/ink.nvim/
├── library.json           # Library metadata
├── related.json           # Related metadata
├── collections.json       # Collections
├── cache/                 # Temporary (safe to delete)
│   └── {book-slug}/       # Extracted EPUB, TOC, indexes
└── books/                 # User data (permanent)
    └── {book-slug}/
        ├── state.json     # Reading position
        ├── highlights.json
        ├── bookmarks.json
        ├── glossary.json
        ├── padnotes/
        └── sessions.json  # Reading history
```

## Testing

Test files demonstrate all features:
```vim
:InkOpen ink-test.epub
:InkOpen ink-test.md
```

## Author

Created by [DanielPonte01](https://github.com/DanielPonte01)

## License

GPL-3.0
