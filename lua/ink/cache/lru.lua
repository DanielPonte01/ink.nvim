-- lua/ink/cache/lru.lua
-- Generic LRU (Least Recently Used) cache implementation

local M = {}

-- Create a new LRU cache
-- @param max_size: maximum number of entries to keep
-- @return cache object with get/put methods
function M.new(max_size)
  local cache = {
    max_size = max_size or 10,
    entries = {},      -- key -> value mapping
    access_order = {}, -- ordered list of keys (least to most recent)
  }

  -- Update access order (move key to end = most recently used)
  local function update_access(key)
    -- Remove from current position
    for i, k in ipairs(cache.access_order) do
      if k == key then
        table.remove(cache.access_order, i)
        break
      end
    end

    -- Add to end (most recently used)
    table.insert(cache.access_order, key)
  end

  -- Evict least recently used entry if cache is full
  local function evict_if_needed()
    if #cache.access_order <= cache.max_size then
      return
    end

    -- Remove oldest (first in list)
    local oldest_key = table.remove(cache.access_order, 1)
    cache.entries[oldest_key] = nil
  end

  -- Get value from cache
  -- @param key: cache key
  -- @return value or nil if not in cache
  function cache:get(key)
    local value = self.entries[key]

    if value == nil then
      return nil
    end

    -- Update access order (mark as recently used)
    update_access(key)

    return value
  end

  -- Put value into cache
  -- @param key: cache key
  -- @param value: value to store
  function cache:put(key, value)
    -- Store in cache
    self.entries[key] = value

    -- Update access order
    update_access(key)

    -- Evict old entries if needed
    evict_if_needed()
  end

  -- Check if key exists in cache
  -- @param key: cache key
  -- @return boolean
  function cache:has(key)
    return self.entries[key] ~= nil
  end

  -- Clear all entries
  function cache:clear()
    self.entries = {}
    self.access_order = {}
  end

  -- Get cache size
  -- @return number of entries
  function cache:size()
    return #self.access_order
  end

  -- Get cache statistics
  -- @return table with stats
  function cache:stats()
    return {
      size = #self.access_order,
      max_size = self.max_size,
      utilization = string.format("%.1f%%", (#self.access_order / self.max_size) * 100),
    }
  end

  return cache
end

return M
