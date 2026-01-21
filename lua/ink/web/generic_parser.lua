local entities = require("ink.html.entities")

local M = {}

-- Security limits
local MAX_LOOP_ITERATIONS = 10000  -- Maximum iterations for any loop

-- Escape HTML special characters to prevent XSS
-- This is critical for user-controlled data inserted into HTML
local function html_escape(str)
  if not str then return "" end
  str = tostring(str)  -- Ensure it's a string
  str = str:gsub("&", "&amp;")
  str = str:gsub("<", "&lt;")
  str = str:gsub(">", "&gt;")
  str = str:gsub('"', "&quot;")
  str = str:gsub("'", "&#39;")
  return str
end

-- Extract content between matching tags (handles nested tags)
-- @param html: HTML content
-- @param start_pos: position where opening tag was found
-- @param tag_name: name of the tag (e.g., "div", "article")
-- @return content (including opening and closing tags), end_pos
local function extract_matching_tag(html, start_pos, tag_name)
  local pos = start_pos
  local depth = 0
  local open_pattern = "<" .. tag_name .. "[^>]*>"
  local close_pattern = "</" .. tag_name .. ">"

  -- Find the end of the opening tag
  local opening_tag_end = html:find(">", pos, true)
  if not opening_tag_end then return nil, pos end

  pos = opening_tag_end + 1
  depth = 1

  -- Search for matching closing tag
  while pos <= #html and depth > 0 do
    -- Find next opening or closing tag of this type
    local next_open = html:find(open_pattern, pos)
    local next_close = html:find(close_pattern, pos)

    if not next_close then
      -- No closing tag found
      return nil, pos
    end

    if next_open and next_open < next_close then
      -- Found nested opening tag
      depth = depth + 1
      pos = next_open + 1
    else
      -- Found closing tag
      depth = depth - 1
      if depth == 0 then
        -- Found matching closing tag
        local close_tag_end = html:find(">", next_close, true)
        return html:sub(start_pos, close_tag_end), close_tag_end
      end
      pos = next_close + 1
    end
  end

  return nil, pos
end

-- Tags that typically contain main content
local CONTENT_TAGS = {
  article = true,
  main = true,
  ["div"] = true,
  section = true,
}

-- Tags/classes that typically contain non-content elements
local NEGATIVE_PATTERNS = {
  "nav", "navigation", "menu", "sidebar", "side%-bar",
  "footer", "header", "ad", "advertisement", "social",
  "share", "comment", "related", "recommended",
  "widget", "popup", "modal", "cookie", "banner"
}

-- Tags/classes that typically contain main content
local POSITIVE_PATTERNS = {
  "article", "content", "main", "post", "entry",
  "story", "body", "text", "paragraph"
}

-- Extract title from HTML
local function extract_title(html)
  -- Try <title> tag first
  local title = html:match("<title>([^<]+)</title>")
  if title then
    title = entities.decode_entities(title) -- Decode HTML entities
    title = title:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return title
  end

  -- Try h1
  title = html:match("<h1[^>]*>(.-)</h1>")
  if title then
    title = title:gsub("<[^>]+>", "")
    title = entities.decode_entities(title) -- Decode HTML entities
    title = title:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return title
  end

  return "Web Page"
end

-- Check if string matches negative patterns
local function is_negative(str)
  if not str then return false end
  str = str:lower()

  for _, pattern in ipairs(NEGATIVE_PATTERNS) do
    if str:match(pattern) then
      return true
    end
  end

  return false
end

-- Check if string matches positive patterns
local function is_positive(str)
  if not str then return false end
  str = str:lower()

  for _, pattern in ipairs(POSITIVE_PATTERNS) do
    if str:match(pattern) then
      return true
    end
  end

  return false
end

-- Calculate content score for a block of HTML
local function calculate_content_score(html_block)
  local score = 0

  -- Count paragraphs
  local p_count = 0
  for _ in html_block:gmatch("<p[^>]*>") do
    p_count = p_count + 1
  end
  score = score + p_count * 10

  -- Count text length (rough approximation)
  local text_only = html_block:gsub("<[^>]+>", "")
  local text_length = #text_only
  score = score + math.min(text_length / 100, 50)

  -- Bonus for semantic tags
  if html_block:match("<article[^>]*>") then score = score + 50 end
  if html_block:match("<main[^>]*>") then score = score + 50 end

  -- Extract class and id from the opening tag
  local class_attr = html_block:match('class="([^"]+)"')
  local id_attr = html_block:match('id="([^"]+)"')

  -- Penalty for negative patterns
  if is_negative(class_attr) or is_negative(id_attr) then
    score = score - 50
  end

  -- Bonus for positive patterns
  if is_positive(class_attr) or is_positive(id_attr) then
    score = score + 25
  end

  return score
end

-- Extract main content using Readability-like algorithm
local function extract_main_content(html)
  -- Extract body content
  local body = html:match("<body[^>]*>(.-)</body>") or html

  -- Find all potential content blocks (article, main, div, section)
  local candidates = {}

  -- Look for article tags
  local pos = 1
  local iterations = 0
  while iterations < MAX_LOOP_ITERATIONS do
    iterations = iterations + 1
    local article_start = body:find("<article[^>]*>", pos)
    if not article_start then break end

    local match, end_pos = extract_matching_tag(body, article_start, "article")
    if match then
      local score = calculate_content_score(match)
      table.insert(candidates, {content = match, score = score})
      pos = end_pos + 1
    else
      pos = article_start + 1
    end
  end

  -- Look for main tags
  pos = 1
  iterations = 0
  while iterations < MAX_LOOP_ITERATIONS do
    iterations = iterations + 1
    local main_start = body:find("<main[^>]*>", pos)
    if not main_start then break end

    local match, end_pos = extract_matching_tag(body, main_start, "main")
    if match then
      local score = calculate_content_score(match)
      table.insert(candidates, {content = match, score = score})
      pos = end_pos + 1
    else
      pos = main_start + 1
    end
  end

  -- Look for divs with content-related classes/ids
  pos = 1
  iterations = 0
  while iterations < MAX_LOOP_ITERATIONS do
    iterations = iterations + 1
    local div_start, div_attrs_end = body:find("<div([^>]*)>", pos)
    if not div_start then break end

    local attrs = body:sub(div_start + 4, div_attrs_end - 1)
    local class_attr = attrs:match('class="([^"]+)"')
    local id_attr = attrs:match('id="([^"]+)"')

    -- Only consider divs with positive patterns or potentially substantial content
    if is_positive(class_attr) or is_positive(id_attr) then
      local match, end_pos = extract_matching_tag(body, div_start, "div")
      if match then
        local score = calculate_content_score(match)
        if score > 20 then
          table.insert(candidates, {content = match, score = score})
        end
        pos = end_pos + 1
      else
        pos = div_start + 1
      end
    else
      pos = div_attrs_end + 1
    end
  end

  -- If no candidates found, fall back to body
  if #candidates == 0 then
    return body
  end

  -- Sort by score and pick the best
  table.sort(candidates, function(a, b) return a.score > b.score end)

  return candidates[1].content
end

-- Remove scripts, styles, and other non-content elements
local function clean_html(html)
  local result = html

  -- Remove script tags and content (handles nested tags)
  local pos = 1
  local iterations = 0
  while iterations < MAX_LOOP_ITERATIONS do
    iterations = iterations + 1
    local script_start = result:find("<script[^>]*>", pos)
    if not script_start then break end

    local match, end_pos = extract_matching_tag(result, script_start, "script")
    if match then
      result = result:sub(1, script_start - 1) .. result:sub(end_pos + 1)
      pos = script_start
    else
      pos = script_start + 1
    end
  end

  -- Remove style tags and content (handles nested tags)
  pos = 1
  iterations = 0
  while iterations < MAX_LOOP_ITERATIONS do
    iterations = iterations + 1
    local style_start = result:find("<style[^>]*>", pos)
    if not style_start then break end

    local match, end_pos = extract_matching_tag(result, style_start, "style")
    if match then
      result = result:sub(1, style_start - 1) .. result:sub(end_pos + 1)
      pos = style_start
    else
      pos = style_start + 1
    end
  end

  -- Remove comments
  result = result:gsub("<!%-%-.-%-%->", "")

  -- Remove common non-content elements (handles nested tags)
  for _, tag in ipairs({"nav", "header", "footer"}) do
    pos = 1
    iterations = 0
    while iterations < MAX_LOOP_ITERATIONS do
      iterations = iterations + 1
      local tag_start = result:find("<" .. tag .. "[^>]*>", pos)
      if not tag_start then break end

      local match, end_pos = extract_matching_tag(result, tag_start, tag)
      if match then
        result = result:sub(1, tag_start - 1) .. result:sub(end_pos + 1)
        pos = tag_start
      else
        pos = tag_start + 1
      end
    end
  end

  return result
end

-- Parse generic web page
function M.parse(html, url)
  local title = extract_title(html)

  -- Clean HTML
  local cleaned_html = clean_html(html)

  -- Extract main content
  local main_content = extract_main_content(cleaned_html)

  return {
    title = title,
    url = url,
    raw_content = cleaned_html, -- Full body without scripts/styles
    compiled_content = main_content, -- Extracted main content
    full_html = html -- Original HTML
  }
end

-- Add IDs to headers in HTML content
local function add_header_ids(html)
  local heading_count = 0

  -- Process both h2 and h3 tags in order of appearance
  local result = html:gsub("(<h[23][^>]*)>", function(opening_tag)
    -- Check if already has an id
    if opening_tag:match('id=') then
      return opening_tag .. ">"
    end
    heading_count = heading_count + 1
    return opening_tag .. ' id="heading-' .. heading_count .. '">'
  end)

  return result
end

-- Build spine for raw version (full HTML)
function M.build_raw_spine(parsed_page)
  -- Add IDs to headers for navigation
  local content_with_ids = add_header_ids(parsed_page.raw_content)

  -- Security: Escape title to prevent XSS
  local safe_title = html_escape(parsed_page.title)

  local content = string.format([[
<style>
  body { max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }
  img { max-width: 100%%; height: auto; }
  pre { background: #f4f4f4; padding: 10px; overflow-x: auto; }
  code { background: #f4f4f4; padding: 2px 5px; }
</style>
<h1>%s</h1>
<div class="content">
%s
</div>
]], safe_title, content_with_ids)

  return {
    {
      content = content,
      href = "page-content",
      title = parsed_page.title,
      index = 1
    }
  }
end

-- Build spine for compiled version (main content only)
function M.build_compiled_spine(parsed_page)
  -- Add IDs to headers for navigation
  local content_with_ids = add_header_ids(parsed_page.compiled_content)

  -- Security: Escape title to prevent XSS
  local safe_title = html_escape(parsed_page.title)

  local content = string.format([[
<style>
  body { max-width: 800px; margin: 0 auto; padding: 20px; line-height: 1.6; }
  img { max-width: 100%%; height: auto; }
  pre { background: #f4f4f4; padding: 10px; overflow-x: auto; }
  code { background: #f4f4f4; padding: 2px 5px; }
</style>
<h1>%s</h1>
<div class="content">
%s
</div>
]], safe_title, content_with_ids)

  return {
    {
      content = content,
      href = "page-content",
      title = parsed_page.title,
      index = 1
    }
  }
end

-- Build table of contents (simple version for generic pages)
function M.build_toc(parsed_page)
  local toc = {}
  local heading_count = 0

  -- Extract h2 and h3 headers in order of appearance
  local pos = 1
  local iterations = 0
  while iterations < MAX_LOOP_ITERATIONS do
    iterations = iterations + 1
    -- Find next h2 or h3
    local h2_start = parsed_page.compiled_content:find("<h2[^>]*>", pos)
    local h3_start = parsed_page.compiled_content:find("<h3[^>]*>", pos)

    -- Determine which comes first
    local next_pos, tag_level
    if h2_start and h3_start then
      if h2_start < h3_start then
        next_pos = h2_start
        tag_level = 2
      else
        next_pos = h3_start
        tag_level = 3
      end
    elseif h2_start then
      next_pos = h2_start
      tag_level = 2
    elseif h3_start then
      next_pos = h3_start
      tag_level = 3
    else
      break -- No more headers
    end

    -- Extract the heading text
    local pattern = "<h" .. tag_level .. "[^>]*>(.-)</h" .. tag_level .. ">"
    local heading = parsed_page.compiled_content:match(pattern, next_pos)

    if heading then
      local text = heading:gsub("<[^>]+>", "")
      text = entities.decode_entities(text) -- Decode HTML entities
      text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

      if text ~= "" then
        heading_count = heading_count + 1
        table.insert(toc, {
          label = text,
          href = "page-content#heading-" .. heading_count,
          level = tag_level - 1 -- h2 = level 1, h3 = level 2
        })
      end
    end

    -- Move past this heading
    pos = next_pos + 1
  end

  return toc
end

return M
