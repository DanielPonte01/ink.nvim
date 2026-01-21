local fs = require("ink.fs")
local data = require("ink.data")
local web_util = require("ink.web.util")

local M = {}

-- Cache format version - increment when breaking changes are made
-- Version 2: Added proper ISO-8859-1 to UTF-8 encoding conversion
-- Version 3: Fixed strike tag preservation and complete paragraph capture
-- Version 4: Added CSS strikethrough normalization to <strike> tags
-- Version 5: Changed default version to RAW, improved CSS selectors
-- Version 6: Implemented proper CSS to <strike> tag normalization
local CACHE_VERSION = 6

-- Get cache directory for web pages
function M.get_cache_dir(slug)
  local valid, err = data.validate_slug(slug)
  if not valid then
    error("get_cache_dir: " .. err)
  end

  local dir = data.get_data_dir() .. "/cache/" .. slug
  fs.ensure_dir(dir)
  return dir
end

-- Get cache metadata file path
local function get_metadata_path(slug)
  return M.get_cache_dir(slug) .. "/page_metadata.json"
end

-- Get cached HTML file path
local function get_html_cache_path(slug)
  return M.get_cache_dir(slug) .. "/page.html"
end

-- Calculate SHA256 hash of content
local function calculate_hash(content)
  -- Use vim's sha256 function
  return vim.fn.sha256(content)
end

-- Load metadata from cache
local function load_metadata(slug)
  local metadata_path = get_metadata_path(slug)

  if not fs.exists(metadata_path) then
    return nil
  end

  local content = fs.read_file(metadata_path)
  if not content then
    return nil
  end

  local metadata, err = data.json_decode_safe(content, metadata_path)
  if not metadata then
    vim.notify("Failed to decode page metadata: " .. err, vim.log.levels.WARN)
    return nil
  end

  return metadata
end

-- Save metadata to cache
local function save_metadata(slug, metadata)
  local metadata_path = get_metadata_path(slug)
  local content = data.json_encode(metadata)

  local ok, err = fs.write_file(metadata_path, content)
  if not ok then
    vim.notify("Failed to save page metadata: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Convert ISO-8859-1 bytes to UTF-8 using iconv
-- Security: Avoids shell injection by using direct process execution
local function convert_encoding(content, from_encoding, to_encoding)
  if not content or #content == 0 then
    return content
  end

  -- Use vim.system with direct arguments (no shell interpolation)
  local result = vim.system(
    {"iconv", "-f", from_encoding, "-t", to_encoding},
    {stdin = content, text = true}
  ):wait()

  if result.code ~= 0 then
    -- If conversion fails, return original content
    vim.notify("Warning: encoding conversion failed, using original content", vim.log.levels.WARN)
    return content
  end

  return result.stdout
end

-- Fetch URL using curl
local function fetch_url(url)
  -- Security: Validate URL size to prevent resource exhaustion
  if #url > 2048 then
    return nil, "URL too long (max: 2048 characters)"
  end

  -- Use vim.system for safer command execution (Neovim 0.10+)
  -- Add user-agent to avoid blocking, timeout to prevent hanging
  -- Security: Pass URL as direct argument, NOT through shell

  local user_agent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

  -- Planalto website uses ISO-8859-1 encoding
  if web_util.is_planalto_url(url) then
    -- Step 1: Fetch content using curl (direct arguments, no shell)
    local result = vim.system(
      {
        "curl",
        "-L",              -- Follow redirects
        "-s",              -- Silent mode
        "-S",              -- Show errors
        "--max-time", "30", -- Timeout
        "-A", user_agent,   -- User agent
        url                 -- URL as direct argument (safe)
      },
      {text = false}  -- Binary mode for encoding conversion
    ):wait()

    if result.code ~= 0 then
      local error_msg = result.stderr or "Unknown error"
      return nil, "Failed to fetch URL: " .. error_msg
    end

    -- Step 2: Convert encoding from ISO-8859-1 to UTF-8
    local utf8_content = convert_encoding(result.stdout, "ISO-8859-1", "UTF-8")
    return utf8_content, nil
  end

  -- For generic URLs, try to detect encoding from content-type or meta tags
  -- First fetch the content
  local result = vim.system(
    {
      "curl", "-L", "-s", "-S", "--max-time", "30",
      "-A", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36",
      url
    },
    {text = true}
  ):wait()

  if result.code ~= 0 then
    local error_msg = result.stderr or "Unknown error"
    return nil, "Failed to fetch URL: " .. error_msg
  end

  local html = result.stdout

  -- Try to detect encoding from meta tags (multiple patterns)
  local charset = nil

  -- Pattern 1: <meta charset="utf-8">
  charset = html:match('<meta%s+charset="([^"]+)"')

  -- Pattern 2: <meta charset='utf-8'> (single quotes)
  if not charset then
    charset = html:match("<meta%s+charset='([^']+)'")
  end

  -- Pattern 3: <meta charset=utf-8> (no quotes)
  if not charset then
    charset = html:match('<meta%s+charset=([^%s>]+)')
  end

  -- Pattern 4: <meta http-equiv="content-type" content="text/html; charset=utf-8">
  if not charset then
    charset = html:match('<meta%s+[^>]*content="[^"]*charset=([^";%s]+)')
  end

  -- Pattern 5: Same as 4 but with single quotes
  if not charset then
    charset = html:match("<meta%s+[^>]*content='[^']*charset=([^';%s]+)")
  end

  -- If we found a charset and it's not UTF-8, try to convert
  if charset then
    charset = charset:lower():gsub("^%s+", ""):gsub("%s+$", "")

    if not charset:match("utf%-?8") then
      -- Try to convert from detected encoding
      local encoding = charset:upper()
      if charset:match("iso%-?8859%-?1") or charset:match("latin%-?1") then
        encoding = "ISO-8859-1"
      elseif charset:match("windows%-?1252") then
        encoding = "WINDOWS-1252"
      end

      -- Convert using our safe encoding converter
      local converted = convert_encoding(html, encoding, "UTF-8")
      if converted then
        return converted, nil
      end
    end
  end

  -- Return as-is (likely already UTF-8)
  return html, nil
end

-- Download and cache page HTML
-- @param url: URL of the page on Planalto website
-- @param slug: unique identifier for the page
-- @param force: force re-download even if cached
-- @return html_content, metadata, error
function M.fetch_and_cache(url, slug, force)
  local cache_path = get_html_cache_path(slug)
  local metadata = load_metadata(slug)

  -- Invalidate cache if version doesn't match
  local cache_valid = metadata and metadata.cache_version == CACHE_VERSION

  -- Check if we have valid cache and don't need to re-download
  if not force and cache_valid and fs.exists(cache_path) and metadata then
    local cached_html = fs.read_file(cache_path)
    if cached_html then
      return cached_html, metadata, nil
    end
  end

  -- If cache was invalidated due to version mismatch, notify user
  if metadata and not cache_valid then
    vim.notify("Cache format updated, re-downloading page...", vim.log.levels.INFO)
  end

  -- Check for existing highlights before downloading (Option 1: Warning)
  if metadata and fs.exists(cache_path) then
    local highlights_path = data.get_book_dir(slug) .. "/highlights.json"
    if fs.exists(highlights_path) then
      local content = fs.read_file(highlights_path)
      if content then
        local ok, hl_data = pcall(vim.json.decode, content)
        if ok and hl_data and hl_data.highlights and #hl_data.highlights > 0 then
          vim.notify(
            string.format(
              "AVISO: Esta página possui %d highlight(s). Atualizar pode desalinhar seus highlights se a estrutura da página mudou.",
              #hl_data.highlights
            ),
            vim.log.levels.WARN
          )
        end
      end
    end
  end

  -- Download from URL
  vim.notify("Downloading page from: " .. url, vim.log.levels.INFO)
  local html, err = fetch_url(url)

  if not html then
    return nil, nil, err
  end

  -- Calculate hash for change detection
  local hash = calculate_hash(html)

  -- Create new metadata
  local new_metadata = {
    url = url,
    slug = slug,
    downloaded_at = os.time(),
    hash = hash,
    last_checked = os.time(),
    cache_version = CACHE_VERSION
  }

  -- Check if content changed (for update notifications)
  if metadata and metadata.hash ~= hash then
    new_metadata.updated_at = os.time()
    new_metadata.previous_hash = metadata.hash
    vim.notify("Page has been updated since last download", vim.log.levels.WARN)
  end

  -- Save to cache
  local ok, write_err = fs.write_file(cache_path, html)
  if not ok then
    return nil, nil, "Failed to cache HTML: " .. tostring(write_err)
  end

  -- Save metadata
  save_metadata(slug, new_metadata)

  vim.notify("Page cached successfully", vim.log.levels.INFO)
  return html, new_metadata, nil
end

-- Check if page has updates available
-- @param url: URL of the page
-- @param slug: unique identifier
-- @return has_update, new_hash, error
function M.check_for_updates(url, slug)
  local metadata = load_metadata(slug)

  if not metadata then
    return nil, nil, "No cached version found"
  end

  -- Fetch current version from web
  vim.notify("Checking for updates: " .. url, vim.log.levels.INFO)
  local html, err = fetch_url(url)

  if not html then
    return nil, nil, err
  end

  -- Calculate hash
  local current_hash = calculate_hash(html)

  -- Update last_checked timestamp
  metadata.last_checked = os.time()
  save_metadata(slug, metadata)

  -- Compare hashes
  if current_hash ~= metadata.hash then
    return true, current_hash, nil
  end

  return false, current_hash, nil
end

-- Get cached HTML content
-- @param slug: unique identifier
-- @return html_content, metadata, error
function M.get_cached(slug)
  local cache_path = get_html_cache_path(slug)

  if not fs.exists(cache_path) then
    return nil, nil, "No cached version found"
  end

  local html = fs.read_file(cache_path)
  if not html then
    return nil, nil, "Failed to read cached HTML"
  end

  local metadata = load_metadata(slug)

  return html, metadata, nil
end

-- Clear cache for specific page
function M.clear_cache(slug)
  local cache_dir = M.get_cache_dir(slug)

  if fs.dir_exists(cache_dir) then
    return fs.remove_dir(cache_dir)
  end

  return true
end

return M
