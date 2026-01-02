local fs = require("ink.fs")
local library = require("ink.library")
local context = require("ink.ui.context")
local render = require("ink.ui.render")
local navigation = require("ink.ui.navigation")
local notes = require("ink.ui.notes")
local search = require("ink.ui.search")
local library_view = require("ink.ui.library_view")
local bookmarks_ui = require("ink.ui.bookmarks")
local book_loader = require("ink.ui.book_loader")
local cache_ui = require("ink.ui.cache")

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
M.increase_line_spacing = navigation.increase_line_spacing
M.decrease_line_spacing = navigation.decrease_line_spacing
M.reset_line_spacing = navigation.reset_line_spacing
M.increase_paragraph_spacing = navigation.increase_paragraph_spacing
M.decrease_paragraph_spacing = navigation.decrease_paragraph_spacing
M.reset_paragraph_spacing = navigation.reset_paragraph_spacing

-- Re-export Render/TOC
M.render_chapter = render.render_chapter
M.render_toc = render.render_toc
M.toggle_toc = render.toggle_toc
M.toggle_note_display = render.toggle_note_display
M.toggle_glossary_display = render.toggle_glossary_display
M.invalidate_glossary_cache = render.invalidate_glossary_cache

-- Re-export Notes/Highlights
M.add_note = notes.add_note
M.add_note_on_selection = notes.add_note_on_selection
M.edit_note = notes.edit_note
M.remove_note = notes.remove_note
M.add_highlight = notes.add_highlight
M.remove_highlight = notes.remove_highlight
M.change_highlight_color = notes.change_highlight_color

-- Re-export Search
M.search_toc = search.search_toc
M.search_content = search.search_content

-- Re-export Library
M.show_library = library_view.show_library

-- Re-export Bookmarks
M.add_bookmark = bookmarks_ui.add_bookmark
M.edit_bookmark = bookmarks_ui.edit_bookmark
M.remove_bookmark = bookmarks_ui.remove_bookmark
M.goto_next_bookmark = bookmarks_ui.goto_next
M.goto_prev_bookmark = bookmarks_ui.goto_prev
M.show_all_bookmarks = bookmarks_ui.show_all_bookmarks
M.show_book_bookmarks = bookmarks_ui.show_book_bookmarks

-- Re-export Cache management
M.show_clear_cache_ui = cache_ui.show_clear_cache_ui
M.clear_book_cache = cache_ui.clear_book_cache
M.clear_all_cache = cache_ui.clear_all_cache

-- Glossary functions
function M.add_glossary_from_selection()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local glossary_ui = require("ink.glossary.ui")
  glossary_ui.add_from_selection(ctx.data.slug, function(entry)
    if entry then
      vim.notify("Glossary entry '" .. entry.term .. "' saved", vim.log.levels.INFO)
      -- Re-render to show new glossary marks
      render.invalidate_glossary_cache(ctx)
      local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
      render.render_chapter(ctx.current_chapter_idx, cursor, ctx)
    end
  end)
end

function M.add_glossary_under_cursor()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local glossary_ui = require("ink.glossary.ui")

  -- Check if cursor is on an existing glossary term
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local line = cursor[1]
  local col = cursor[2]

  local glossary_match = glossary_ui.get_match_at_cursor(line, col)

  if glossary_match then
    -- Cursor is on existing glossary term - open full edit
    local entry = ctx.glossary_detection_index.entries[glossary_match.entry_id]
    if entry then
      glossary_ui.show_edit_entry_modal(ctx.data.slug, entry, function(updated_entry)
        if updated_entry then
          vim.notify("Glossary entry '" .. updated_entry.term .. "' updated", vim.log.levels.INFO)
          render.invalidate_glossary_cache(ctx)
          local cursor_pos = vim.api.nvim_win_get_cursor(ctx.content_win)
          render.render_chapter(ctx.current_chapter_idx, cursor_pos, ctx)
        end
      end, true)  -- true = allow changing type
    end
  else
    -- No glossary term under cursor - require visual selection to add new term
    vim.notify("Select text to add to glossary", vim.log.levels.INFO)
  end
end

function M.preview_glossary()
  local ctx = context.current()
  if not ctx then return end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  local glossary_ui = require("ink.glossary.ui")
  local glossary_match = glossary_ui.get_match_at_cursor(line, col)

  if glossary_match then
    glossary_ui.show_entry_preview(glossary_match)
  else
    vim.notify("No glossary term at cursor", vim.log.levels.INFO)
  end
end

function M.show_glossary_browser()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local glossary_ui = require("ink.glossary.ui")
  glossary_ui.show_glossary_browser(ctx.data.slug)
end

function M.show_glossary_graph()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local glossary_ui = require("ink.glossary.ui")
  glossary_ui.show_full_graph(ctx.data.slug)
end

function M.show_term_graph_under_cursor()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  local glossary_ui = require("ink.glossary.ui")

  -- Check if cursor is on a glossary term
  local glossary_match = glossary_ui.get_match_at_cursor(line, col)

  if glossary_match then
    local entry = ctx.glossary_detection_index.entries[glossary_match.entry_id]
    if entry then
      glossary_ui.show_term_graph(ctx.data.slug, entry)
    end
  else
    vim.notify("No glossary term at cursor", vim.log.levels.INFO)
  end
end

function M.edit_glossary_under_cursor()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  local glossary_ui = require("ink.glossary.ui")
  local glossary = require("ink.glossary")

  -- Check if cursor is on a glossary term
  local glossary_match = glossary_ui.get_match_at_cursor(line, col)

  if glossary_match then
    -- Get the entry
    local entry = ctx.glossary_detection_index.entries[glossary_match.entry_id]
    if entry then
      -- Quick edit: only definition, keep type unchanged
      glossary_ui.show_edit_entry_modal(ctx.data.slug, entry, function(updated_entry)
        if updated_entry then
          vim.notify("Glossary entry '" .. updated_entry.term .. "' updated", vim.log.levels.INFO)
          render.invalidate_glossary_cache(ctx)
          local cursor_pos = vim.api.nvim_win_get_cursor(ctx.content_win)
          render.render_chapter(ctx.current_chapter_idx, cursor_pos, ctx)
        end
      end, false)  -- false = only edit definition, not type
    end
  else
    vim.notify("No glossary term at cursor. Use <leader>ga to add one.", vim.log.levels.INFO)
  end
end

function M.remove_glossary_under_cursor()
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  local glossary_ui = require("ink.glossary.ui")
  local glossary = require("ink.glossary")

  -- Check if cursor is on a glossary term
  local glossary_match = glossary_ui.get_match_at_cursor(line, col)

  if glossary_match then
    -- Get the entry
    local entry = ctx.glossary_detection_index.entries[glossary_match.entry_id]
    if entry then
      -- Use the centralized removal function
      glossary_ui.remove_glossary_entry(ctx.data.slug, entry)
    end
  else
    vim.notify("No glossary term at cursor", vim.log.levels.INFO)
  end
end

function M.open_book(epub_data)
  book_loader.open_book(epub_data)
end

function M.open_last_book()
  local last_path = library.get_last_book_path()
  if not last_path then vim.notify("No books in library yet", vim.log.levels.INFO); return end
  if not fs.exists(last_path) then vim.notify("Last book not found: " .. last_path, vim.log.levels.ERROR); return end

  -- Get book format from library
  local lib = library.load()
  local book_format = nil
  for _, book in ipairs(lib.books) do
    if book.path == last_path then
      book_format = book.format
      break
    end
  end

  local ok, book_data = library.open_book(last_path, book_format)
  if not ok then vim.notify("Failed to open book: " .. tostring(book_data), vim.log.levels.ERROR); return end
  M.open_book(book_data)
end

return M
