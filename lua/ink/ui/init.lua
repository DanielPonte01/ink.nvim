local fs = require("ink.fs")
local library = require("ink.library")
local state = require("ink.state")
local context = require("ink.ui.context")
local render = require("ink.ui.render")
local navigation = require("ink.ui.navigation")
local notes = require("ink.ui.notes")
local search = require("ink.ui.search")
local library_view = require("ink.ui.library_view")
local bookmarks_ui = require("ink.ui.bookmarks")

local M = {}

-- Re-export configuration
M.config = context.config
M.setup = context.setup

-- Re-export Navigation
M.jump_to_link = navigation.jump_to_link
M.next_chapter = navigation.next_chapter
M.prev_chapter = navigation.prev_chapter
M.handle_enter = navigation.handle_enter
M.increase_width = navigation.increase_width
M.decrease_width = navigation.decrease_width
M.reset_width = navigation.reset_width
M.toggle_justify = navigation.toggle_justify

-- Re-export Render/TOC
M.render_chapter = render.render_chapter
M.render_toc = render.render_toc
M.toggle_toc = render.toggle_toc
M.toggle_note_display = render.toggle_note_display

-- Re-export Notes/Highlights
M.add_note = notes.add_note
M.edit_note = notes.edit_note
M.remove_note = notes.remove_note
M.add_highlight = notes.add_highlight
M.remove_highlight = notes.remove_highlight

-- Re-export Search
M.search_toc = search.search_toc
M.search_content = search.search_content

-- Re-export Library
M.show_library = library_view.show_library

-- Re-export Bookmarks
M.add_bookmark = bookmarks_ui.add_bookmark
M.remove_bookmark = bookmarks_ui.remove_bookmark
M.goto_next_bookmark = bookmarks_ui.goto_next
M.goto_prev_bookmark = bookmarks_ui.goto_prev
M.show_all_bookmarks = bookmarks_ui.show_all_bookmarks
M.show_book_bookmarks = bookmarks_ui.show_book_bookmarks

function M.setup_keymaps(buf)
  local opts = { noremap = true, silent = true }
  local keymaps = context.config.keymaps or {}

  if keymaps.next_chapter then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.next_chapter, ":lua require('ink.ui').next_chapter()<CR>", opts)
  end
  if keymaps.prev_chapter then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.prev_chapter, ":lua require('ink.ui').prev_chapter()<CR>", opts)
  end
  if keymaps.activate then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.activate, ":lua require('ink.ui').handle_enter()<CR>", opts)
  end
  local jump_key = keymaps.jump_to_link or "g<CR>"
  vim.api.nvim_buf_set_keymap(buf, "n", jump_key, ":lua require('ink.ui').jump_to_link()<CR>", opts)
  if keymaps.search_toc then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.search_toc, ":lua require('ink.ui').search_toc()<CR>", opts)
  end
  if keymaps.search_content then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.search_content, ":lua require('ink.ui').search_content()<CR>", opts)
  end
  if keymaps.width_increase then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.width_increase, ":lua require('ink.ui').increase_width()<CR>", opts)
  end
  if keymaps.width_decrease then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.width_decrease, ":lua require('ink.ui').decrease_width()<CR>", opts)
  end
  if keymaps.width_reset then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.width_reset, ":lua require('ink.ui').reset_width()<CR>", opts)
  end
  if keymaps.toggle_justify then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.toggle_justify, ":lua require('ink.ui').toggle_justify()<CR>", opts)
  end
end

function M.open_book(epub_data)
  context.ctx.data = epub_data

  library.add_book({
    slug = epub_data.slug,
    title = epub_data.title,
    author = epub_data.author,
    language = epub_data.language,
    date = epub_data.date,
    description = epub_data.description,
    path = epub_data.path,
    chapter = 1,
    total_chapters = #epub_data.spine
  })

  context.ctx.default_max_width = context.config.max_width

  local function find_buf_by_name(name)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name == name then return buf end
      end
    end
    return nil
  end

  local toc_name = "ink://" .. epub_data.slug .. "/TOC"
  local content_name = "ink://" .. epub_data.slug .. "/content"
  local existing_toc = find_buf_by_name(toc_name)
  if existing_toc then vim.api.nvim_buf_delete(existing_toc, { force = true }) end
  local existing_content = find_buf_by_name(content_name)
  if existing_content then vim.api.nvim_buf_delete(existing_content, { force = true }) end

  context.ctx.toc_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(context.ctx.toc_buf, toc_name)
  vim.api.nvim_set_option_value("filetype", "ink_toc", { buf = context.ctx.toc_buf })

  context.ctx.content_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(context.ctx.content_buf, content_name)
  vim.api.nvim_set_option_value("filetype", "ink_content", { buf = context.ctx.content_buf })
  vim.api.nvim_set_option_value("syntax", "off", { buf = context.ctx.content_buf })

  vim.cmd("tabnew")
  context.ctx.content_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(context.ctx.content_win, context.ctx.content_buf)

  render.render_toc()
  render.toggle_toc()

  local saved = state.load(epub_data.slug)
  if saved then
    render.render_chapter(saved.chapter, saved.line)
    if context.ctx.content_win and vim.api.nvim_win_is_valid(context.ctx.content_win) then
      vim.api.nvim_set_current_win(context.ctx.content_win)
    end
  else
    render.render_chapter(1)
  end

  M.setup_keymaps(context.ctx.content_buf)
  M.setup_keymaps(context.ctx.toc_buf)

  local keymaps = context.config.keymaps or {}
  local keymap_opts = { noremap = true, silent = true }
  if keymaps.toggle_toc then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", keymap_opts)
    vim.api.nvim_buf_set_keymap(context.ctx.toc_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", keymap_opts)
  end

  local highlight_keymaps = context.config.highlight_keymaps or {}
  for color_name, keymap in pairs(highlight_keymaps) do
    if color_name == "remove" then
      vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", keymap, ":lua require('ink.ui').remove_highlight()<CR>", keymap_opts)
    else
      vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "v", keymap, string.format(":lua require('ink.ui').add_highlight('%s')<CR>", color_name), keymap_opts)
    end
  end

  local note_keymaps = context.config.note_keymaps or {}
  if note_keymaps.add then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", note_keymaps.add, ":lua require('ink.ui').add_note()<CR>", keymap_opts)
  end
  if note_keymaps.edit then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", note_keymaps.edit, ":lua require('ink.ui').edit_note()<CR>", keymap_opts)
  end
  if note_keymaps.remove then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", note_keymaps.remove, ":lua require('ink.ui').remove_note()<CR>", keymap_opts)
  end
  if note_keymaps.toggle_display then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", note_keymaps.toggle_display, ":lua require('ink.ui').toggle_note_display()<CR>", keymap_opts)
  end

  local bookmark_keymaps = context.config.bookmark_keymaps or {}
  if bookmark_keymaps.add then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", bookmark_keymaps.add, ":lua require('ink.ui').add_bookmark()<CR>", keymap_opts)
  end
  if bookmark_keymaps.remove then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", bookmark_keymaps.remove, ":lua require('ink.ui').remove_bookmark()<CR>", keymap_opts)
  end
  if bookmark_keymaps.next then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", bookmark_keymaps.next, ":lua require('ink.ui').goto_next_bookmark()<CR>", keymap_opts)
  end
  if bookmark_keymaps.prev then
    vim.api.nvim_buf_set_keymap(context.ctx.content_buf, "n", bookmark_keymaps.prev, ":lua require('ink.ui').goto_prev_bookmark()<CR>", keymap_opts)
  end

  local augroup = vim.api.nvim_create_augroup("Ink_" .. epub_data.slug, { clear = true })
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
      if context.ctx.content_win and vim.api.nvim_win_is_valid(context.ctx.content_win) then
        local resized_wins = vim.v.event.windows or {}
        for _, win_id in ipairs(resized_wins) do
          if win_id == context.ctx.content_win then
            local cursor = vim.api.nvim_win_get_cursor(context.ctx.content_win)
            render.render_chapter(context.ctx.current_chapter_idx, cursor[1])
            break
          end
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = augroup,
    buffer = context.ctx.content_buf,
    callback = function()
      if not context.ctx.content_win or not vim.api.nvim_win_is_valid(context.ctx.content_win) then return end
      local cursor = vim.api.nvim_win_get_cursor(context.ctx.content_win)
      local current_line = cursor[1]
      local total_lines = vim.api.nvim_buf_line_count(context.ctx.content_buf)
      local percent = math.floor((current_line / total_lines) * 100)
      if math.abs(percent - context.ctx.last_statusline_percent) >= 10 then
        context.ctx.last_statusline_percent = percent
        render.update_statusline()
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = context.ctx.content_buf,
    callback = function()
      if context.ctx.default_max_width then
        context.config.max_width = context.ctx.default_max_width
      end
    end,
  })
end

function M.open_last_book()
  local last_path = library.get_last_book_path()
  if not last_path then vim.notify("No books in library yet", vim.log.levels.INFO); return end
  if not fs.exists(last_path) then vim.notify("Last book not found: " .. last_path, vim.log.levels.ERROR); return end
  local epub = require("ink.epub")
  local ok, epub_data = pcall(epub.open, last_path)
  if not ok then vim.notify("Failed to open book: " .. tostring(epub_data), vim.log.levels.ERROR); return end
  M.open_book(epub_data)
end

return M
