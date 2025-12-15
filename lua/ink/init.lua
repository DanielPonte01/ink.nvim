local epub = require("ink.epub")
local markdown = require("ink.markdown")
local ui = require("ink.ui")

local M = {}

local default_config = {
  focused_mode = true,
  image_open = true,
  justify_text = false,  -- Enable text justification (adds spaces between words, affects copying)
  keymaps = {
    next_chapter = "]c",
    prev_chapter = "[c",
    toggle_toc = "<leader>t",
    activate = "<CR>",
    jump_to_link = "g<CR>",  -- Jump to link target (footnotes, cross-references)
    search_toc = "<leader>pit",
    search_content = "<leader>pif",
    search_mode_toggle = "<C-f>",  -- Toggle between TOC and content search
    width_increase = "<leader>+",
    width_decrease = "<leader>-",
    width_reset = "<leader>=",
    toggle_justify = "<leader>jt",  -- Toggle text justification
    library = "<leader>eL",  -- Open library
    last_book = "<leader>el"  -- Open last book
  },
  max_width = 120,
  width_step = 10,  -- How much to change width per keypress
  highlight_colors = {
    yellow = { bg = "#f9e2af", fg = "#000000" },
    green = { bg = "#a6e3a1", fg = "#000000" },
    red = { bg = "#f38ba8", fg = "#000000" },
    blue = { bg = "#89b4fa", fg = "#000000" },
  },
  highlight_keymaps = {
    yellow = "<leader>hy",
    green = "<leader>hg",
    red = "<leader>hr",
    blue = "<leader>hb",
    remove = "<leader>hd"
  },
  note_keymaps = {
    add = "<leader>na",           -- Add/edit note on highlight under cursor
    remove = "<leader>nd",       -- Remove note from highlight under cursor
    toggle_display = "<leader>nt" -- Toggle note display mode (off/indicator/expanded)
  },
  bookmark_keymaps = {
    add = "<leader>ba",           -- Add/edit bookmark
    remove = "<leader>bd",        -- Remove bookmark
    next = "<leader>bn",          -- Go to next bookmark
    prev = "<leader>bp",          -- Go to previous bookmark
    list_all = "<leader>bl",      -- List all bookmarks
    list_book = "<leader>bb",     -- List bookmarks in current book
  },
  bookmark_icon = "📑",            -- Default bookmark icon
  export_keymaps = {
    current_book = "<leader>ex",  -- Export current book
  },
  export_defaults = {
    format = "markdown",           -- "markdown" | "json"
    include_bookmarks = false,
    include_context = false,
    export_dir = "~/Documents",    -- Default export directory
  },
  typography = {
    line_spacing = 1,              -- Lines between each line of text (1 = normal, 2 = double space)
    paragraph_spacing = 1,         -- Lines between paragraphs
    indent_size = 4,               -- Indent size for blockquotes, code blocks, definitions
    list_indent = 2,               -- Indent size for nested lists
  },
  typography_keymaps = {
    line_spacing_increase = "<leader>l+",
    line_spacing_decrease = "<leader>l-",
    line_spacing_reset = "<leader>l=",
    paragraph_spacing_increase = "<leader>p+",
    paragraph_spacing_decrease = "<leader>p-",
    paragraph_spacing_reset = "<leader>p=",
  }
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", default_config, opts or {})
  ui.setup(M.config)

  -- Function to define highlights
  local function define_highlights()
    vim.cmd([[
      highlight default link InkTitle Title
      highlight default link InkH1 Title
      highlight default link InkH2 Constant
      highlight default link InkH3 Identifier
      highlight default link InkH4 Statement
      highlight default link InkH5 PreProc
      highlight default link InkH6 Type
      highlight default link InkStatement Statement
      highlight default link InkComment Comment
      highlight default link InkSpecial Special
      highlight default link InkListItem Special
      highlight default link InkHorizontalRule Comment
      highlight default link InkCode String
      highlight default link InkHighlight Search
      highlight! InkBold cterm=bold gui=bold
      highlight! InkItalic cterm=italic gui=italic
      highlight! InkUnderlined cterm=underline gui=underline
      highlight! InkStrikethrough cterm=strikethrough gui=strikethrough
      highlight default link InkNoteIndicator DiagnosticInfo
      highlight default link InkNoteText Comment
      highlight default link InkBookmark DiagnosticHint
    ]])

    -- Define user highlight colors
    for color_name, color_def in pairs(M.config.highlight_colors) do
      local hl_group = "InkUserHighlight_" .. color_name
      vim.api.nvim_set_hl(0, hl_group, {
        bg = color_def.bg,
        fg = color_def.fg
      })
    end
  end

  -- Define highlights initially
  define_highlights()

  -- Re-define highlights after colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("InkHighlights", { clear = true }),
    callback = function()
      define_highlights()
    end
  })

  -- Create Command
  vim.api.nvim_create_user_command("InkOpen", function(args)
    local path = args.args
    if path == "" then
      vim.notify("Please provide a file path (EPUB or Markdown)", vim.log.levels.ERROR)
      return
    end

    -- Expand path
    path = vim.fn.expand(path)

    -- Detect file format and open accordingly
    local ok, data
    if path:match("%.epub$") then
      ok, data = pcall(epub.open, path)
      if not ok then
        vim.notify("Failed to open EPUB: " .. data, vim.log.levels.ERROR)
        return
      end
    elseif path:match("%.md$") or path:match("%.markdown$") then
      ok, data = pcall(markdown.open, path)
      if not ok then
        vim.notify("Failed to open Markdown: " .. data, vim.log.levels.ERROR)
        return
      end
    else
      vim.notify("Unsupported file format. Please use .epub or .md files", vim.log.levels.ERROR)
      return
    end

    ui.open_book(data)

  end, {
    nargs = 1,
    complete = "file"
  })

  -- Create Library command
  vim.api.nvim_create_user_command("InkLibrary", function()
    ui.show_library()
  end, {})

  -- Create Last Book command
  vim.api.nvim_create_user_command("InkLast", function()
    ui.open_last_book()
  end, {})

  -- Create Edit Library command (opens library.json for manual editing)
  vim.api.nvim_create_user_command("InkEditLibrary", function()
    local library_path = vim.fn.stdpath("data") .. "/ink.nvim/library.json"
    vim.cmd("edit " .. library_path)
  end, {})

  -- Create Add Library command (scans directory for EPUBs and adds them to library)
  vim.api.nvim_create_user_command("InkAddLibrary", function(args)
    local library = require("ink.library")
    local directory = args.args
    if directory == "" then
      directory = vim.fn.getcwd()
    end

    vim.notify("Scanning for EPUB files in " .. directory .. "...", vim.log.levels.INFO)

    -- Use async version with callback
    library.scan_directory(directory, function(result, err)
      if not result then
        vim.notify("Error: " .. err, vim.log.levels.ERROR)
        return
      end

      local message = string.format(
        "Scan complete:\n- Total EPUBs found: %d\n- Added to library: %d\n- Already in library: %d",
        result.total,
        result.added,
        result.skipped
      )

      if #result.errors > 0 then
        message = message .. "\n- Failed to parse: " .. #result.errors
        for i, error_info in ipairs(result.errors) do
          if i <= 3 then
            message = message .. "\n  * " .. vim.fn.fnamemodify(error_info.path, ":t")
          end
        end
        if #result.errors > 3 then
          message = message .. "\n  ... and " .. (#result.errors - 3) .. " more"
        end
      end

      vim.notify(message, vim.log.levels.INFO)
    end)
  end, {
    nargs = "?",
    complete = "dir"
  })

  -- Create Bookmarks commands
  vim.api.nvim_create_user_command("InkBookmarks", function()
    ui.show_all_bookmarks()
  end, {})

  vim.api.nvim_create_user_command("InkBookmarksBook", function()
    ui.show_book_bookmarks()
  end, {})

  -- Create Export command
  vim.api.nvim_create_user_command("InkExport", function()
    local export_ui = require("ink.export.ui")
    export_ui.show_export_dialog()
  end, {})

  -- Create Cache management commands
  vim.api.nvim_create_user_command("InkClearCache", function(args)
    local arg = args.args

    if arg == "" then
      -- No argument: show interactive UI
      local cache_ui = require("ink.ui.cache")
      cache_ui.show_clear_cache_ui()
    elseif arg == "--all" then
      -- --all flag: clear all cache with confirmation
      local cache_ui = require("ink.ui.cache")
      cache_ui.clear_all_cache()
    else
      -- Specific slug provided
      local success, message = epub.clear_cache(arg)
      if success then
        vim.notify(message, vim.log.levels.INFO)
      else
        vim.notify(message, vim.log.levels.ERROR)
      end
    end
  end, {
    nargs = "?",
    desc = "Clear EPUB cache (interactive, --all, or specific slug)"
  })

  vim.api.nvim_create_user_command("InkCacheInfo", function()
    local info = epub.get_cache_info()
    if info.exists then
      vim.notify(
        string.format("EPUB Cache: %d books cached\nLocation: %s", info.total_books, info.path),
        vim.log.levels.INFO
      )
    else
      vim.notify("No cache directory found", vim.log.levels.INFO)
    end
  end, {})

  -- Global keymaps for library features
  local keymaps = M.config.keymaps
  local opts = { noremap = true, silent = true }

  if keymaps.library then
    vim.api.nvim_set_keymap("n", keymaps.library, ":InkLibrary<CR>", opts)
  end

  if keymaps.last_book then
    vim.api.nvim_set_keymap("n", keymaps.last_book, ":InkLast<CR>", opts)
  end

  -- Global keymaps for bookmarks
  local bookmark_keymaps = M.config.bookmark_keymaps
  if bookmark_keymaps.list_all then
    vim.api.nvim_set_keymap("n", bookmark_keymaps.list_all, ":InkBookmarks<CR>", opts)
  end
  if bookmark_keymaps.list_book then
    vim.api.nvim_set_keymap("n", bookmark_keymaps.list_book, ":InkBookmarksBook<CR>", opts)
  end

  -- Global keymaps for export
  local export_keymaps = M.config.export_keymaps
  if export_keymaps.current_book then
    vim.api.nvim_set_keymap("n", export_keymaps.current_book, ":InkExport<CR>", opts)
  end
end

return M
