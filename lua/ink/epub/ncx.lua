local M = {}

local function get_attribute(tag_string, attr)
  local escaped_attr = attr:gsub("([%-%^%$%(%)%%%.%[%]%*%+%?])", "%%%1")
  return tag_string:match(escaped_attr .. '=["\']([^"\']+)["\']')
end

function M.parse_ncx(toc_content, resolve_href, level)
  local items = {}
  local pos = 1
  while true do
    local s, e = toc_content:find("<navPoint([^>]+)>", pos)
    if not s then break end
    
    local balance = 1
    local inner_start = e + 1
    local inner_end = inner_start
    local p = inner_start
    
    while balance > 0 and p <= #toc_content do
      local s2, e2, t2 = toc_content:find("<(/?navPoint)", p)
      if not s2 then break end
      if t2 == "navPoint" then balance = balance + 1
      else balance = balance - 1 end
      p = e2 + 1
      if balance == 0 then inner_end = s2 - 1 end
    end
    
    local inner_xml = toc_content:sub(inner_start, inner_end)
    local label = inner_xml:match("<text>([^<]+)</text>")
    local content_tag = inner_xml:match("<content[^>]+>")
    local src = get_attribute(content_tag or "", "src")
    
    if label and src then
      src = resolve_href(src)
      table.insert(items, { label = label, href = src, level = level })
      -- Recursively parse child navPoints
      local child_items = M.parse_ncx(inner_xml, resolve_href, level + 1)
      for _, child in ipairs(child_items) do
        table.insert(items, child)
      end
    end
    
    pos = p
  end
  return items
end

return M