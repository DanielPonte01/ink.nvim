-- Query functions for notes
local user_highlights = require("ink.user_highlights")
local library = require("ink.library")
local fs = require("ink.fs")
local data = require("ink.data")

local M = {}

-- Get all notes from a specific book
-- Returns: array of {book_slug, book_title, book_author, chapter, text, note, color, context_before, context_after, created_at, updated_at}
function M.get_book_notes(slug)
  local highlights_path = data.get_book_dir(slug) .. "/highlights.json"

  if not fs.exists(highlights_path) then
    return {}
  end

  local content = fs.read_file(highlights_path)
  if not content then
    return {}
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data or not data.highlights then
    return {}
  end

  -- Filter early: only highlights with notes
  local notes = {}
  for _, h in ipairs(data.highlights) do
    if h.note and h.note ~= "" then
      table.insert(notes, {
        book_slug = slug,
        chapter = h.chapter,
        text = h.text,
        note = h.note,
        color = h.color,
        context_before = h.context_before,
        context_after = h.context_after,
        created_at = h.created_at,
        updated_at = h.updated_at,
      })
    end
  end

  return notes
end

-- Get all notes from all books in library
-- Returns: array of {book_slug, book_title, book_author, chapter, text, note, color, context_before, context_after, created_at, updated_at}
function M.get_all_notes()
  local books = library.get_books()
  local all_notes = {}

  for _, book in ipairs(books) do
    local book_notes = M.get_book_notes(book.slug)

    -- Add book metadata to each note
    for _, note in ipairs(book_notes) do
      note.book_title = book.title
      note.book_author = book.author
      table.insert(all_notes, note)
    end
  end

  -- Sort by updated_at (most recent first)
  table.sort(all_notes, function(a, b)
    local a_time = a.updated_at or a.created_at or 0
    local b_time = b.updated_at or b.created_at or 0
    return a_time > b_time
  end)

  return all_notes
end

-- Async version for large libraries (≥20 books)
function M.get_all_notes_async(callback)
  local books = library.get_books()

  -- If small library, just use sync version
  if #books < 20 then
    callback(M.get_all_notes())
    return
  end

  -- Async processing
  local all_notes = {}
  local processed = 0
  local total = #books

  local function process_next(idx)
    if idx > total then
      -- Sort by updated_at (most recent first)
      table.sort(all_notes, function(a, b)
        local a_time = a.updated_at or a.created_at or 0
        local b_time = b.updated_at or b.created_at or 0
        return a_time > b_time
      end)
      callback(all_notes)
      return
    end

    local book = books[idx]
    local book_notes = M.get_book_notes(book.slug)

    -- Add book metadata
    for _, note in ipairs(book_notes) do
      note.book_title = book.title
      note.book_author = book.author
      table.insert(all_notes, note)
    end

    processed = processed + 1

    -- Yield to event loop every 5 books
    if processed % 5 == 0 then
      vim.schedule(function()
        process_next(idx + 1)
      end)
    else
      process_next(idx + 1)
    end
  end

  process_next(1)
end

return M
