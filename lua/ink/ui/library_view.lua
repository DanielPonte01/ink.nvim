local fs = require("ink.fs")
local library = require("ink.library")
local context = require("ink.ui.context")

local M = {}

-- Forward declaration needed to break cyclic dependency on init via open_book
local function open_book_via_init(epub_data)
  require("ink.ui").open_book(epub_data)
end

-- Helper function to calculate visual width of string (handles multibyte chars)
local function visual_width(str)
  return vim.fn.strdisplaywidth(str)
end

-- Helper function to truncate and pad string to exact width
local function fit_string(str, width)
  if not str or str == "" then
    return string.rep(" ", width)
  end

  local vw = visual_width(str)
  if vw > width then
    -- Truncate: keep removing chars until it fits
    local result = str
    while visual_width(result) > width do
      result = result:sub(1, vim.fn.byteidx(result, vim.fn.strchars(result) - 1))
    end
    return result
  else
    -- Pad with spaces
    return str .. string.rep(" ", width - vw)
  end
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
    local tag = book.tag or ""
    local title_str = fit_string(book.title, 30)
    local author_str = fit_string(author, 20)
    local tag_str = fit_string(tag, 15)
    local progress_str = string.format("%3d%%", progress)

    table.insert(entries, {
      display = string.format("%s │ %s │ %s │ %s │ %s", title_str, author_str, tag_str, progress_str, last_opened),
      ordinal = book.title .. " " .. author .. " " .. tag,
      book = book,
      progress = progress,
      last_opened = last_opened,
      author = author
    })
  end

  pickers.new({}, {
    prompt_title = "Library (C-b: bookmarks, C-d: delete, C-e: edit, C-t: tag)",
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

        -- For web URLs, skip file existence check
        local is_web_url = book.path:match("^https?://") ~= nil
        if not is_web_url and not fs.exists(book.path) then
          vim.notify("Book not found: " .. book.path, vim.log.levels.ERROR)
          return
        end

        local ok, book_data = library.open_book(book.path, book.format)
        if ok then
          open_book_via_init(book_data)
        else
          vim.notify("Failed to open: " .. tostring(book_data), vim.log.levels.ERROR)
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
      map('i', '<C-t>', function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)
          vim.ui.input({ prompt = "Tag: ", default = selection.book.tag or "" }, function(input)
            if input ~= nil then
              library.set_book_tag(selection.book.slug, input)
              vim.notify("Tag updated for: " .. selection.book.title, vim.log.levels.INFO)
            end
            vim.schedule(function() M.show_library() end)
          end)
        end
      end)
      map('n', '<C-t>', function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)
          vim.ui.input({ prompt = "Tag: ", default = selection.book.tag or "" }, function(input)
            if input ~= nil then
              library.set_book_tag(selection.book.slug, input)
              vim.notify("Tag updated for: " .. selection.book.title, vim.log.levels.INFO)
            end
            vim.schedule(function() M.show_library() end)
          end)
        end
      end)
      return true
    end
  }):find()
end

function M.show_library_floating(books)
  local lines = {}
  local book_map = {}
  table.insert(lines, "Library (press Enter to open, t to tag, d to delete, q to close)")
  table.insert(lines, string.rep("─", 95))
  for i, book in ipairs(books) do
    local progress = math.floor((book.chapter / book.total_chapters) * 100)
    local last_opened = library.format_last_opened(book.last_opened)
    local author = book.author or "Unknown"
    local tag = book.tag or ""
    local title_str = fit_string(book.title, 30)
    local author_str = fit_string(author, 20)
    local tag_str = fit_string(tag, 15)
    local progress_str = string.format("%3d%%", progress)

    local line = string.format(" %s │ %s │ %s │ %s │ %s", title_str, author_str, tag_str, progress_str, last_opened)
    table.insert(lines, line)
    book_map[#lines] = book
  end
  table.insert(lines, ""); table.insert(lines, " Press Enter to open, t to tag, d to delete, q to close")

  local width = 100
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

      -- For web URLs, skip file existence check
      local is_web_url = book.path:match("^https?://") ~= nil
      if not is_web_url and not fs.exists(book.path) then
        vim.notify("Book not found: " .. book.path, vim.log.levels.ERROR)
        return
      end

      local ok, book_data = library.open_book(book.path, book.format)
      if ok then
        open_book_via_init(book_data)
      else
        vim.notify("Failed to open: " .. tostring(book_data), vim.log.levels.ERROR)
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
  vim.keymap.set("n", "t", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local book = book_map[cursor[1]]
    if book then
      close_window()
      vim.ui.input({ prompt = "Tag: ", default = book.tag or "" }, function(input)
        if input ~= nil then
          library.set_book_tag(book.slug, input)
          vim.notify("Tag updated for: " .. book.title, vim.log.levels.INFO)
        end
        vim.schedule(function() M.show_library() end)
      end)
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
