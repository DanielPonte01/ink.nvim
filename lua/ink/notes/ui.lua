-- UI for notes browsing
local query = require("ink.notes.query")
local library = require("ink.library")

local M = {}

-- Helper to find book by slug
local function find_book_by_slug(slug)
  local books = library.get_books()
  for _, book in ipairs(books) do
    if book.slug == slug then
      return book
    end
  end
  return nil
end

-- Navigate to a note (opens book if needed and jumps to highlight)
local function goto_note(note)
  if not note then return end

  local ui = require("ink.ui")
  local context = require("ink.ui.context")
  local render = require("ink.ui.render")
  local util = require("ink.ui.util")

  -- Check if book is already open
  local ctx = context.current()
  local current_slug = ctx and ctx.data and ctx.data.slug

  if current_slug ~= note.book_slug then
    -- Need to open the book first
    local book = find_book_by_slug(note.book_slug)
    if not book then
      vim.notify("Book not found in library: " .. note.book_slug, vim.log.levels.ERROR)
      return
    end

    -- Open the book
    local epub = require("ink.epub")
    local epub_data = epub.open(book.path)
    if not epub_data then
      vim.notify("Failed to open book: " .. book.path, vim.log.levels.ERROR)
      return
    end

    ui.open_book(epub_data)
  end

  -- Now navigate to the chapter with the highlight
  ctx = context.current()
  if not ctx then return end

  -- Render the chapter if not already there
  if ctx.current_chapter_idx ~= note.chapter then
    render.render_chapter(note.chapter)
  end

  -- Find the highlight position in the buffer
  local lines = vim.api.nvim_buf_get_lines(ctx.content_buf, 0, -1, false)
  local start_line = util.find_text_position(
    lines,
    note.text,
    note.context_before,
    note.context_after
  )

  if start_line then
    -- Jump to the highlight
    local wins = vim.fn.win_findbuf(ctx.content_buf)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      vim.api.nvim_win_set_cursor(wins[1], { start_line, 0 })
      vim.cmd("normal! zz") -- Center screen
    end
  else
    vim.notify("Could not find highlight position in chapter", vim.log.levels.WARN)
  end
end

-- Telescope picker for notes
local function show_notes_telescope(notes, title)
  local has_telescope, telescope = pcall(require, "telescope")
  if not has_telescope then
    return false
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  pickers
    .new({}, {
      prompt_title = title,
      finder = finders.new_table({
        results = notes,
        entry_maker = function(note)
          -- Display format: [Book] Chapter X: First 60 chars of note
          local note_preview = note.note
          if #note_preview > 60 then
            note_preview = note_preview:sub(1, 57) .. "..."
          end

          local display = string.format(
            "[%s] Ch %d: %s",
            note.book_title or note.book_slug,
            note.chapter,
            note_preview
          )

          return {
            value = note,
            display = display,
            ordinal = (note.book_title or "") .. " " .. note.note .. " " .. note.text,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Note Details",
        define_preview = function(self, entry)
          local note = entry.value
          local lines = {}

          -- Book info
          table.insert(lines, "Book: " .. (note.book_title or note.book_slug))
          if note.book_author then
            table.insert(lines, "Author: " .. note.book_author)
          end
          table.insert(lines, "Chapter: " .. note.chapter)
          if note.color then
            table.insert(lines, "Color: " .. note.color)
          end
          table.insert(lines, "")

          -- Highlight text
          table.insert(lines, "Highlighted text:")
          table.insert(lines, "────────────────")
          -- Word wrap the highlight text
          local text_lines = vim.split(note.text, "\n")
          for _, line in ipairs(text_lines) do
            table.insert(lines, line)
          end
          table.insert(lines, "")

          -- Note
          table.insert(lines, "Note:")
          table.insert(lines, "─────")
          local note_lines = vim.split(note.note, "\n")
          for _, line in ipairs(note_lines) do
            table.insert(lines, line)
          end

          -- Context (if available)
          if note.context_before or note.context_after then
            table.insert(lines, "")
            table.insert(lines, "Context:")
            table.insert(lines, "────────")
            if note.context_before then
              table.insert(lines, "..." .. note.context_before)
            end
            table.insert(lines, ">>> " .. note.text:sub(1, 50) .. (#note.text > 50 and "..." or ""))
            if note.context_after then
              table.insert(lines, note.context_after .. "...")
            end
          end

          -- Timestamps
          if note.created_at or note.updated_at then
            table.insert(lines, "")
            if note.created_at then
              table.insert(lines, "Created: " .. os.date("%Y-%m-%d %H:%M", note.created_at))
            end
            if note.updated_at then
              table.insert(lines, "Updated: " .. os.date("%Y-%m-%d %H:%M", note.updated_at))
            end
          end

          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            goto_note(selection.value)
          end
        end)
        return true
      end,
    })
    :find()

  return true
end

-- Fallback floating window for notes
local function show_notes_floating(notes, title)
  if #notes == 0 then
    vim.notify("No notes found", vim.log.levels.INFO)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"

  -- Build display lines
  local lines = { title, string.rep("─", 60), "" }
  local note_map = {} -- Map line number to note

  for i, note in ipairs(notes) do
    local start_line = #lines + 1
    table.insert(lines, string.format("[%d] %s - Chapter %d", i, note.book_title or note.book_slug, note.chapter))
    table.insert(lines, "    Highlight: " .. note.text:sub(1, 60) .. (#note.text > 60 and "..." or ""))
    table.insert(lines, "    Note: " .. note.note:sub(1, 80) .. (#note.note > 80 and "..." or ""))
    if note.color then
      table.insert(lines, "    Color: " .. note.color)
    end
    table.insert(lines, "")

    -- Map all lines of this entry to the note
    for j = start_line, #lines do
      note_map[j] = note
    end
  end

  table.insert(lines, "")
  table.insert(lines, "Press <CR> to open note, q to close")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Create floating window
  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  -- Keymaps
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local note = note_map[cursor[1]]
    if note then
      vim.api.nvim_win_close(win, true)
      goto_note(note)
    end
  end, { buffer = buf, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, nowait = true })
end

-- Show all notes across all books
function M.show_all_notes()
  local books = library.get_books()

  -- Check if we need async loading
  if #books >= 20 then
    vim.notify("Loading notes...", vim.log.levels.INFO)
    query.get_all_notes_async(function(notes)
      vim.schedule(function()
        if #notes == 0 then
          vim.notify("No notes found", vim.log.levels.INFO)
          return
        end

        local success = show_notes_telescope(notes, "All Notes (" .. #notes .. ")")
        if not success then
          show_notes_floating(notes, "All Notes")
        end
      end)
    end)
  else
    local notes = query.get_all_notes()
    if #notes == 0 then
      vim.notify("No notes found", vim.log.levels.INFO)
      return
    end

    local success = show_notes_telescope(notes, "All Notes (" .. #notes .. ")")
    if not success then
      show_notes_floating(notes, "All Notes")
    end
  end
end

-- Show notes for current book
function M.show_book_notes()
  local context = require("ink.ui.context")
  local ctx = context.current()

  if not ctx or not ctx.data then
    vim.notify("No book is currently open", vim.log.levels.WARN)
    return
  end

  local slug = ctx.data.slug
  local notes = query.get_book_notes(slug)

  if #notes == 0 then
    vim.notify("No notes in current book", vim.log.levels.INFO)
    return
  end

  -- Add book metadata
  for _, note in ipairs(notes) do
    note.book_title = ctx.data.title
    note.book_author = ctx.data.author
  end

  local success = show_notes_telescope(notes, "Notes in " .. ctx.data.title .. " (" .. #notes .. ")")
  if not success then
    show_notes_floating(notes, "Notes in " .. ctx.data.title)
  end
end

return M
