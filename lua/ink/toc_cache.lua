local fs = require("ink.fs")
local data = require("ink.data")

local M = {}

local function get_toc_cache_path(slug)
  local cache_dir = vim.fn.stdpath("data") .. "/ink.nvim/cache/" .. slug
  fs.ensure_dir(cache_dir)
  return cache_dir .. "/toc.json"
end

function M.save(slug, toc)
  local path = get_toc_cache_path(slug)
  local json = data.json_encode({ toc = toc })

  local file = io.open(path, "w")
  if file then
    file:write(json)
    file:close()
    return true
  end
  return false
end

function M.load(slug)
  local path = get_toc_cache_path(slug)

  if not fs.exists(path) then
    return nil
  end

  local content = fs.read_file(path)
  if not content then
    return nil
  end

  local ok, cache_data = pcall(vim.json.decode, content)
  if not ok or not cache_data or not cache_data.toc then
    return nil
  end

  return cache_data.toc
end

function M.clear(slug)
  local path = get_toc_cache_path(slug)
  if fs.exists(path) then
    vim.fn.delete(path)
  end
end

return M
