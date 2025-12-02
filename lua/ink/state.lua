local fs = require("ink.fs")

local M = {}

local function get_state_dir()
  return vim.fn.stdpath("data") .. "/ink.nvim"
end

function M.save(slug, state)
  local dir = get_state_dir()
  fs.ensure_dir(dir)
  local path = dir .. "/" .. slug .. ".json"
  
  local file = io.open(path, "w")
  if file then
    local json = vim.json.encode(state)
    file:write(json)
    file:close()
  end
end

function M.load(slug)
  local dir = get_state_dir()
  local path = dir .. "/" .. slug .. ".json"
  
  local content = fs.read_file(path)
  if content then
    local ok, state = pcall(vim.json.decode, content)
    if ok then
      return state
    end
  end
  return nil
end

return M
