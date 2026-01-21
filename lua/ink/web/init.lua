local fetcher = require("ink.web.fetcher")
local planalto_parser = require("ink.web.planalto_parser")
local generic_parser = require("ink.web.generic_parser")
local versions = require("ink.web.versions")
local changelog = require("ink.web.changelog")
local web_util = require("ink.web.util")
local migrate_highlights = require("ink.web.migrate_highlights")
local util = require("ink.markdown.util") -- Reuse slugify function

local M = {}

-- Generate slug from URL
-- For Planalto: Extract law number (lei-13140-2015)
-- For generic URLs: Use short hash
local function generate_slug(url, is_planalto)
  if is_planalto then
    -- Extract meaningful parts from Planalto URL
    local path = url:match("https?://[^/]+/(.+)$")
    if path then
      -- Try to extract law number and year
      local year, number = path:match("(%d%d%d%d)/lei/l(%d+)")
      if year and number then
        return "lei-" .. number .. "-" .. year
      end

      -- Try without year
      number = path:match("lei/l(%d+)")
      if number then
        return "lei-" .. number
      end

      -- Fallback: slugify the path
      return util.slugify(path)
    end
  end

  -- For generic URLs, use SHA256 hash (first 16 chars for readability)
  local hash = vim.fn.sha256(url)
  return "web-" .. hash:sub(1, 16)
end

-- Check if URL is from Planalto website
function M.is_planalto_url(url)
  return web_util.is_planalto_url(url)
end

-- deprecated
local function old_validate_url(url)
  -- Check type and size
  if not url or type(url) ~= "string" then
    return false, "Invalid URL: must be a string"
  end

  if #url > 2048 then
    return false, "URL too long (max: 2048 characters)"
  end

  -- Must start with http:// or https://
  if not url:match("^https?://") then
    return false, "Invalid URL: must start with http:// or https://"
  end

  -- Extract hostname from URL
  local hostname = url:match("^https?://([^/:]+)")
  if not hostname then
    return false, "Invalid URL: cannot extract hostname"
  end

  -- Security: Block localhost and private IP ranges (SSRF prevention)
  hostname = hostname:lower()

  -- Block localhost
  if hostname == "localhost" or hostname == "127.0.0.1" or hostname:match("^127%.") then
    return false, "Access to localhost is not allowed"
  end

  -- Block IPv6 localhost
  if hostname == "::1" or hostname:match("^::ffff:127%.") then
    return false, "Access to localhost is not allowed"
  end

  -- Block private IPv4 ranges (RFC 1918)
  -- 10.0.0.0/8
  if hostname:match("^10%.") then
    return false, "Access to private IP ranges is not allowed"
  end

  -- 172.16.0.0/12
  local second_octet = hostname:match("^172%.(%d+)%.")
  if second_octet then
    second_octet = tonumber(second_octet)
    if second_octet and second_octet >= 16 and second_octet <= 31 then
      return false, "Access to private IP ranges is not allowed"
    end
  end

  -- 192.168.0.0/16
  if hostname:match("^192%.168%.") then
    return false, "Access to private IP ranges is not allowed"
  end

  -- Block link-local (169.254.0.0/16)
  if hostname:match("^169%.254%.") then
    return false, "Access to link-local addresses is not allowed"
  end

  -- Block metadata services (cloud providers)
  if hostname:match("169%.254%.169%.254") or hostname == "metadata" or hostname:match("%.metadata%.") then
    return false, "Access to metadata services is not allowed"
  end

  return true, nil
end

-- Validate URL for security (SSRF-safe, Neovim-compatible)
-- @param url: URL string to validate
-- @return valid boolean, error message
local function validate_url(url)
  -- Basic checks
  if type(url) ~= "string" then
    return false, "Invalid URL: must be a string"
  end

  if #url > 2048 then
    return false, "URL too long (max: 2048 characters)"
  end

  if not url:match("^https?://") then
    return false, "Invalid URL: must start with http:// or https://"
  end

  -- Reject userinfo (user:pass@host)
  if url:match("^https?://[^/]+@") then
    return false, "Userinfo in URL is not allowed"
  end

  -- Extract hostname (no port)
  local hostname = url:match("^https?://([^/:]+)")
  if not hostname then
    return false, "Invalid URL: cannot extract hostname"
  end

  hostname = hostname:lower():gsub("%.$", "") -- normalize trailing dot

  -- Reject IP literals entirely (IPv4, IPv6, decimal, hex, shorthand)
  if hostname:match("^%d+%.") or
     hostname:match("^%d+$") or
     hostname:match(":") then
    return false, "IP literal hosts are not allowed"
  end

  -- Block obvious local names
  if hostname == "localhost" or hostname:match("%.localhost$") then
    return false, "Access to localhost is not allowed"
  end

  -- Block metadata services (name-based)
  if hostname == "metadata" or hostname:match("%.metadata%.") then
    return false, "Access to metadata services is not allowed"
  end

  -- DNS resolution via libuv (vim.loop)
  local uv = vim.loop
  local results = {}
  local done = false
  local err_msg

  uv.getaddrinfo(hostname, nil, { socktype = "stream" }, function(err, res)
    if err then
      err_msg = err
    else
      results = res or {}
    end
    done = true
  end)

  -- Block until DNS completes (safe here: validation step)
  while not done do
    uv.run("nowait")
  end

  if err_msg or #results == 0 then
    return false, "DNS resolution failed"
  end

  for _, entry in ipairs(results) do
    if entry.family == "inet" then
      -- IPv4 checks
      local a, b = entry.addr:match("^(%d+)%.(%d+)%.")
      a, b = tonumber(a), tonumber(b)

      if not a or not b then
        return false, "Invalid IPv4 address"
      end

      -- Block loopback, private, link-local
      if a == 10 or
         a == 127 or
         (a == 169 and b == 254) or
         (a == 192 and b == 168) or
         (a == 172 and b >= 16 and b <= 31) then
        return false, "Resolved to private IPv4 address"
      end

    elseif entry.family == "inet6" then
      -- Conservative IPv6 policy
      local ip = entry.addr:lower()
      if ip == "::1" or
         ip:match("^fe80:") or
         ip:match("^fc") or
         ip:match("^fd") or
         ip:match("^::ffff:") then
        return false, "Resolved to disallowed IPv6 address"
      end
    else
      return false, "Unknown address family"
    end
  end

  return true, nil
end

-- Open and parse a web page from URL
-- Returns data structure compatible with ink.nvim format
-- @param url: URL to the page (any website)
-- @param opts: optional table with { force_download = true }
-- @return data structure or nil, error
function M.open(url, opts)
  opts = opts or {}

  -- Security: Validate URL
  local valid, err = validate_url(url)
  if not valid then
    return nil, err
  end

  -- Detect site type
  local is_planalto = M.is_planalto_url(url)

  -- Generate slug
  local slug = generate_slug(url, is_planalto)

  -- Try to get cached version first
  local cached_html, cached_metadata, _ = fetcher.get_cached(slug)

  -- Fetch (or use cache)
  local html, metadata, err = fetcher.fetch_and_cache(url, slug, opts.force_download)

  if not html then
    return nil, err
  end

  -- Update changelog if we had a cached version and content changed
  -- Use hash comparison to avoid false positives from whitespace changes
  local has_changes = false
  local old_spine = nil  -- For highlight migration

  if cached_metadata and cached_metadata.hash then
    -- Compare hashes instead of raw HTML
    if metadata.hash ~= cached_metadata.hash then
      local chlog, changed = changelog.update(slug, cached_html, html, url)
      has_changes = changed

      if has_changes then
        vim.notify(
          "Página atualizada! Use :InkWebChangelog para ver as mudanças.",
          vim.log.levels.WARN
        )

        -- For Planalto pages, parse old HTML to get old spine for migration
        if is_planalto and cached_html then
          local old_parsed = planalto_parser.parse(cached_html, url)
          local active_version = versions.load_preference(slug)

          -- Get the spine that matches the user's active version preference
          if active_version == versions.VERSION_RAW then
            old_spine = planalto_parser.build_raw_spine(old_parsed)
          else
            old_spine = planalto_parser.build_compiled_spine(old_parsed)
          end
        end
      end
    end
  elseif not cached_html then
    -- First time opening this page
    changelog.update(slug, nil, html, url)
  end

  -- Select parser based on site type
  local parser = is_planalto and planalto_parser or generic_parser

  -- Parse HTML
  local parsed_page = parser.parse(html, url)

  -- Build both spine versions
  local raw_spine = parser.build_raw_spine(parsed_page)
  local compiled_spine = parser.build_compiled_spine(parsed_page)

  -- Migrate highlights if page was updated (for Planalto pages)
  if has_changes and old_spine and is_planalto then
    -- Determine which spine to use for migration based on user preference
    local active_version = versions.load_preference(slug)
    local new_spine = (active_version == versions.VERSION_RAW) and raw_spine or compiled_spine

    local migration_stats = migrate_highlights.migrate_highlights(slug, old_spine, new_spine)

    -- Notify user about migration results
    if migration_stats.migrated > 0 or migration_stats.failed > 0 then
      local msg_parts = {}

      if migration_stats.migrated > 0 then
        table.insert(msg_parts, string.format("%d highlight(s) migrado(s)", migration_stats.migrated))
      end

      if migration_stats.unchanged > 0 then
        table.insert(msg_parts, string.format("%d inalterado(s)", migration_stats.unchanged))
      end

      if migration_stats.failed > 0 then
        table.insert(msg_parts, string.format("%d falhou(aram) - artigo removido?", migration_stats.failed))
      end

      vim.notify(
        "Migração de highlights: " .. table.concat(msg_parts, ", "),
        migration_stats.failed > 0 and vim.log.levels.WARN or vim.log.levels.INFO
      )
    end
  end

  -- Build table of contents
  local toc_data = parser.build_toc(parsed_page)

  -- Build page data based on site type
  local page_data = {
    title = parsed_page.title,
    language = "pt-BR",
    spine = compiled_spine, -- Default spine (will be replaced by version manager)
    toc = toc_data,
    slug = slug,
    base_dir = fetcher.get_cache_dir(slug),
    cache_dir = fetcher.get_cache_dir(slug),
    path = url,
    format = "web",
    url = url,
    has_updates = has_changes,
    is_planalto = is_planalto
  }

  -- Add Planalto-specific metadata
  if is_planalto then
    page_data.author = "Governo Federal do Brasil"
    page_data.date = parsed_page.year
    page_data.description = parsed_page.ementa
    page_data.page_id = parsed_page.page_id
    page_data.page_number = parsed_page.number
    page_data.page_year = parsed_page.year
  else
    -- Generic page metadata
    page_data.author = url:match("https?://([^/]+)") or "Unknown"
    page_data.description = parsed_page.title
  end

  -- Add version information
  page_data = versions.create_versioned_data(page_data, raw_spine, compiled_spine)

  -- Get active spine based on user preference
  local active_spine = versions.get_active_spine(page_data, slug)
  page_data.spine = active_spine

  -- Add active version info for display
  local active_version = versions.load_preference(slug)
  page_data.active_version = active_version
  page_data.version_name = versions.get_display_name(active_version)

  return page_data
end

-- Toggle between raw and compiled versions
-- @param slug: page identifier
-- @return new version name
function M.toggle_version(slug)
  local new_version = versions.toggle(slug)
  return versions.get_display_name(new_version)
end

-- Check for updates for a specific page
-- @param slug: page identifier
-- @param url: page URL
-- @return has_update, message
function M.check_updates(slug, url)
  local has_update, new_hash, err = fetcher.check_for_updates(url, slug)

  if err then
    return nil, err
  end

  if has_update then
    return true, "Atualização disponível para esta página"
  else
    return false, "Página está atualizada"
  end
end

-- Get changelog for a page
-- @param slug: page identifier
-- @return formatted changelog string
function M.get_changelog(slug)
  local chlog = changelog.load(slug)
  return changelog.format_for_display(chlog)
end

-- Clear cache for a specific page
function M.clear_cache(slug)
  return fetcher.clear_cache(slug)
end

return M
