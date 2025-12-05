local fs = require("ink.fs")
local data = require("ink.data")
local migrate = require("ink.data.migrate")

local M = {}

function M.save(slug, state)
  migrate.migrate_book(slug)
  local path = data.get_book_dir(slug) .. "/state.json"

  local file = io.open(path, "w")
  if file then
    file:write(vim.json.encode(state))
    file:close()
  end
end

function M.load(slug)
  migrate.migrate_book(slug)
  local path = data.get_book_dir(slug) .. "/state.json"

  local content = fs.read_file(path)
  if content then
    local ok, state = pcall(vim.json.decode, content)
    if ok then return state end
  end
  return nil
end

return M
