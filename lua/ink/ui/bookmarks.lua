local bookmarks = require("ink.bookmarks")
local context = require("ink.ui.context")
local render = require("ink.ui.render")

local M = {}

local function find_paragraph_line(lines, cursor_line)
  local line_content = lines[cursor_line] or ""

  -- If cursor is on empty line, find next paragraph
  if line_content:match("^%s*$") then
    for i = cursor_line + 1, #lines do
      if not lines[i]:match("^%s*$") then
        -- Find the start of this paragraph
        for j = i, 1, -1 do
          if lines[j]:match("^%s*$") then
            return j + 1
          end
          if j == 1 then return 1 end
        end
      end
    end
    return cursor_line
  end

  -- Find start of current paragraph (go up until empty line or start)
  for i = cursor_line, 1, -1 do
    if lines[i]:match("^%s*$") then
      return i + 1
    end
    if i == 1 then return 1 end
  end
  return 1
end

local function get_paragraph_preview(lines, start_line, max_chars)
  max_chars = max_chars or 100
  local text = ""
  for i = start_line, #lines do
    local line = lines[i]
    if line:match("^%s*$") then break end
    local trimmed = line:match("^%s*(.-)%s*$")
    if text ~= "" then text = text .. " " end
    text = text .. trimmed
    if #text >= max_chars then break end
  end
  if #text > max_chars then
    text = text:sub(1, max_chars - 3) .. "..."
  end
  return text
end

local function open_bookmark_input(initial_name, callback)
  local buf = vim.api.nvim_create_buf(false, true)
  local width = 60
  local min_height = 1
  local max_height = 5

  local function calc_height(lines)
    return math.max(min_height, math.min(#lines, max_height))
  end

  local initial_lines = (initial_name and initial_name ~= "") and {initial_name} or {""}
  if initial_name and initial_name ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor", row = 1, col = 0, width = width, height = calc_height(initial_lines),
    style = "minimal", border = "rounded", title = " Bookmark name (Esc to save, empty to cancel) ", title_pos = "center",
  })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  local function resize_win()
    if not vim.api.nvim_win_is_valid(win) then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_height = calc_height(lines)
    vim.api.nvim_win_set_config(win, { height = new_height })
  end

  local augroup = vim.api.nvim_create_augroup("InkBookmarkResize", { clear = true })
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    group = augroup,
    buffer = buf,
    callback = resize_win,
  })

  if not initial_name or initial_name == "" then vim.cmd("startinsert") end
  vim.keymap.set("i", "<Esc>", function() vim.cmd("stopinsert") end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_del_augroup_by_id(augroup)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local name = table.concat(lines, " "):match("^%s*(.-)%s*$")
    vim.api.nvim_win_close(win, true)
    if callback then callback(name) end
  end, { buffer = buf })
end

function M.add_bookmark()
  local ctx = context.ctx
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then
    vim.notify("Bookmarks can only be added in the content buffer", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local cursor_line = cursor[1]
  local lines = ctx.rendered_lines or {}
  local paragraph_line = find_paragraph_line(lines, cursor_line)

  -- Check if bookmark already exists at this line
  local existing = bookmarks.find_at_line(ctx.data.slug, ctx.current_chapter_idx, paragraph_line)
  if existing then
    -- Edit existing bookmark
    open_bookmark_input(existing.name, function(name)
      if name and name ~= "" then
        bookmarks.update(existing.id, name)
        render.render_chapter(ctx.current_chapter_idx, cursor_line)
        vim.notify("Bookmark updated", vim.log.levels.INFO)
      end
    end)
    return
  end

  local preview = get_paragraph_preview(lines, paragraph_line, 100)

  open_bookmark_input("", function(name)
    if name and name ~= "" then
      local bookmark = {
        name = name,
        book_slug = ctx.data.slug,
        book_title = ctx.data.title,
        book_author = ctx.data.author,
        chapter = ctx.current_chapter_idx,
        paragraph_line = paragraph_line,
        text_preview = preview,
      }
      bookmarks.add(bookmark)
      render.render_chapter(ctx.current_chapter_idx, cursor_line)
      vim.notify("Bookmark added", vim.log.levels.INFO)
    end
  end)
end

function M.remove_bookmark()
  local ctx = context.ctx
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then
    vim.notify("Bookmarks can only be removed in the content buffer", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local cursor_line = cursor[1]
  local lines = ctx.rendered_lines or {}
  local paragraph_line = find_paragraph_line(lines, cursor_line)

  -- Find bookmark at paragraph
  local found = bookmarks.find_at_line(ctx.data.slug, ctx.current_chapter_idx, paragraph_line)

  if not found then
    vim.notify("No bookmark in this paragraph", vim.log.levels.WARN)
    return
  end

  bookmarks.remove(found.id)
  render.render_chapter(ctx.current_chapter_idx, cursor_line)
  vim.notify("Bookmark removed", vim.log.levels.INFO)
end

function M.goto_next()
  local ctx = context.ctx
  if not ctx.data then
    vim.notify("No book open", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local next_bm = bookmarks.get_next(ctx.data.slug, ctx.current_chapter_idx, cursor[1])

  if not next_bm then
    vim.notify("No next bookmark", vim.log.levels.INFO)
    return
  end

  if next_bm.chapter ~= ctx.current_chapter_idx then
    render.render_chapter(next_bm.chapter, next_bm.paragraph_line)
  else
    vim.api.nvim_win_set_cursor(ctx.content_win, {next_bm.paragraph_line, 0})
  end
end

function M.goto_prev()
  local ctx = context.ctx
  if not ctx.data then
    vim.notify("No book open", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local prev_bm = bookmarks.get_prev(ctx.data.slug, ctx.current_chapter_idx, cursor[1])

  if not prev_bm then
    vim.notify("No previous bookmark", vim.log.levels.INFO)
    return
  end

  if prev_bm.chapter ~= ctx.current_chapter_idx then
    render.render_chapter(prev_bm.chapter, prev_bm.paragraph_line)
  else
    vim.api.nvim_win_set_cursor(ctx.content_win, {prev_bm.paragraph_line, 0})
  end
end

function M.show_bookmarks_telescope(book_slug, switch_callback)
  local has_telescope, telescope = pcall(require, "telescope.builtin")
  if not has_telescope then
    M.show_bookmarks_floating(book_slug)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  local all_bookmarks = book_slug and bookmarks.get_by_book(book_slug) or bookmarks.get_all()
  local is_local = book_slug ~= nil
  local title = is_local and "Bookmarks Book (C-d delete, C-f toggle all, C-b goto Library)" or "Bookmarks All(C-d delete, C-f toggle book, C-b goto Library)"

  if #all_bookmarks == 0 then
    vim.notify("No bookmarks found", vim.log.levels.INFO)
    return
  end

  pickers.new({}, {
    prompt_title = title,
    finder = finders.new_table({
      results = all_bookmarks,
      entry_maker = function(bm)
        local display = bm.name .. " | " .. (bm.book_title or "Unknown") .. " | " .. (bm.book_author or "Unknown")
        return {
          value = bm,
          display = display,
          ordinal = bm.name .. " " .. (bm.book_title or "") .. " " .. (bm.book_author or ""),
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Bookmark Preview",
      define_preview = function(self, entry)
        local bm = entry.value
        local lines = {
          "Bookmark: " .. bm.name,
          "",
          "Book: " .. (bm.book_title or "Unknown"),
          "Author: " .. (bm.book_author or "Unknown"),
          "Chapter: " .. bm.chapter,
          "",
          "Preview:",
          bm.text_preview or "",
        }
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          local bm = entry.value
          M.goto_bookmark(bm)
        end
      end)

      -- Toggle local/global
      local function toggle_scope()
        actions.close(prompt_bufnr)
        local ctx = context.ctx
        if is_local then
          -- Go to global
          M.show_bookmarks_telescope(nil, switch_callback)
        else
          -- Go to local (book)
          if ctx.data and ctx.data.slug then
            M.show_bookmarks_telescope(ctx.data.slug, switch_callback)
          else
            vim.notify("No book open to show local bookmarks", vim.log.levels.WARN)
            M.show_bookmarks_telescope(nil, switch_callback)
          end
        end
      end
      map("i", "<C-f>", toggle_scope)
      map("n", "<C-f>", toggle_scope)

      -- Edit bookmarks file
      map("i", "<C-e>", function()
        actions.close(prompt_bufnr)
        vim.cmd("edit " .. bookmarks.get_file_path())
      end)
      map("n", "<C-e>", function()
        actions.close(prompt_bufnr)
        vim.cmd("edit " .. bookmarks.get_file_path())
      end)

      -- Switch to library
      map("i", "<C-b>", function()
        actions.close(prompt_bufnr)
        if switch_callback then switch_callback() end
      end)
      map("n", "<C-b>", function()
        actions.close(prompt_bufnr)
        if switch_callback then switch_callback() end
      end)

      -- Delete bookmark
      map("i", "<C-d>", function()
        local entry = action_state.get_selected_entry()
        if entry then
          bookmarks.remove(entry.value.id)
          actions.close(prompt_bufnr)
          M.show_bookmarks_telescope(book_slug, switch_callback)
        end
      end)
      map("n", "<C-d>", function()
        local entry = action_state.get_selected_entry()
        if entry then
          bookmarks.remove(entry.value.id)
          actions.close(prompt_bufnr)
          M.show_bookmarks_telescope(book_slug, switch_callback)
        end
      end)

      return true
    end,
  }):find()
end

function M.show_bookmarks_floating(book_slug)
  local all_bookmarks = book_slug and bookmarks.get_by_book(book_slug) or bookmarks.get_all()

  if #all_bookmarks == 0 then
    vim.notify("No bookmarks found", vim.log.levels.INFO)
    return
  end

  local lines = { " Bookmarks", "" }
  local bm_map = {}
  for i, bm in ipairs(all_bookmarks) do
    local line = string.format(" %d. %s | %s", i, bm.name, bm.book_title or "Unknown")
    table.insert(lines, line)
    bm_map[#lines] = bm
  end
  table.insert(lines, "")
  table.insert(lines, " Enter: open | d: delete | q: close")

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
    style = "minimal", border = "rounded", title = " Bookmarks ", title_pos = "center",
  })

  vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf })
  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local bm = bm_map[cursor[1]]
    if bm then
      vim.api.nvim_win_close(win, true)
      M.goto_bookmark(bm)
    end
  end, { buffer = buf })
  vim.keymap.set("n", "d", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local bm = bm_map[cursor[1]]
    if bm then
      bookmarks.remove(bm.id)
      vim.api.nvim_win_close(win, true)
      M.show_bookmarks_floating(book_slug)
    end
  end, { buffer = buf })
end

function M.goto_bookmark(bm)
  local ctx = context.ctx

  -- If different book, need to open it first
  if not ctx.data or ctx.data.slug ~= bm.book_slug then
    local library = require("ink.library")
    local books = library.get_books()
    local book_path = nil
    for _, book in ipairs(books) do
      if book.slug == bm.book_slug then
        book_path = book.path
        break
      end
    end
    if book_path then
      local epub = require("ink.epub")
      local ui = require("ink.ui")
      local epub_data = epub.open(book_path)
      if epub_data then
        ui.open_book(epub_data)
        vim.defer_fn(function()
          render.render_chapter(bm.chapter, bm.paragraph_line)
        end, 100)
      end
    else
      vim.notify("Book not found in library", vim.log.levels.WARN)
    end
    return
  end

  -- Same book, just navigate
  if bm.chapter ~= ctx.current_chapter_idx then
    render.render_chapter(bm.chapter, bm.paragraph_line)
  else
    vim.api.nvim_win_set_cursor(ctx.content_win, {bm.paragraph_line, 0})
  end
end

function M.show_all_bookmarks()
  local library_view = require("ink.ui.library_view")
  M.show_bookmarks_telescope(nil, function()
    library_view.show_library()
  end)
end

function M.show_book_bookmarks()
  local ctx = context.ctx
  if not ctx.data then
    vim.notify("No book open", vim.log.levels.WARN)
    return
  end
  local library_view = require("ink.ui.library_view")
  M.show_bookmarks_telescope(ctx.data.slug, function()
    library_view.show_library()
  end)
end

return M
