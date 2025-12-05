local M = {}

-- Simple CSS parser to extract class-based styling
-- Focuses on: font-weight, font-style, text-decoration
function M.parse_css(css_content)
  local class_styles = {}

  if not css_content or #css_content == 0 then
    return class_styles
  end

  -- Remove comments /* ... */
  css_content = css_content:gsub("/%*.-%*/", "")

  -- Match class selectors and their properties
  -- Pattern: .classname { properties }
  local pos = 1
  while pos <= #css_content do
    -- Find class selector: .classname
    local class_start, class_end, class_name = css_content:find("%s*%.([%w%._-]+)%s*{", pos)

    if not class_start then break end

    -- Find the closing brace
    local brace_count = 1
    local prop_start = class_end + 1
    local prop_end = prop_start

    while prop_end <= #css_content and brace_count > 0 do
      local char = css_content:sub(prop_end, prop_end)
      if char == "{" then
        brace_count = brace_count + 1
      elseif char == "}" then
        brace_count = brace_count - 1
      end
      prop_end = prop_end + 1
    end

    -- Extract properties block
    local properties = css_content:sub(prop_start, prop_end - 2)

    -- Parse font-weight, font-style, text-decoration
    local style = {}

    -- Check for bold
    if properties:match("font%-weight%s*:%s*bold") or
       properties:match("font%-weight%s*:%s*[6-9]00") then
      style.bold = true
    end

    -- Check for italic
    if properties:match("font%-style%s*:%s*italic") or
       properties:match("font%-style%s*:%s*oblique") then
      style.italic = true
    end

    -- Check for underline
    if properties:match("text%-decoration%s*:%s*underline") then
      style.underline = true
    end

    -- Check for line-through (strikethrough)
    if properties:match("text%-decoration%s*:%s*line%-through") then
      style.strikethrough = true
    end

    -- Check if class name suggests it's a title
    -- Common patterns: title, book-title, booktitle, chapter-title, epub-title, etc.
    if class_name:lower():match("title") then
      style.is_title = true
    end

    -- Store if we found any relevant styles
    if style.bold or style.italic or style.underline or style.strikethrough or style.is_title then
      class_styles[class_name] = style
    end

    pos = prop_end
  end

  return class_styles
end

return M
