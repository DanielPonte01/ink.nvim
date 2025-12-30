local fs = require("ink.fs")
local data = require("ink.data")
-- local migrate = require("ink.data.migrate")  -- TODO: Add migration when needed

local M = {}

function M.get_file_path(slug)
  -- migrate.migrate_glossary()  -- TODO: Add migration support
  return data.get_book_dir(slug) .. "/glossary.json"
end

function M.save(slug, entries, custom_types)
  local path = M.get_file_path(slug)
  local json = data.json_encode({
    entries = entries or {},
    custom_types = custom_types or {}
  })
  local file = io.open(path, "w")
  if file then
    file:write(json)
    file:close()
    return true
  end
  return false
end

function M.load(slug)
  local path = M.get_file_path(slug)
  if not fs.exists(path) then
    return { entries = {}, custom_types = {} }
  end
  local content = fs.read_file(path)
  if not content then
    return { entries = {}, custom_types = {} }
  end
  local ok, loaded = pcall(vim.json.decode, content)
  if not ok or not loaded then
    return { entries = {}, custom_types = {} }
  end
  -- Ensure both fields exist
  loaded.entries = loaded.entries or {}
  loaded.custom_types = loaded.custom_types or {}
  return loaded
end

return M
