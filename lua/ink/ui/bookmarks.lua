local bookmarks = require("ink.bookmarks")
local context = require("ink.ui.context")
local render = require("ink.ui.render")
local library = require("ink.library")
local modals = require("ink.ui.modals")

local M = {}

-- Get all bookmarks across all books in library
local function get_all_bookmarks()
  local all = {}
  local books = library.get_books()
  for _, book in ipairs(books) do
    local book_bm = bookmarks.get_by_book(book.slug)
    for _, bm in ipairs(book_bm) do
      table.insert(all, bm)
    end
  end
  return all
end

local function find_bookmark_line(bm, lines)
  if not lines then return nil end
  local util = require("ink.ui.util")

  -- New bookmarks with text-matching
  if bm.paragraph_text then
    local start_line = util.find_text_position(
      lines,
      bm.paragraph_text,
      bm.context_before,
      bm.context_after
    )
    return start_line
  -- Legacy bookmarks with line-based positioning
  elseif bm.paragraph_line then
    return bm.paragraph_line
  end

  return nil
end

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

local function get_paragraph_text(lines, start_line, max_chars)
  max_chars = max_chars or 200
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
    text = text:sub(1, max_chars)
  end
  return text
end

local function get_paragraph_preview(lines, start_line, max_chars)
  max_chars = max_chars or 100
  local text = get_paragraph_text(lines, start_line, max_chars)
  if #text > max_chars then
    text = text:sub(1, max_chars - 3) .. "..."
  end
  return text
end

local function get_paragraph_context(lines, start_line, context_len)
  context_len = context_len or 30
  local util = require("ink.ui.util")

  local paragraph_text = get_paragraph_text(lines, start_line, 200)
  local full_text = util.get_full_text(lines)
  local start_offset = util.line_col_to_offset(lines, start_line, 0)

  local context_before = ""
  if start_offset > 0 then
    local ctx_start = math.max(0, start_offset - context_len)
    context_before = full_text:sub(ctx_start + 1, start_offset)
  end

  local context_after = ""
  local para_end_offset = start_offset + #paragraph_text
  if para_end_offset < #full_text then
    local ctx_end = math.min(#full_text, para_end_offset + context_len)
    context_after = full_text:sub(para_end_offset + 1, ctx_end)
  end

  return util.normalize_whitespace(paragraph_text),
         util.normalize_whitespace(context_before),
         util.normalize_whitespace(context_after)
end


function M.add_bookmark()
  local ctx = context.current()
  if not ctx then return end
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then
    vim.notify("Bookmarks can only be added in the content buffer", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local cursor_line = cursor[1]
  local lines = ctx.rendered_lines or {}
  local paragraph_line = find_paragraph_line(lines, cursor_line)

  -- Extract paragraph text and context
  local paragraph_text, context_before, context_after = get_paragraph_context(lines, paragraph_line, 30)
  local preview = get_paragraph_preview(lines, paragraph_line, 100)

  -- Check if bookmark already exists at this paragraph
  local util = require("ink.ui.util")
  local chapter_bookmarks = bookmarks.get_chapter_bookmarks(ctx.data.slug, ctx.current_chapter_idx)
  local existing = nil
  for _, bm in ipairs(chapter_bookmarks) do
    if bm.paragraph_text then
      local bm_line = util.find_text_position(lines, bm.paragraph_text, bm.context_before, bm.context_after)
      if bm_line == paragraph_line then
        existing = bm
        break
      end
    elseif bm.paragraph_line == paragraph_line then
      existing = bm
      break
    end
  end

  if existing then
    -- Edit existing bookmark
    modals.open_bookmark_input(existing.name, function(name)
      if name and name ~= "" then
        bookmarks.update(ctx.data.slug, existing.id, name)
        render.render_chapter(ctx.current_chapter_idx, cursor_line, ctx)
        vim.notify("Bookmark updated", vim.log.levels.INFO)
      end
    end)
    return
  end

  modals.open_bookmark_input("", function(name)
    if name and name ~= "" then
      local bookmark = {
        name = name,
        book_slug = ctx.data.slug,
        book_title = ctx.data.title,
        book_author = ctx.data.author,
        chapter = ctx.current_chapter_idx,
        paragraph_line = paragraph_line,
        paragraph_text = paragraph_text,
        context_before = context_before,
        context_after = context_after,
        text_preview = preview,
      }
      bookmarks.add(ctx.data.slug, bookmark)
      render.render_chapter(ctx.current_chapter_idx, cursor_line, ctx)
      vim.notify("Bookmark added", vim.log.levels.INFO)
    end
  end)
end

function M.remove_bookmark()
  local ctx = context.current()
  if not ctx then return end
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then
    vim.notify("Bookmarks can only be removed in the content buffer", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local cursor_line = cursor[1]
  local lines = ctx.rendered_lines or {}
  local paragraph_line = find_paragraph_line(lines, cursor_line)

  -- Find bookmark at current paragraph
  local util = require("ink.ui.util")
  local chapter_bookmarks = bookmarks.get_chapter_bookmarks(ctx.data.slug, ctx.current_chapter_idx)
  local found = nil

  for _, bm in ipairs(chapter_bookmarks) do
    if bm.paragraph_text then
      local bm_line = util.find_text_position(lines, bm.paragraph_text, bm.context_before, bm.context_after)
      if bm_line == paragraph_line then
        found = bm
        break
      end
    elseif bm.paragraph_line == paragraph_line then
      found = bm
      break
    end
  end

  if not found then
    vim.notify("No bookmark in this paragraph", vim.log.levels.WARN)
    return
  end

  bookmarks.remove(ctx.data.slug, found.id)
  render.render_chapter(ctx.current_chapter_idx, cursor_line, ctx)
  vim.notify("Bookmark removed", vim.log.levels.INFO)
end

function M.goto_next()
  local ctx = context.current()
  if not ctx or not ctx.data then
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
    -- Render chapter, then find bookmark position
    render.render_chapter(next_bm.chapter, 1, ctx)
    vim.defer_fn(function()
      local line = find_bookmark_line(next_bm, ctx.rendered_lines)
      if line and ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
        vim.api.nvim_win_set_cursor(ctx.content_win, {line, 0})
      end
    end, 10)
  else
    local line = find_bookmark_line(next_bm, ctx.rendered_lines)
    if line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {line, 0})
    end
  end
end

function M.goto_prev()
  local ctx = context.current()
  if not ctx or not ctx.data then
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
    -- Render chapter, then find bookmark position
    render.render_chapter(prev_bm.chapter, 1, ctx)
    vim.defer_fn(function()
      local line = find_bookmark_line(prev_bm, ctx.rendered_lines)
      if line and ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
        vim.api.nvim_win_set_cursor(ctx.content_win, {line, 0})
      end
    end, 10)
  else
    local line = find_bookmark_line(prev_bm, ctx.rendered_lines)
    if line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {line, 0})
    end
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

  local all_bookmarks = book_slug and bookmarks.get_by_book(book_slug) or get_all_bookmarks()
  local is_local = book_slug ~= nil
  local title = is_local and "Bookmarks Book (C-d delete, C-f toggle all, C-b goto Library)" or "Bookmarks All (C-d delete, C-f toggle book, C-b goto Library)"

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
        local ctx = context.current()
        if is_local then
          -- Go to global
          M.show_bookmarks_telescope(nil, switch_callback)
        else
          -- Go to local (book)
          if ctx and ctx.data and ctx.data.slug then
            M.show_bookmarks_telescope(ctx.data.slug, switch_callback)
          else
            vim.notify("No book open", vim.log.levels.WARN)
            M.show_bookmarks_telescope(nil, switch_callback)
          end
        end
      end
      map("i", "<C-f>", toggle_scope)
      map("n", "<C-f>", toggle_scope)

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
          bookmarks.remove(entry.value.book_slug, entry.value.id)
          actions.close(prompt_bufnr)
          M.show_bookmarks_telescope(book_slug, switch_callback)
        end
      end)
      map("n", "<C-d>", function()
        local entry = action_state.get_selected_entry()
        if entry then
          bookmarks.remove(entry.value.book_slug, entry.value.id)
          actions.close(prompt_bufnr)
          M.show_bookmarks_telescope(book_slug, switch_callback)
        end
      end)

      return true
    end,
  }):find()
end

function M.show_bookmarks_floating(book_slug)
  local all_bookmarks = book_slug and bookmarks.get_by_book(book_slug) or get_all_bookmarks()

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
      bookmarks.remove(bm.book_slug, bm.id)
      vim.api.nvim_win_close(win, true)
      M.show_bookmarks_floating(book_slug)
    end
  end, { buffer = buf })
end

function M.goto_bookmark(bm)
  local ctx = context.current()

  -- If different book, need to open it first
  if not ctx or not ctx.data or ctx.data.slug ~= bm.book_slug then
    local books = library.get_books()
    local book_path = nil
    local book_format = nil
    for _, book in ipairs(books) do
      if book.slug == bm.book_slug then
        book_path = book.path
        book_format = book.format
        break
      end
    end
    if book_path then
      local ui = require("ink.ui")
      local ok, book_data = library.open_book(book_path, book_format)
      if ok then
        ui.open_book(book_data)
        vim.defer_fn(function()
          local new_ctx = context.current()
          if new_ctx then
            render.render_chapter(bm.chapter, 1, new_ctx)
            vim.defer_fn(function()
              local line = find_bookmark_line(bm, new_ctx.rendered_lines)
              if line and new_ctx.content_win and vim.api.nvim_win_is_valid(new_ctx.content_win) then
                vim.api.nvim_win_set_cursor(new_ctx.content_win, {line, 0})
              end
            end, 10)
          end
        end, 100)
      else
        vim.notify("Failed to open book: " .. tostring(book_data), vim.log.levels.ERROR)
      end
    else
      vim.notify("Book not found in library", vim.log.levels.WARN)
    end
    return
  end

  -- Same book, just navigate
  if bm.chapter ~= ctx.current_chapter_idx then
    render.render_chapter(bm.chapter, 1, ctx)
    vim.defer_fn(function()
      local line = find_bookmark_line(bm, ctx.rendered_lines)
      if line and ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
        vim.api.nvim_win_set_cursor(ctx.content_win, {line, 0})
      end
    end, 10)
  else
    local line = find_bookmark_line(bm, ctx.rendered_lines)
    if line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {line, 0})
    end
  end
end

function M.show_all_bookmarks()
  local library_view = require("ink.ui.library_view")
  M.show_bookmarks_telescope(nil, function()
    library_view.show_library()
  end)
end

function M.show_book_bookmarks()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book open", vim.log.levels.WARN)
    return
  end
  local library_view = require("ink.ui.library_view")
  M.show_bookmarks_telescope(ctx.data.slug, function()
    library_view.show_library()
  end)
end

return M
