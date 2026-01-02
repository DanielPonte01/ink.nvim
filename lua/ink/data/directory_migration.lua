-- Directory structure migration
-- Migrates from old flat structure to new organized structure
local M = {}

local fs = require("ink.fs")

-- Migration version
local MIGRATION_VERSION = 1

-- Get migration status file path
local function get_migration_file()
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  return data_dir .. "/.directory_migration"
end

-- Check if migration has been run
local function is_migrated()
  local migration_file = get_migration_file()
  if not fs.exists(migration_file) then
    return false
  end

  local content = fs.read_file(migration_file)
  if not content then
    return false
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data.version then
    return false
  end

  return data.version >= MIGRATION_VERSION
end

-- Mark migration as complete
local function mark_migrated()
  local migration_file = get_migration_file()
  local data = {
    version = MIGRATION_VERSION,
    timestamp = os.time()
  }

  local file = io.open(migration_file, "w")
  if file then
    file:write(vim.json.encode(data))
    file:close()
    return true
  end
  return false
end

-- Get all book slugs from cache and books directories
local function get_all_slugs()
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  local cache_dir = data_dir .. "/cache"
  local books_dir = data_dir .. "/books"

  local slugs = {}
  local seen = {}

  -- Get slugs from cache directory
  if fs.dir_exists(cache_dir) then
    local handle = vim.loop.fs_scandir(cache_dir)
    if handle then
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if type == "directory" and not seen[name] then
          slugs[#slugs + 1] = name
          seen[name] = true
        end
      end
    end
  end

  -- Get slugs from books directory
  if fs.dir_exists(books_dir) then
    local handle = vim.loop.fs_scandir(books_dir)
    if handle then
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if type == "directory" and not seen[name] then
          slugs[#slugs + 1] = name
          seen[name] = true
        end
      end
    end
  end

  return slugs
end

-- Migrate a single book's cache structure
local function migrate_book_cache(slug)
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  local cache_dir = data_dir .. "/cache/" .. slug
  local books_dir = data_dir .. "/books/" .. slug

  if not fs.dir_exists(cache_dir) then
    return true -- Nothing to migrate
  end

  local changes = 0

  -- 1. Move EPUB files to epub/ subdirectory
  local epub_subdir = cache_dir .. "/epub"
  local needs_epub_migration = false

  -- Check if there are EPUB files in root of cache dir
  local handle = vim.loop.fs_scandir(cache_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end

      -- Skip files/dirs that should stay in root
      if name ~= "epub" and name ~= "toc.json" and name ~= "css.json"
         and name ~= "search_index.json" and name ~= "glossary_matches.json" then
        needs_epub_migration = true
        break
      end
    end
  end

  if needs_epub_migration then
    -- Create epub subdirectory
    fs.ensure_dir(epub_subdir)

    -- Move files to epub/
    handle = vim.loop.fs_scandir(cache_dir)
    if handle then
      while true do
        local name, type = vim.loop.fs_scandir_next(handle)
        if not name then break end

        -- Move everything except cache files and epub dir itself
        if name ~= "epub" and name ~= "toc.json" and name ~= "css.json"
           and name ~= "search_index.json" and name ~= "glossary_matches.json" then

          local old_path = cache_dir .. "/" .. name
          local new_path = epub_subdir .. "/" .. name

          local success = os.rename(old_path, new_path)
          if success then
            changes = changes + 1
          end
        end
      end
    end
  end

  -- 2. Move legacy TOC from root to cache/{slug}/toc.json
  local legacy_toc = data_dir .. "/" .. slug .. "_toc.json"
  local new_toc = cache_dir .. "/toc.json"

  if fs.exists(legacy_toc) and not fs.exists(new_toc) then
    local success = os.rename(legacy_toc, new_toc)
    if success then
      changes = changes + 1
    end
  end

  -- 3. Move and rename glossary_matches_cache.json to glossary_matches.json
  -- Check both in cache root and in epub/ (if migrated incorrectly before)
  local old_glossary_cache_root = cache_dir .. "/glossary_matches_cache.json"
  local old_glossary_cache_epub = cache_dir .. "/epub/glossary_matches_cache.json"
  local new_glossary_cache = cache_dir .. "/glossary_matches.json"

  if fs.exists(old_glossary_cache_root) and not fs.exists(new_glossary_cache) then
    local success = os.rename(old_glossary_cache_root, new_glossary_cache)
    if success then
      changes = changes + 1
    end
  elseif fs.exists(old_glossary_cache_epub) and not fs.exists(new_glossary_cache) then
    -- Move from epub/ to cache root and rename
    local success = os.rename(old_glossary_cache_epub, new_glossary_cache)
    if success then
      changes = changes + 1
    end
  end

  -- 4. Move css_cache.json from books/ to cache/
  if fs.dir_exists(books_dir) then
    local old_css = books_dir .. "/css_cache.json"
    local new_css = cache_dir .. "/css.json"

    if fs.exists(old_css) and not fs.exists(new_css) then
      local success = os.rename(old_css, new_css)
      if success then
        changes = changes + 1
      end
    end

    -- 5. Move toc_cache.json from books/ to cache/
    local old_toc_cache = books_dir .. "/toc_cache.json"
    local new_toc_cache = cache_dir .. "/toc.json"

    if fs.exists(old_toc_cache) and not fs.exists(new_toc_cache) then
      local success = os.rename(old_toc_cache, new_toc_cache)
      if success then
        changes = changes + 1
      end
    end

    -- 6. Move search_index.json from books/ to cache/
    local old_search = books_dir .. "/search_index.json"
    local new_search = cache_dir .. "/search_index.json"

    if fs.exists(old_search) and not fs.exists(new_search) then
      local success = os.rename(old_search, new_search)
      if success then
        changes = changes + 1
      end
    end
  end

  return true, changes
end

-- Clean up legacy TOC files in root
local function cleanup_legacy_toc_files()
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  local cleaned = 0

  local handle = vim.loop.fs_scandir(data_dir)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end

      -- Remove legacy TOC files (ending with _toc.json)
      if type == "file" and name:match("_toc%.json$") then
        local path = data_dir .. "/" .. name
        local success = os.remove(path)
        if success then
          cleaned = cleaned + 1
        end
      end
    end
  end

  return cleaned
end

-- Run full migration
function M.migrate()
  if is_migrated() then
    return true, "Already migrated"
  end

  local slugs = get_all_slugs()
  local total_changes = 0
  local failed_slugs = {}

  for _, slug in ipairs(slugs) do
    local success, changes = migrate_book_cache(slug)
    if success then
      total_changes = total_changes + (changes or 0)
    else
      table.insert(failed_slugs, slug)
    end
  end

  -- Cleanup legacy TOC files
  local cleaned = cleanup_legacy_toc_files()
  total_changes = total_changes + cleaned

  if #failed_slugs == 0 then
    mark_migrated()
    return true, string.format("Migration complete: %d changes", total_changes)
  else
    return false, string.format("Migration failed for: %s", table.concat(failed_slugs, ", "))
  end
end

-- Force re-run migration (for testing)
function M.force_migrate()
  local migration_file = get_migration_file()
  if fs.exists(migration_file) then
    os.remove(migration_file)
  end
  return M.migrate()
end

return M
