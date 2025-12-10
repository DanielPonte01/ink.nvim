-- lua/ink/ui/book_loader.lua
-- Responsabilidade: Criação e configuração de buffers/contexto para livros

local library = require("ink.library")
local state = require("ink.state")
local context = require("ink.ui.context")
local render = require("ink.ui.render")

local M = {}

-- Helper to find buffer by name
local function find_buf_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local buf_name = vim.api.nvim_buf_get_name(buf)
      if buf_name == name then return buf end
    end
  end
  return nil
end

-- Create TOC and content buffers
function M.create_book_buffers(slug)
  local toc_name = "ink://" .. slug .. "/TOC"
  local content_name = "ink://" .. slug .. "/content"

  -- Delete existing buffers if they exist
  local existing_toc = find_buf_by_name(toc_name)
  if existing_toc then
    context.remove(existing_toc)
    vim.api.nvim_buf_delete(existing_toc, { force = true })
  end
  local existing_content = find_buf_by_name(content_name)
  if existing_content then
    context.remove(existing_content)
    vim.api.nvim_buf_delete(existing_content, { force = true })
  end

  -- Create content buffer
  local content_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(content_buf, content_name)
  vim.api.nvim_set_option_value("filetype", "ink_content", { buf = content_buf })
  vim.api.nvim_set_option_value("syntax", "off", { buf = content_buf })

  -- Create TOC buffer
  local toc_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(toc_buf, toc_name)
  vim.api.nvim_set_option_value("filetype", "ink_toc", { buf = toc_buf })

  return content_buf, toc_buf
end

-- Setup context for book
function M.setup_book_context(content_buf, toc_buf, book_data)
  local ctx = context.create(content_buf)
  ctx.data = book_data
  ctx.toc_buf = toc_buf
  ctx.content_buf = content_buf
  ctx.default_max_width = context.config.max_width

  return ctx
end

-- Setup basic navigation keymaps
function M.setup_basic_keymaps(buf)
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

-- Setup all book-specific keymaps
function M.setup_book_keymaps(content_buf, toc_buf)
  local keymap_opts = { noremap = true, silent = true }
  local keymaps = context.config.keymaps or {}

  -- Setup basic keymaps for both buffers
  M.setup_basic_keymaps(content_buf)
  M.setup_basic_keymaps(toc_buf)

  -- TOC toggle keymap
  if keymaps.toggle_toc then
    vim.api.nvim_buf_set_keymap(content_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", keymap_opts)
    vim.api.nvim_buf_set_keymap(toc_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", keymap_opts)
  end

  -- Highlight keymaps (content buffer only)
  local highlight_keymaps = context.config.highlight_keymaps or {}
  for color_name, keymap in pairs(highlight_keymaps) do
    if color_name == "remove" then
      vim.api.nvim_buf_set_keymap(content_buf, "n", keymap, ":lua require('ink.ui').remove_highlight()<CR>", keymap_opts)
    else
      vim.api.nvim_buf_set_keymap(content_buf, "v", keymap, string.format(":lua require('ink.ui').add_highlight('%s')<CR>", color_name), keymap_opts)
    end
  end

  -- Note keymaps (content buffer only)
  local note_keymaps = context.config.note_keymaps or {}
  if note_keymaps.add then
    vim.api.nvim_buf_set_keymap(content_buf, "n", note_keymaps.add, ":lua require('ink.ui').add_note()<CR>", keymap_opts)
  end
  if note_keymaps.edit then
    vim.api.nvim_buf_set_keymap(content_buf, "n", note_keymaps.edit, ":lua require('ink.ui').edit_note()<CR>", keymap_opts)
  end
  if note_keymaps.remove then
    vim.api.nvim_buf_set_keymap(content_buf, "n", note_keymaps.remove, ":lua require('ink.ui').remove_note()<CR>", keymap_opts)
  end
  if note_keymaps.toggle_display then
    vim.api.nvim_buf_set_keymap(content_buf, "n", note_keymaps.toggle_display, ":lua require('ink.ui').toggle_note_display()<CR>", keymap_opts)
  end

  -- Bookmark keymaps (content buffer only)
  local bookmark_keymaps = context.config.bookmark_keymaps or {}
  if bookmark_keymaps.add then
    vim.api.nvim_buf_set_keymap(content_buf, "n", bookmark_keymaps.add, ":lua require('ink.ui').add_bookmark()<CR>", keymap_opts)
  end
  if bookmark_keymaps.remove then
    vim.api.nvim_buf_set_keymap(content_buf, "n", bookmark_keymaps.remove, ":lua require('ink.ui').remove_bookmark()<CR>", keymap_opts)
  end
  if bookmark_keymaps.next then
    vim.api.nvim_buf_set_keymap(content_buf, "n", bookmark_keymaps.next, ":lua require('ink.ui').goto_next_bookmark()<CR>", keymap_opts)
  end
  if bookmark_keymaps.prev then
    vim.api.nvim_buf_set_keymap(content_buf, "n", bookmark_keymaps.prev, ":lua require('ink.ui').goto_prev_bookmark()<CR>", keymap_opts)
  end
end

-- Setup autocmds for book
function M.setup_book_autocmds(content_buf, slug)
  local augroup = vim.api.nvim_create_augroup("Ink_" .. slug, { clear = true })

  -- Window resize handler
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
      local current_ctx = context.get(content_buf)
      if current_ctx and current_ctx.content_win and vim.api.nvim_win_is_valid(current_ctx.content_win) then
        local resized_wins = vim.v.event.windows or {}
        for _, win_id in ipairs(resized_wins) do
          if win_id == current_ctx.content_win then
            local cursor = vim.api.nvim_win_get_cursor(current_ctx.content_win)
            render.render_chapter(current_ctx.current_chapter_idx, cursor[1], current_ctx)
            break
          end
        end
      end
    end,
  })

  -- Cursor move handler for statusline updates
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = augroup,
    buffer = content_buf,
    callback = function()
      local current_ctx = context.get(content_buf)
      if not current_ctx or not current_ctx.content_win or not vim.api.nvim_win_is_valid(current_ctx.content_win) then return end
      local cursor = vim.api.nvim_win_get_cursor(current_ctx.content_win)
      local current_line = cursor[1]
      local total_lines = vim.api.nvim_buf_line_count(current_ctx.content_buf)
      local percent = math.floor((current_line / total_lines) * 100)
      if math.abs(percent - current_ctx.last_statusline_percent) >= 10 then
        current_ctx.last_statusline_percent = percent
        render.update_statusline(current_ctx)
      end
    end,
  })

  -- Buffer delete handler
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = content_buf,
    callback = function()
      local current_ctx = context.get(content_buf)
      if current_ctx and current_ctx.default_max_width then
        context.config.max_width = current_ctx.default_max_width
      end
      context.remove(content_buf)
    end,
  })
end

-- Main function to open a book
function M.open_book(book_data)
  -- Register book in library
  library.add_book({
    slug = book_data.slug,
    title = book_data.title,
    author = book_data.author,
    language = book_data.language,
    date = book_data.date,
    description = book_data.description,
    path = book_data.path,
    chapter = 1,
    total_chapters = #book_data.spine
  })

  -- Create buffers
  local content_buf, toc_buf = M.create_book_buffers(book_data.slug)

  -- Setup context
  local ctx = M.setup_book_context(content_buf, toc_buf, book_data)

  -- Create new tab and set content window
  vim.cmd("tabnew")
  ctx.content_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ctx.content_win, content_buf)

  -- Render TOC and toggle it open
  render.render_toc(ctx)
  render.toggle_toc(ctx)

  -- Load saved position or render first chapter
  local saved = state.load(book_data.slug)
  if saved then
    render.render_chapter(saved.chapter, saved.line, ctx)
    if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
    end
  else
    render.render_chapter(1, nil, ctx)
  end

  -- Setup keymaps and autocmds
  M.setup_book_keymaps(content_buf, toc_buf)
  M.setup_book_autocmds(content_buf, book_data.slug)
end

return M
