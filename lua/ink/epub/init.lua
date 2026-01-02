local fs = require("ink.fs")
local container = require("ink.epub.container")
local opf = require("ink.epub.opf")
local ncx = require("ink.epub.ncx")
local nav = require("ink.epub.nav")
local css = require("ink.epub.css")
local util = require("ink.epub.util")

local M = {}

local function get_cache_dir()
  return vim.fn.stdpath("data") .. "/ink.nvim/cache"
end

-- Clear cache for a specific slug or all cache
function M.clear_cache(slug)
  local cache_root = get_cache_dir()

  if slug then
    -- Clear specific book cache
    local cache_dir = cache_root .. "/" .. slug
    if fs.dir_exists(cache_dir) then
      local success = fs.remove_dir(cache_dir)
      if success then
        return true, "Cleared cache for: " .. slug
      else
        return false, "Failed to clear cache for: " .. slug
      end
    else
      return false, "Cache not found for: " .. slug
    end
  else
    -- Clear all cache
    if fs.dir_exists(cache_root) then
      local success = fs.remove_dir(cache_root)
      if success then
        -- Recreate empty cache directory
        fs.ensure_dir(cache_root)
        return true, "Cleared all EPUB cache"
      else
        return false, "Failed to clear cache"
      end
    else
      return true, "Cache directory already empty"
    end
  end
end

-- Get cache size information
function M.get_cache_info()
  local cache_root = get_cache_dir()

  if not fs.dir_exists(cache_root) then
    return {
      total_books = 0,
      exists = false
    }
  end

  -- Count subdirectories (each is a cached book)
  local handle = vim.loop.fs_scandir(cache_root)
  local count = 0

  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if type == "directory" then
        count = count + 1
      end
    end
  end

  return {
    total_books = count,
    exists = true,
    path = cache_root
  }
end

-- Get list of all cached books with their slugs
function M.get_cached_books()
  local cache_root = get_cache_dir()
  local books = {}

  if not fs.dir_exists(cache_root) then
    return books
  end

  local handle = vim.loop.fs_scandir(cache_root)
  if handle then
    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end
      if type == "directory" then
        table.insert(books, {
          slug = name,
          path = cache_root .. "/" .. name
        })
      end
    end
  end

  return books
end

-- Build TOC from content headings (H1-H3)
-- This is a lazy function that will be called only when TOC is first accessed
function M.build_toc_from_content(spine, base_dir, class_styles)
  local html = require("ink.html")
  local toc = {}

  for chapter_idx, spine_item in ipairs(spine) do
    local chapter_path = base_dir .. "/" .. spine_item.href
    local content = fs.read_file(chapter_path)

    if content then
      -- Parse with a simple max_width for heading extraction
      local parsed = html.parse(content, 80, class_styles, false)

      -- Add headings to TOC
      if parsed.headings then
        for _, heading in ipairs(parsed.headings) do
          local href = spine_item.href
          if heading.id then
            href = href .. "#" .. heading.id
          end

          table.insert(toc, {
            label = heading.text,
            href = href,
            level = heading.level
          })
        end
      end
    end
  end

  return toc
end

function M.open(epub_path, opts)
  -- local start_time = vim.loop.hrtime()  -- DEBUG: Start timing

  opts = opts or {}
  local skip_toc_generation = opts.skip_toc_generation or false

  epub_path = vim.fn.fnamemodify(epub_path, ":p")

  if not fs.exists(epub_path) then
    error("File not found: " .. epub_path)
  end

  local slug = util.get_slug(epub_path)
  local cache_dir = get_cache_dir() .. "/" .. slug
  local epub_dir = cache_dir .. "/epub"
  local extraction_flag = epub_dir .. "/.extracted"

  -- Check if extraction is needed
  local needs_extraction = false

  if not fs.dir_exists(epub_dir) then
    -- EPUB directory doesn't exist
    needs_extraction = true
  elseif not fs.exists(extraction_flag) then
    -- Directory exists but extraction wasn't completed (interrupted?)
    needs_extraction = true
  else
    -- Check if EPUB was modified after cache was created
    local epub_mtime = fs.get_mtime(epub_path)
    local cache_mtime = fs.get_mtime(extraction_flag)

    if epub_mtime and cache_mtime and epub_mtime > cache_mtime then
      -- EPUB is newer than cache, re-extract
      needs_extraction = true
      fs.remove_dir(epub_dir)
    end
  end

  if needs_extraction then
    -- vim.notify("📦 Extracting EPUB to cache...", vim.log.levels.INFO)  -- DEBUG
    fs.ensure_dir(cache_dir)  -- Ensure parent cache dir exists
    local success = fs.unzip(epub_path, epub_dir)
    if not success then error("Failed to unzip epub") end

    -- Create extraction flag to mark successful extraction
    fs.write_file(extraction_flag, tostring(os.time()))
    -- vim.notify("✅ EPUB extracted to cache", vim.log.levels.INFO)  -- DEBUG
  -- else
    -- vim.notify("⚡ Using cached EPUB (no extraction needed)", vim.log.levels.INFO)  -- DEBUG
  end

  -- 1. Container
  local container_path = epub_dir .. "/META-INF/container.xml"
  local container_xml = fs.read_file(container_path)
  if not container_xml then error("Invalid EPUB: Missing META-INF/container.xml") end
  local opf_rel_path = container.parse_container_xml(container_xml)
  local opf_path = epub_dir .. "/" .. opf_rel_path
  opf_path = util.validate_path(opf_path, epub_dir)
  local opf_dir = vim.fn.fnamemodify(opf_path, ":h")

  -- 2. OPF
  local opf_content = fs.read_file(opf_path)
  if not opf_content then error("Could not read OPF file: " .. opf_path) end
  local manifest = opf.parse_manifest(opf_content)
  local spine = opf.parse_spine(opf_content, manifest)
  local metadata = opf.parse_metadata(opf_content, slug)

  -- 3. TOC
  local toc_href = opf.find_toc_href(opf_content, manifest)
  local toc = {}
  if toc_href then
    local toc_path = opf_dir .. "/" .. toc_href
    toc_path = util.validate_path(toc_path, epub_dir)
    local toc_content = fs.read_file(toc_path)
    if toc_content then
      local toc_dir_rel = vim.fn.fnamemodify(toc_href, ":h")
      local function resolve_href(href)
        if not href then return nil end
        local path_part = href:match("^([^#]+)") or href
        local anchor_part = href:match("(#.+)$") or ""
        local full_path = path_part
        if toc_dir_rel ~= "." then full_path = toc_dir_rel .. "/" .. path_part end
        local normalized = util.normalize_path(full_path)
        return normalized .. anchor_part
      end
      if toc_href:match("%.xhtml$") or toc_href:match("%.html$") then
        toc = nav.parse_nav(toc_content, resolve_href)
      else
        toc = ncx.parse_ncx(toc_content, resolve_href, 1)
      end
    end
  end

  -- 4. CSS - with caching
  local css_cache = require("ink.css_cache")
  local class_styles = css_cache.load(slug)

  if not class_styles then
    -- Parse CSS and cache it
    class_styles = css.parse_all_css_files(manifest, opf_dir, epub_dir)
    css_cache.save(slug, class_styles)
  end

  -- 5. Build TOC from content headings (H1-H3) - ONLY if no official TOC exists
  -- Official TOC (NCX/NAV) always takes priority
  if #toc == 0 then
    -- No official TOC found, try to build from content
    local toc_cache = require("ink.toc_cache")
    local cached_toc = toc_cache.load(slug)

    if cached_toc and #cached_toc > 0 then
      -- Use cached TOC
      toc = cached_toc
    elseif not skip_toc_generation then
      -- Build TOC and cache it
      local content_toc = M.build_toc_from_content(spine, opf_dir, class_styles)
      if #content_toc > 0 then
        toc = content_toc
        toc_cache.save(slug, toc)
      end
    end
  end

  -- DEBUG: Calculate elapsed time
  -- local end_time = vim.loop.hrtime()
  -- local elapsed_ms = (end_time - start_time) / 1000000  -- Convert nanoseconds to milliseconds
  -- vim.notify(string.format("⏱️  EPUB parsing took %.0f ms", elapsed_ms), vim.log.levels.INFO)

  return {
    title = metadata.title,
    author = metadata.author,
    language = metadata.language,
    date = metadata.date,
    description = metadata.description,
    spine = spine,
    toc = toc,
    base_dir = opf_dir,
    slug = slug,
    cache_dir = cache_dir,
    class_styles = class_styles,
    path = epub_path
  }
end

return M