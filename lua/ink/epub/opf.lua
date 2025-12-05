local M = {}

local function get_attribute(tag_string, attr)
  local escaped_attr = attr:gsub("([%-%^%$%(%)%%%.%[%]%*%+%?])", "%%%1")
  return tag_string:match(escaped_attr .. '=["\']([^"\']+)["\']')
end

local function get_tag_content(xml, tag)
  local pattern = "<" .. tag .. "[^>]*>(.-)</" .. tag .. ">"
  return xml:match(pattern)
end

function M.parse_manifest(opf_content)
  local manifest = {}
  for item in opf_content:gmatch("<item%s+[^>]+>") do
    local id = get_attribute(item, "id")
    local href = get_attribute(item, "href")
    local media_type = get_attribute(item, "media-type")
    manifest[id] = { href = href, media_type = media_type }
  end
  return manifest
end

function M.parse_spine(opf_content, manifest)
  local spine = {}
  for itemref in opf_content:gmatch("<itemref[^>]+>") do
    local idref = get_attribute(itemref, "idref")
    if manifest[idref] then table.insert(spine, manifest[idref]) end
  end
  return spine
end

function M.parse_metadata(opf_content, slug)
  local title = get_tag_content(opf_content, "dc:title") or slug
  local author = get_tag_content(opf_content, "dc:creator") or "Unknown"
  local language = get_tag_content(opf_content, "dc:language")
  local date = get_tag_content(opf_content, "dc:date")
  local description = get_tag_content(opf_content, "dc:description")
  
  if date then
    local year = date:match("^(%d%d%d%d)")
    if year then date = year end
  end
  
  if description then
    description = description:gsub("<[^>]+>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
  end
  
  return {
    title = title,
    author = author,
    language = language,
    date = date,
    description = description
  }
end

function M.find_toc_href(opf_content, manifest)
  -- EPUB 3 nav
  for item in opf_content:gmatch("<item[^>]+>") do
    local props = get_attribute(item, "properties")
    if props and props:match("nav") then
      return get_attribute(item, "href")
    end
  end
  -- EPUB 2 ncx
  for id, item in pairs(manifest) do
    if item.media_type == "application/x-dtbncx+xml" then
      return item.href
    end
  end
  return nil
end

return M