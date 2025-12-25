-- lua/ink/chapter_cache.lua
-- LRU cache for parsed chapters to improve navigation performance

local M = {}

-- Cache configuration
local MAX_CACHE_SIZE = 10 -- Keep last 10 parsed chapters in memory
local cache = {}
local access_order = {} -- Track access order for LRU eviction

-- Generate cache key
local function get_cache_key(slug, chapter_idx)
  return slug .. ":" .. tostring(chapter_idx)
end

-- Update access order (move to end = most recently used)
local function update_access(key)
  -- Remove from current position
  for i, k in ipairs(access_order) do
    if k == key then
      table.remove(access_order, i)
      break
    end
  end

  -- Add to end (most recently used)
  table.insert(access_order, key)
end

-- Evict least recently used item if cache is full
local function evict_if_needed()
  if #access_order <= MAX_CACHE_SIZE then
    return
  end

  -- Remove oldest (first in list)
  local oldest_key = table.remove(access_order, 1)
  cache[oldest_key] = nil
end

-- Store parsed chapter in cache
-- @param slug: book slug
-- @param chapter_idx: chapter index
-- @param parsed_data: parsed chapter data from html.parse()
function M.set(slug, chapter_idx, parsed_data)
  local key = get_cache_key(slug, chapter_idx)

  -- Store in cache
  cache[key] = {
    data = parsed_data,
    timestamp = os.time(),
  }

  -- Update access order
  update_access(key)

  -- Evict old entries if needed
  evict_if_needed()
end

-- Get parsed chapter from cache
-- @param slug: book slug
-- @param chapter_idx: chapter index
-- @return parsed_data or nil if not in cache
function M.get(slug, chapter_idx)
  local key = get_cache_key(slug, chapter_idx)
  local entry = cache[key]

  if not entry then
    return nil
  end

  -- Update access order (mark as recently used)
  update_access(key)

  return entry.data
end

-- Check if chapter is in cache
-- @param slug: book slug
-- @param chapter_idx: chapter index
-- @return boolean
function M.has(slug, chapter_idx)
  local key = get_cache_key(slug, chapter_idx)
  return cache[key] ~= nil
end

-- Invalidate cache for specific book
-- @param slug: book slug (optional - if nil, clears entire cache)
function M.invalidate(slug)
  if not slug then
    -- Clear entire cache
    cache = {}
    access_order = {}
    return
  end

  -- Clear only entries for this book
  local prefix = slug .. ":"
  for key, _ in pairs(cache) do
    if key:match("^" .. vim.pesc(prefix)) then
      cache[key] = nil

      -- Remove from access order
      for i, k in ipairs(access_order) do
        if k == key then
          table.remove(access_order, i)
          break
        end
      end
    end
  end
end

-- Pre-cache adjacent chapters for smoother navigation
-- @param slug: book slug
-- @param current_idx: current chapter index
-- @param total_chapters: total number of chapters
-- @param parse_fn: function(idx) that returns parsed chapter data
function M.prefetch_adjacent(slug, current_idx, total_chapters, parse_fn)
  -- Prefetch next chapter if not in cache
  if current_idx < total_chapters then
    local next_idx = current_idx + 1
    if not M.has(slug, next_idx) then
      vim.schedule(function()
        local parsed = parse_fn(next_idx)
        if parsed then
          M.set(slug, next_idx, parsed)
        end
      end)
    end
  end

  -- Prefetch previous chapter if not in cache
  if current_idx > 1 then
    local prev_idx = current_idx - 1
    if not M.has(slug, prev_idx) then
      vim.schedule(function()
        local parsed = parse_fn(prev_idx)
        if parsed then
          M.set(slug, prev_idx, parsed)
        end
      end)
    end
  end
end

-- Get cache statistics
-- @return table with cache stats
function M.stats()
  local book_counts = {}

  for key, _ in pairs(cache) do
    local slug = key:match("^([^:]+):")
    if slug then
      book_counts[slug] = (book_counts[slug] or 0) + 1
    end
  end

  return {
    total_entries = #access_order,
    max_size = MAX_CACHE_SIZE,
    utilization = string.format("%.1f%%", (#access_order / MAX_CACHE_SIZE) * 100),
    books = book_counts,
  }
end

-- Clear all cache (useful for debugging)
function M.clear_all()
  cache = {}
  access_order = {}
end

return M
