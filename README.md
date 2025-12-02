# ink.nvim

A minimalist, distraction-free EPUB reader for Neovim.

## Features
- Read EPUB files inside Neovim buffers
- Continuous scrolling per chapter
- Navigable table of contents
- Syntax-highlighted text rendered from HTML
- Progress tracking and restoration
- Image extraction and external viewing

## Usage

- `:InkOpen <path/to/book.epub>`: Open an EPUB file.
- `]c`: Next chapter
- `[c`: Previous chapter
- `<leader>t`: Toggle TOC
- `<CR>`: In TOC, jump to chapter; on image, open in viewer

## Testing

A comprehensive test EPUB (`ink-test.epub`) is included to demonstrate all features:

```bash
nvim -u repro.lua
:InkOpen ink-test.epub
```

The test book includes:
- Lists (ordered, unordered, nested, mixed)
- Text formatting (bold, italic, underline, strikethrough, highlight)
- Code blocks and inline code
- Blockquotes (simple and nested)
- Definition lists
- Links and anchors
- Images
- Horizontal rules
- All heading levels
