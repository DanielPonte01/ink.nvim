local fs = require("ink.fs")

local M = {}

-- Pretty-print JSON encoder
local function json_pretty_encode(data, indent)
  indent = indent or 0
  local spacing = string.rep("  ", indent)
  local spacing_inner = string.rep("  ", indent + 1)

  if type(data) == "table" then
    -- Check if array or object
    local is_array = #data > 0 or next(data) == nil
    if is_array and #data > 0 then
      -- Check if it's really an array (sequential numeric keys)
      for k, _ in pairs(data) do
        if type(k) ~= "number" then
          is_array = false
          break
        end
      end
    end

    if is_array then
      if #data == 0 then
        return "[]"
      end
      local items = {}
      for _, v in ipairs(data) do
        table.insert(items, spacing_inner .. json_pretty_encode(v, indent + 1))
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. spacing .. "]"
    else
      local items = {}
      for k, v in pairs(data) do
        local key = '"' .. tostring(k) .. '"'
        table.insert(items, spacing_inner .. key .. ": " .. json_pretty_encode(v, indent + 1))
      end
      if #items == 0 then
        return "{}"
      end
      -- Sort keys for consistent output
      table.sort(items)
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. spacing .. "}"
    end
  elseif type(data) == "string" then
    -- Escape special characters
    local escaped = data:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. escaped .. '"'
  elseif type(data) == "number" then
    return tostring(data)
  elseif type(data) == "boolean" then
    return data and "true" or "false"
  elseif data == nil then
    return "null"
  else
    return '"' .. tostring(data) .. '"'
  end
end

-- Get the library file path
local function get_library_path()
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  fs.ensure_dir(data_dir)
  return data_dir .. "/library.json"
end

-- Load library from disk
function M.load()
  local path = get_library_path()

  if not fs.exists(path) then
    return { books = {}, last_book_path = nil }
  end

  local content = fs.read_file(path)
  if not content then
    return { books = {}, last_book_path = nil }
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data then
    return { books = {}, last_book_path = nil }
  end

  return data
end

-- Save library to disk (pretty-printed for easy manual editing)
function M.save(library)
  local path = get_library_path()
  local data = json_pretty_encode(library)

  local file = io.open(path, "w")
  if file then
    file:write(data)
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

return M
