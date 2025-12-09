local M = {}

-- Parse XML text elements from pdftohtml output
function M.parse_xml(xml_content)
  local pages = {}
  local current_page = nil

  -- Extract page dimensions and text elements
  for line in xml_content:gmatch("[^\r\n]+") do
    -- Match page tags: <page number="1" position="absolute" top="0" left="0" height="1263" width="892">
    local page_num, height, width = line:match('<page%s+number="(%d+)".-height="(%d+)".-width="(%d+)"')
    if page_num then
      current_page = {
        number = tonumber(page_num),
        height = tonumber(height),
        width = tonumber(width),
        texts = {}
      }
      table.insert(pages, current_page)
    end

    -- Match text tags: <text top="123" left="45" width="200" height="16" font="0">Hello</text>
    if current_page then
      local top, left, width, height, font, text = line:match(
        '<text%s+top="([%d%.]+)"%s+left="([%d%.]+)"%s+width="([%d%.]+)"%s+height="([%d%.]+)"%s+font="(%d+)"[^>]*>([^<]*)</text>'
      )
      if top then
        table.insert(current_page.texts, {
          top = tonumber(top),
          left = tonumber(left),
          width = tonumber(width),
          height = tonumber(height),
          font = tonumber(font),
          text = M.decode_xml_entities(text or "")
        })
      end
    end
  end

  -- Extract font information
  local fonts = M.parse_fonts(xml_content)

  return {
    pages = pages,
    fonts = fonts
  }
end

-- Parse font specifications from XML
function M.parse_fonts(xml_content)
  local fonts = {}

  for line in xml_content:gmatch("[^\r\n]+") do
    -- <fontspec id="0" size="12" family="Times" color="#000000"/>
    local id, size, family, color = line:match(
      '<fontspec%s+id="(%d+)"%s+size="([%d%.]+)"%s+family="([^"]+)"'
    )
    if id then
      fonts[tonumber(id)] = {
        size = tonumber(size),
        family = family,
        color = color
      }
    end
  end

  return fonts
end

-- Decode XML entities
function M.decode_xml_entities(text)
  local entities = {
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&amp;"] = "&",
    ["&quot;"] = '"',
    ["&apos;"] = "'",
    ["&#160;"] = " "
  }

  local result = text
  for entity, char in pairs(entities) do
    result = result:gsub(entity, char)
  end

  -- Decode numeric entities
  result = result:gsub("&#(%d+);", function(num)
    return string.char(tonumber(num))
  end)

  return result
end

-- Sort text elements in reading order (top to bottom, left to right)
function M.sort_reading_order(texts)
  table.sort(texts, function(a, b)
    -- Group by vertical position (tolerance of 5 pixels for same line)
    local tolerance = 5
    if math.abs(a.top - b.top) > tolerance then
      return a.top < b.top
    end
    -- Same line, sort by horizontal position
    return a.left < b.left
  end)
  return texts
end

return M
