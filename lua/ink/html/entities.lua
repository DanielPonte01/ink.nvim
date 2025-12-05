local M = {}

function M.decode_entities(str)
  str = str:gsub("&lt;", "<")
  str = str:gsub("&gt;", ">")
  str = str:gsub("&amp;", "&")
  str = str:gsub("&quot;", '"')
  str = str:gsub("&apos;", "'")
  str = str:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
  str = str:gsub("&#x(%x+);", function(n) return string.char(tonumber(n, 16)) end)
  return str
end

return M