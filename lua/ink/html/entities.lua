local M = {}

-- Safe character conversion with bounds checking
local function safe_char(num)
  -- Valid Unicode range: 0x0000 to 0x10FFFF (1114111 decimal)
  -- Exclude surrogate pairs: 0xD800 to 0xDFFF
  if not num or num < 0 or num > 0x10FFFF then
    return ""
  end
  if num >= 0xD800 and num <= 0xDFFF then
    return ""
  end

  -- Try utf8.char first (Neovim 0.10+)
  if utf8 and utf8.char then
    local ok, result = pcall(utf8.char, num)
    if ok then
      return result
    end
  end

  -- Fallback to string.char for ASCII range (0-127)
  if num <= 127 then
    return string.char(num)
  end

  -- For non-ASCII, return empty string (better than crash)
  -- Most common HTML entities are ASCII anyway
  return ""
end

function M.decode_entities(str)
  str = str:gsub("&lt;", "<")
  str = str:gsub("&gt;", ">")
  str = str:gsub("&amp;", "&")
  str = str:gsub("&quot;", '"')
  str = str:gsub("&apos;", "'")
  -- Decode numeric character references with bounds checking
  str = str:gsub("&#(%d+);", function(n)
    return safe_char(tonumber(n))
  end)
  str = str:gsub("&#x(%x+);", function(n)
    return safe_char(tonumber(n, 16))
  end)
  return str
end

return M