local M = {}

local function get_attribute(tag_string, attr)
  local escaped_attr = attr:gsub("([%-%^%$%(%)%%%.%[%]%*%+%?])", "%%%1")
  return tag_string:match(escaped_attr .. '=["\']([^"\']+)["\']')
end

function M.parse_nav(toc_content, resolve_href)
  local toc = {}
  for link in toc_content:gmatch("<a[^>]+>.-</a>") do
    local href = get_attribute(link, "href")
    local text = link:match(">([^<]+)<")
    if href and text then
      href = resolve_href(href)
      table.insert(toc, { label = text, href = href, level = 1 })
    end
  end
  return toc
end

return M