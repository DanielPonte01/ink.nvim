local fs = require("ink.fs")
local library = require("ink.library")
local context = require("ink.ui.context")

local M = {}

-- Forward declaration needed to break cyclic dependency on init via open_book
local function open_book_via_init(epub_data)
  require("ink.ui").open_book(epub_data)
end

function M.show_library_telescope(books)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')

  local entries = {}
  for _, book in ipairs(books) do
    local progress = math.floor((book.chapter / book.total_chapters) * 100)
    local last_opened = library.format_last_opened(book.last_opened)
    local author = book.author or "Unknown"
    table.insert(entries, {
      display = string.format("%-30s │ %-20s │ %3d%% │ %s", book.title:sub(1, 30), author:sub(1, 20), progress, last_opened),
      ordinal = book.title .. " " .. author,
      book = book,
      progress = progress,
      last_opened = last_opened,
      author = author
    })
  end

  pickers.new({}, {
    prompt_title = "Library (C-b: bookmarks, C-d: delete, C-e: edit)",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return { value = entry, display = entry.display, ordinal = entry.ordinal, book = entry.book }
      end
    }),
    previewer = previewers.new_buffer_previewer({
      title = "Book Info",
      define_preview = function(self, entry)
        local book = entry.book
        local lines = { "Title: " .. book.title, "Author: " .. (book.author or "Unknown") }
        if book.language then table.insert(lines, "Language: " .. book.language) end
        if book.date then table.insert(lines, "Date: " .. book.date) end
        table.insert(lines, "")
        table.insert(lines, "Progress: " .. entry.value.progress .. "% (Chapter " .. book.chapter .. "/" .. book.total_chapters .. ")")
        table.insert(lines, "Last opened: " .. entry.value.last_opened)
        if book.description and book.description ~= "" then
          table.insert(lines, ""); table.insert(lines, "Description:")
          local desc = book.description; local wrap_width = 60
          while #desc > 0 do
            if #desc <= wrap_width then table.insert(lines, "  " .. desc); break
            else
              local break_pos = desc:sub(1, wrap_width):match(".*()%s") or wrap_width
              table.insert(lines, "  " .. desc:sub(1, break_pos))
              desc = desc:sub(break_pos + 1):match("^%s*(.*)$") or ""
            end
          end
        end
        table.insert(lines, ""); table.insert(lines, "Path: " .. book.path)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        local book = selection.book
        if not fs.exists(book.path) then vim.notify("Book not found: " .. book.path, vim.log.levels.ERROR); return end

        local epub = require("ink.epub")
        local ok, epub_data = pcall(epub.open, book.path)
        if ok then
          open_book_via_init(epub_data)
        else
          vim.notify("Failed to open: " .. tostring(epub_data), vim.log.levels.ERROR)
        end
      end)
      map('i', '<C-d>', function()
        local selection = action_state.get_selected_entry()
        if selection then
          library.remove_book(selection.book.slug)
          vim.notify("Removed: " .. selection.book.title, vim.log.levels.INFO)
          actions.close(prompt_bufnr)
          vim.schedule(function() M.show_library() end)
        end
      end)
      map('n', '<C-d>', function()
        local selection = action_state.get_selected_entry()
        if selection then
          library.remove_book(selection.book.slug)
          vim.notify("Removed: " .. selection.book.title, vim.log.levels.INFO)
          actions.close(prompt_bufnr)
          vim.schedule(function() M.show_library() end)
        end
      end)
      map('i', '<C-e>', function() actions.close(prompt_bufnr); vim.cmd("InkEditLibrary") end)
      map('n', '<C-e>', function() actions.close(prompt_bufnr); vim.cmd("InkEditLibrary") end)
      map('i', '<C-b>', function()
        actions.close(prompt_bufnr)
        local bookmarks_ui = require("ink.ui.bookmarks")
        bookmarks_ui.show_bookmarks_telescope(nil, function() M.show_library() end)
      end)
      map('n', '<C-b>', function()
        actions.close(prompt_bufnr)
        local bookmarks_ui = require("ink.ui.bookmarks")
        bookmarks_ui.show_bookmarks_telescope(nil, function() M.show_library() end)
      end)
      return true
    end
  }):find()
end

function M.show_library_floating(books)
  local lines = {}
  local book_map = {}
  table.insert(lines, "Library (press Enter to open, q to close)")
  table.insert(lines, string.rep("─", 75))
  for i, book in ipairs(books) do
    local progress = math.floor((book.chapter / book.total_chapters) * 100)
    local last_opened = library.format_last_opened(book.last_opened)
    local author = book.author or "Unknown"
    local line = string.format(" %d. %-25s │ %-15s │ %3d%% │ %s", i, book.title:sub(1, 25), author:sub(1, 15), progress, last_opened)
    table.insert(lines, line)
    book_map[#lines] = book
  end
  table.insert(lines, ""); table.insert(lines, " Press Enter to open, d to delete, q to close")

  local width = 80
  local height = math.min(#lines, 20)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  local win_width = vim.o.columns
  local win_height = vim.o.lines
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor", row = row, col = col, width = width, height = height,
    style = "minimal", border = "rounded", title = " Library ", title_pos = "center",
  })

  local function close_window() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
  vim.keymap.set("n", "q", close_window, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close_window, { buffer = buf })
  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local book = book_map[cursor[1]]
    if book then
      close_window()
      if not fs.exists(book.path) then vim.notify("Book not found: " .. book.path, vim.log.levels.ERROR); return end

      local epub = require("ink.epub")
      local ok, epub_data = pcall(epub.open, book.path)
      if ok then
        open_book_via_init(epub_data)
      else
        vim.notify("Failed to open: " .. tostring(epub_data), vim.log.levels.ERROR)
      end
    end
  end, { buffer = buf })
  vim.keymap.set("n", "d", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local book = book_map[cursor[1]]
    if book then
      library.remove_book(book.slug)
      vim.notify("Removed: " .. book.title, vim.log.levels.INFO)
      close_window()
      vim.schedule(function() M.show_library() end)
    end
  end, { buffer = buf })
  vim.api.nvim_win_set_cursor(win, {3, 0})
end

function M.show_library()
  local books = library.get_books()
  if #books == 0 then vim.notify("Library is empty. Open a book with :InkOpen first.", vim.log.levels.INFO); return end
  local ok_telescope, _ = pcall(require, 'telescope')
  if ok_telescope then M.show_library_telescope(books) else M.show_library_floating(books) end
end

return M
