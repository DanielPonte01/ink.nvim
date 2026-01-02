-- Persistent cache for glossary matches
local M = {}

local fs = require("ink.fs")

-- Get cache file path for a book
local function get_cache_file_path(slug)
  local cache_dir = vim.fn.stdpath("data") .. "/ink.nvim/cache/" .. slug
  return cache_dir .. "/glossary_matches.json"
end

-- Load persistent cache from disk
-- Returns: { version = "hash", chapters = { [idx] = matches } } or nil
function M.load(slug)
  local cache_path = get_cache_file_path(slug)

  if not fs.exists(cache_path) then
    return nil
  end

  local content = fs.read_file(cache_path)
  if not content then
    return nil
  end

  -- Parse JSON
  local ok, cache_data = pcall(vim.json.decode, content)
  if not ok then
    -- Corrupted cache, ignore
    return nil
  end

  -- Validate structure
  if type(cache_data) ~= "table" or not cache_data.version or not cache_data.chapters then
    return nil
  end

  return cache_data
end

-- Save cache to disk
-- cache_data: { version = "hash", chapters = { [idx] = matches } }
function M.save(slug, cache_data)
  local cache_path = get_cache_file_path(slug)

  -- Ensure cache directory exists (it should, since EPUB was extracted there)
  local cache_dir = vim.fn.fnamemodify(cache_path, ":h")
  if not fs.dir_exists(cache_dir) then
    -- Cache dir doesn't exist, can't save (book not opened yet?)
    return false
  end

  -- Serialize to JSON
  local ok, json_content = pcall(vim.json.encode, cache_data)
  if not ok then
    return false
  end

  -- Write to file
  local file = io.open(cache_path, "w")
  if not file then
    return false
  end

  file:write(json_content)
  file:close()

  return true
end

-- Clear cache for a book
function M.clear(slug)
  local cache_path = get_cache_file_path(slug)

  if fs.exists(cache_path) then
    os.remove(cache_path)
  end
end

return M
