local fs = require("ink.fs")
local data = require("ink.data")

local M = {}

local function get_library_path()
  fs.ensure_dir(data.get_data_dir())
  return data.get_data_dir() .. "/library.json"
end

function M.load()
  local path = get_library_path()

  if not fs.exists(path) then
    return { books = {}, last_book_path = nil }
  end

  local content = fs.read_file(path)
  if not content then
    return { books = {}, last_book_path = nil }
  end

  local ok, lib = pcall(vim.json.decode, content)
  if not ok or not lib then
    return { books = {}, last_book_path = nil }
  end

  return lib
end

function M.save(library)
  local path = get_library_path()
  local json = data.json_encode(library)

  local file = io.open(path, "w")
  if file then
    file:write(json)
    file:close()
    return true
  end
  return false
end

-- Add or update a book in the library
function M.add_book(book_info)
  local library = M.load()

  -- Find existing book by slug or path
  local found_idx = nil
  for i, book in ipairs(library.books) do
    if book.slug == book_info.slug or book.path == book_info.path then
      found_idx = i
      break
    end
  end

  local book_entry = {
    slug = book_info.slug,
    title = book_info.title or "Unknown",
    author = book_info.author or "Unknown",
    language = book_info.language,
    date = book_info.date,
    description = book_info.description,
    path = book_info.path,
    last_opened = os.time(),
    chapter = book_info.chapter or 1,
    total_chapters = book_info.total_chapters or 1
  }

  if found_idx then
    -- Update existing
    library.books[found_idx] = book_entry
  else
    -- Add new
    table.insert(library.books, book_entry)
  end

  -- Update last book path
  library.last_book_path = book_info.path

  M.save(library)
  return book_entry
end

-- Update reading progress for a book
function M.update_progress(slug, chapter, total_chapters)
  local library = M.load()

  for i, book in ipairs(library.books) do
    if book.slug == slug then
      library.books[i].chapter = chapter
      library.books[i].total_chapters = total_chapters
      library.books[i].last_opened = os.time()
      library.last_book_path = book.path
      M.save(library)
      return true
    end
  end

  return false
end

-- Get all books sorted by last opened (most recent first)
function M.get_books()
  local library = M.load()
  local books = library.books or {}

  -- Sort by last_opened descending
  table.sort(books, function(a, b)
    return (a.last_opened or 0) > (b.last_opened or 0)
  end)

  return books
end

-- Get last opened book path
function M.get_last_book_path()
  local library = M.load()
  return library.last_book_path
end

-- Remove a book from library
function M.remove_book(slug)
  local library = M.load()
  local new_books = {}

  for _, book in ipairs(library.books) do
    if book.slug ~= slug then
      table.insert(new_books, book)
    end
  end

  library.books = new_books
  M.save(library)
end

-- Format last opened time as relative string
function M.format_last_opened(timestamp)
  if not timestamp then return "Never" end

  local now = os.time()
  local diff = now - timestamp

  if diff < 60 then
    return "Just now"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins .. " min ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours .. "h ago"
  elseif diff < 604800 then
    local days = math.floor(diff / 86400)
    return days .. "d ago"
  else
    return os.date("%Y-%m-%d", timestamp)
  end
end

-- Scan directory for EPUB files and add them to library (async version)
function M.scan_directory(directory, callback)
  local epub = require("ink.epub")

  -- Expand and normalize directory path
  directory = vim.fn.fnamemodify(vim.fn.expand(directory), ":p")

  if not fs.exists(directory) then
    if callback then callback(nil, "Directory not found: " .. directory) end
    return
  end

  -- Find all .epub files recursively using vim.loop (async)
  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)
  local epub_files = {}
  local buffer = ""

  local handle = vim.loop.spawn("find", {
    args = { directory, "-type", "f", "-name", "*.epub" },
    stdio = { nil, stdout, stderr }
  }, function(code, signal)
    -- Process completed
    stdout:close()
    stderr:close()
  end)

  if not handle then
    if callback then callback(nil, "Failed to scan directory") end
    return
  end

  -- Read stdout (file paths)
  stdout:read_start(function(err, data)
    if err then
      if callback then
        vim.schedule(function()
          callback(nil, "Error reading find output: " .. err)
        end)
      end
      return
    end

    if data then
      buffer = buffer .. data
      -- Process complete lines
      for line in buffer:gmatch("([^\n]*)\n") do
        if line ~= "" then
          table.insert(epub_files, line)
        end
      end
      -- Keep incomplete line in buffer
      buffer = buffer:match("[^\n]*$") or ""
    else
      -- EOF - process remaining buffer
      if buffer ~= "" then
        table.insert(epub_files, buffer)
      end

      -- Now process all found EPUBs
      vim.schedule(function()
        M.process_epub_files(epub_files, callback)
      end)
    end
  end)

  -- Read stderr (ignore errors for now)
  stderr:read_start(function(err, data)
    -- Ignore stderr
  end)
end

-- Process EPUB files one by one with progress updates
function M.process_epub_files(epub_files, callback)
  local epub = require("ink.epub")
  local added = 0
  local skipped = 0
  local errors = {}
  local total = #epub_files

  if total == 0 then
    if callback then
      callback({
        total = 0,
        added = 0,
        skipped = 0,
        errors = {}
      })
    end
    return
  end

  local current_idx = 0

  local function process_next()
    current_idx = current_idx + 1

    if current_idx > total then
      -- All done
      if callback then
        callback({
          total = total,
          added = added,
          skipped = skipped,
          errors = errors
        })
      end
      return
    end

    local epub_path = epub_files[current_idx]

    -- Show progress
    vim.schedule(function()
      vim.notify(
        string.format("Processing EPUB %d/%d: %s", current_idx, total, vim.fn.fnamemodify(epub_path, ":t")),
        vim.log.levels.INFO
      )
    end)

    -- Process this EPUB (skip TOC generation for performance)
    local ok, data = pcall(epub.open, epub_path, { skip_toc_generation = true })

    vim.schedule(function()
      if ok then
        local book_info = {
          slug = data.slug,
          title = data.title,
          author = data.author,
          language = data.language,
          date = data.date,
          description = data.description,
          path = data.path,
          total_chapters = #data.spine
        }

        -- Check if book already exists
        local library = M.load()
        local exists = false
        for _, book in ipairs(library.books) do
          if book.slug == book_info.slug or book.path == book_info.path then
            exists = true
            break
          end
        end

        if not exists then
          M.add_book(book_info)
          added = added + 1
        else
          skipped = skipped + 1
        end
      else
        table.insert(errors, { path = epub_path, error = tostring(data) })
      end

      -- Process next file after small delay to keep UI responsive
      vim.defer_fn(process_next, 10)
    end)
  end

  -- Start processing
  process_next()
end

return M
