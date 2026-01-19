local data = require("ink.data")
local fs = require("ink.fs")

local M = {}

-- Version types
M.VERSION_RAW = "raw"
M.VERSION_COMPILED = "compiled"

-- Get version preferences file path
local function get_version_prefs_path(slug)
  local book_dir = data.get_book_dir(slug)
  return book_dir .. "/version_prefs.json"
end

-- Load version preference for a page
-- @param slug: unique identifier for the law
-- @return version string ("raw" or "compiled")
function M.load_preference(slug)
  local prefs_path = get_version_prefs_path(slug)

  if not fs.exists(prefs_path) then
    -- Default to raw version (shows all historical changes)
    return M.VERSION_RAW
  end

  local content = fs.read_file(prefs_path)
  if not content then
    return M.VERSION_RAW
  end

  local prefs, err = data.json_decode_safe(content, prefs_path)
  if not prefs or not prefs.version then
    return M.VERSION_RAW
  end

  return prefs.version
end

-- Save version preference for a page
-- @param slug: unique identifier for the law
-- @param version: "raw" or "compiled"
function M.save_preference(slug, version)
  local prefs_path = get_version_prefs_path(slug)

  local prefs = {
    version = version,
    updated_at = os.time()
  }

  local content = data.json_encode(prefs)
  fs.write_file(prefs_path, content)
end

-- Toggle between raw and compiled versions
-- @param slug: unique identifier for the law
-- @return new version string
function M.toggle(slug)
  local current = M.load_preference(slug)

  local new_version
  if current == M.VERSION_RAW then
    new_version = M.VERSION_COMPILED
  else
    new_version = M.VERSION_RAW
  end

  M.save_preference(slug, new_version)
  return new_version
end

-- Get display name for version
-- @param version: "raw" or "compiled"
-- @return display name string
function M.get_display_name(version)
  if version == M.VERSION_RAW then
    return "Crua (com histórico)"
  elseif version == M.VERSION_COMPILED then
    return "Compilada (texto atual)"
  else
    return "Desconhecida"
  end
end

-- Store both versions of spine in law data structure
-- @param page_data: data structure from parser
-- @param raw_spine: spine for raw version
-- @param compiled_spine: spine for compiled version
function M.create_versioned_data(page_data, raw_spine, compiled_spine)
  page_data.versions = {
    raw = {
      spine = raw_spine,
      name = M.get_display_name(M.VERSION_RAW)
    },
    compiled = {
      spine = compiled_spine,
      name = M.get_display_name(M.VERSION_COMPILED)
    }
  }
  return page_data
end

-- Get the active spine based on version preference
-- @param page_data: data structure with versions
-- @param slug: unique identifier for the law
-- @return active spine array
function M.get_active_spine(page_data, slug)
  local version = M.load_preference(slug)

  if not page_data.versions then
    -- Fallback: return main spine if versions not available
    return page_data.spine
  end

  if version == M.VERSION_RAW and page_data.versions.raw then
    return page_data.versions.raw.spine
  elseif version == M.VERSION_COMPILED and page_data.versions.compiled then
    return page_data.versions.compiled.spine
  end

  -- Fallback to raw version
  return page_data.versions.raw.spine
end

return M
