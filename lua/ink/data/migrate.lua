local fs = require("ink.fs")
local data = require("ink.data")

local M = {}

-- Migrate old data files to new book directory structure
function M.migrate_book(slug)
  local data_dir = data.get_data_dir()
  local book_dir = data.get_book_dir(slug)

  local migrations = {
    { old = slug .. ".json", new = "state.json" },
    { old = slug .. "_highlights.json", new = "highlights.json" },
  }

  for _, m in ipairs(migrations) do
    local old_path = data_dir .. "/" .. m.old
    local new_path = book_dir .. "/" .. m.new

    if fs.exists(old_path) and not fs.exists(new_path) then
      local content = fs.read_file(old_path)
      if content then
        local file = io.open(new_path, "w")
        if file then
          file:write(content)
          file:close()
          os.remove(old_path)
        end
      end
    end
  end
end

-- Migrate bookmarks from global file to per-book files
function M.migrate_bookmarks()
  local data_dir = data.get_data_dir()
  local old_path = data_dir .. "/bookmarks.json"

  if not fs.exists(old_path) then return end

  local content = fs.read_file(old_path)
  if not content then return end

  local ok, old_data = pcall(vim.json.decode, content)
  if not ok or not old_data or not old_data.bookmarks then return end

  -- Group bookmarks by book slug
  local by_book = {}
  for _, bm in ipairs(old_data.bookmarks) do
    local slug = bm.slug
    if slug then
      by_book[slug] = by_book[slug] or {}
      table.insert(by_book[slug], bm)
    end
  end

  -- Save each book's bookmarks to its own file
  for slug, bookmarks in pairs(by_book) do
    local book_dir = data.get_book_dir(slug)
    local new_path = book_dir .. "/bookmarks.json"

    if not fs.exists(new_path) then
      local json = data.json_encode({ bookmarks = bookmarks })
      local file = io.open(new_path, "w")
      if file then
        file:write(json)
        file:close()
      end
    end
  end

  -- Rename old file as backup
  os.rename(old_path, old_path .. ".bak")
end

return M
