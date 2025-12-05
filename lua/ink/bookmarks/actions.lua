local data = require("ink.bookmarks.data")

local M = {}

function M.add(bookmark)
  local loaded = data.load()
  bookmark.id = tostring(os.time()) .. "_" .. math.random(1000, 9999)
  bookmark.created_at = os.time()
  table.insert(loaded.bookmarks, bookmark)
  data.save(loaded.bookmarks)
  return bookmark
end

function M.update(id, name)
  local loaded = data.load()
  for _, bm in ipairs(loaded.bookmarks) do
    if bm.id == id then
      bm.name = name
      bm.updated_at = os.time()
      break
    end
  end
  data.save(loaded.bookmarks)
end

function M.remove(id)
  local loaded = data.load()
  local new_bookmarks = {}
  for _, bm in ipairs(loaded.bookmarks) do
    if bm.id ~= id then
      table.insert(new_bookmarks, bm)
    end
  end
  data.save(new_bookmarks)
end

return M
