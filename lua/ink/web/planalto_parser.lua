local M = {}

-- Extract page number and year from URL or title
local function extract_page_info(url, html)
  local year, number = url:match("/(%d%d%d%d)/lei/l(%d+)%.htm")
  if not year then
    number = url:match("/lei/l(%d+)%.htm")
  end

  local title = html:match("<title>([^<]+)</title>")
  if title then
    title = title:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  end

  if title and not number then
    number = title:match("Lei%s+n?º?%s*(%d+%.?%d*)")
    if number then
      number = number:gsub("%.", "")
    end
  end

  if title and not year then
    year = title:match("de%s+(%d%d%d%d)")
  end

  return {
    number = number or "unknown",
    year = year or "unknown",
    title = title or "Página Web"
  }
end

-- Extract ementa (summary) from HTML
local function extract_ementa(html)
  local ementa = html:match('<p[^>]*class="ementa"[^>]*>(.-)</p>')
  if ementa then
    ementa = ementa:gsub("<[^>]+>", "")
    ementa = ementa:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return ementa
  end
  return nil
end

-- Normalize strikethrough: convert CSS text-decoration:line-through to <strike> tags
-- This ensures consistent handling in both rendering and removal
local function normalize_strikethrough(html)
  local result = html

  -- Pattern to match any tag with text-decoration:line-through in style attribute
  -- This handles multi-line styles and various spacing
  local function wrap_in_strike(full_match)
    -- Extract the tag name, attributes, content, and closing tag
    local tag_name = full_match:match("^<([%w]+)")
    if not tag_name then return full_match end

    -- Find where the opening tag ends
    local tag_end = full_match:find(">", 1, true)
    if not tag_end then return full_match end

    -- Find the closing tag
    local close_pattern = "</" .. tag_name .. ">"
    local close_start = full_match:find(close_pattern, tag_end, true)
    if not close_start then return full_match end

    -- Extract parts
    local opening_tag = full_match:sub(1, tag_end)
    local content = full_match:sub(tag_end + 1, close_start - 1)
    local closing_tag = full_match:sub(close_start)

    -- Don't double-wrap if already has <strike>
    if content:match("^%s*<strike>") then
      return full_match
    end

    -- Wrap content in <strike>
    return opening_tag .. "<strike>" .. content .. "</strike>" .. closing_tag
  end

  -- Find all tags with text-decoration:line-through (case-insensitive, handles whitespace)
  -- This pattern is more flexible to handle line breaks in the style attribute
  local pos = 1
  while true do
    -- Find next occurrence of text-decoration followed by line-through
    local style_start = result:find("text%-decoration", pos)
    if not style_start then break end

    -- Check if it's followed by line-through (with possible whitespace/colon)
    local after_decoration = result:sub(style_start + 15, style_start + 40)
    if after_decoration:match("^%s*:%s*line%-through") then
      -- Found a match - now find the tag that contains this style attribute
      -- Search backwards to find the opening <
      local tag_start = style_start
      while tag_start > 1 and result:sub(tag_start, tag_start) ~= '<' do
        tag_start = tag_start - 1
      end

      if result:sub(tag_start, tag_start) == '<' then
        -- Now find the tag name and full tag
        local tag_name = result:sub(tag_start + 1):match("^([%w]+)")
        if tag_name then
          -- Find the end of opening tag
          local search_from = tag_start
          local opening_end = result:find(">", search_from, true)
          if opening_end then
            -- Find the closing tag
            local close_pattern = "</" .. tag_name .. ">"
            local close_start, close_end = result:find(close_pattern, opening_end, true)
            if close_start then
              -- Extract and wrap
              local full_tag = result:sub(tag_start, close_end)
              local opening_tag = result:sub(tag_start, opening_end)
              local content = result:sub(opening_end + 1, close_start - 1)
              local closing_tag = result:sub(close_start, close_end)

              -- Don't double-wrap
              if not content:match("^%s*<strike>") then
                local replacement = opening_tag .. "<strike>" .. content .. "</strike>" .. closing_tag
                result = result:sub(1, tag_start - 1) .. replacement .. result:sub(close_end + 1)
                -- Update position to skip past this replacement
                pos = tag_start + #replacement
              else
                pos = close_end + 1
              end
            else
              pos = opening_end + 1
            end
          else
            pos = style_start + 1
          end
        else
          pos = style_start + 1
        end
      else
        pos = style_start + 1
      end
    else
      pos = style_start + 1
    end
  end

  return result
end

-- Remove strike-through content (for compiled version)
-- Uses non-greedy matching and handles potential malformed tags
local function remove_strikethrough(html)
  -- Remove complete <strike>...</strike> pairs
  local result = html:gsub("<[sS][tT][rR][iI][kK][eE]>.-</[sS][tT][rR][iI][kK][eE]>", "")

  -- Safety: remove any orphaned opening <strike> tags (shouldn't happen, but just in case)
  result = result:gsub("<[sS][tT][rR][iI][kK][eE]>", "")

  -- Safety: remove any orphaned closing </strike> tags
  result = result:gsub("</[sS][tT][rR][iI][kK][eE]>", "")

  return result
end

-- Parse articles from HTML using a text-based approach
-- Real Planalto structure: articles are in <p> tags with text starting with "Art. X"
-- Returns: articles table and header_content (everything before first article)
local function parse_articles(html)
  local articles = {}

  -- Normalize strikethrough styles to <strike> tags for consistent handling
  html = normalize_strikethrough(html)

  -- Extract the body content
  local body = html:match("<body>(.-)</body>") or html

  -- Split into chunks at each "Art. X" pattern
  -- Pattern matches: Art. 1º, Art. 2, Art. 10., Art. 26-A, Art. 1º-AB, etc.
  local article_parts = {}
  local current_pos = 1

  -- Find all article markers with their positions
  -- Captures: Art. 1, Art. 1º, Art. 26-A, Art. 1º-B, Art. 26-ABC, etc.
  -- Pattern: Art. + spaces + digits + optional ordinal + optional (hyphen/dash + letters) + optional dot
  -- Note: [%-–—] matches hyphen, en-dash, and em-dash
  -- This searches in the full HTML including text inside <strike> tags
  for match_start, article_marker in body:gmatch("()Art%.%s*(%d+[ºo°]?[%-–—]?[A-Z]*%.?)") do
    -- Remove ordinal indicators (º, o, °) but keep hyphen and letters
    local article_num = article_marker:gsub("[ºo°]", ""):gsub("%.$", "")
    table.insert(article_parts, {
      pos = match_start,
      num = article_num,
      marker = article_marker
    })
  end

  -- Extract header content (everything before first article)
  local header_content = ""
  if #article_parts > 0 then
    local first_article_pos = article_parts[1].pos
    -- Look backwards to find the start of the paragraph containing the first article
    local before_first = body:sub(1, first_article_pos - 1)
    local last_tag_end = 1
    for i = #before_first, 1, -1 do
      if before_first:sub(i, i) == '>' then
        last_tag_end = i + 1
        break
      end
    end
    header_content = body:sub(1, last_tag_end - 1)
  else
    -- No articles found, everything is header
    header_content = body
  end

  -- Extract content between article markers
  for i, part in ipairs(article_parts) do
    local start_pos = part.pos
    local next_article_pos = article_parts[i + 1] and article_parts[i + 1].pos or #body

    -- Find where this article ends (before the next article starts)
    local end_pos
    if article_parts[i + 1] then
      -- Look backwards from next article to find the closing </p>
      local before_next = body:sub(start_pos, next_article_pos - 1)

      -- Find the last </p> before the next article
      local last_p_close = 0
      for match_pos in before_next:gmatch("()</[pP]>") do
        last_p_close = match_pos
      end

      if last_p_close > 0 then
        -- Position is relative to start_pos, convert to absolute
        end_pos = start_pos + last_p_close + 3 - 1 -- +3 for </p>, -1 for 0-indexing
      else
        -- Fallback: stop just before next article
        end_pos = next_article_pos - 1
      end
    else
      -- Last article - take everything to the end
      end_pos = #body
    end

    -- Look backwards to find the opening <p> tag for this article
    -- We want to capture the complete <p...> tag with all attributes
    local before = body:sub(math.max(1, start_pos - 2000), start_pos - 1)
    local p_start_distance = 0

    -- Find the opening <p (could have attributes)
    for j = #before, 1, -1 do
      if before:sub(j, j+1) == "<p" or before:sub(j, j+1) == "<P" then
        p_start_distance = #before - j + 1
        break
      end
    end

    -- Extract the full content starting from the <p> tag
    local content_start = p_start_distance > 0 and (start_pos - p_start_distance) or start_pos
    local full_content = body:sub(content_start, end_pos)

    -- Clean up and create article entry
    local article_num = part.num

    -- Ensure content is properly wrapped
    if not full_content:match("^%s*<") then
      full_content = "<div>" .. full_content .. "</div>"
    end

    local raw_content = full_content
    local compiled_content = remove_strikethrough(full_content)

    -- Extract title (first sentence without HTML tags)
    local text_only = compiled_content:gsub("<[^>]+>", "")
    text_only = text_only:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    -- Remove the "Art. X" prefix from title if present
    -- Handles: Art. 1, Art. 1º, Art. 26-A, Art. 1º-AB, etc.
    -- Also removes optional dash/en-dash/em-dash after article number
    -- Pattern matches hyphen (-), en-dash (–), and em-dash (—)
    text_only = text_only:gsub("^Art%.%s*%d+[ºo°]?[%-–—]?[A-Z]*%.?%s*[%-–—]?%s*", "")

    -- Also try to remove if there's a line break or tag between Art and number
    if text_only:match("^%s*$") or text_only == "" then
      -- Fallback: try to get content after the article marker more broadly
      text_only = compiled_content:gsub("<[^>]+>", "")
      text_only = text_only:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      -- Try alternative patterns (greedy to handle edge cases)
      text_only = text_only:gsub("^.*Art%.%s*%d+[ºo°]?[%-–—]?[A-Z]*%.?%s*[%-–—]?%s*", "")
    end

    -- Extract first 80 chars as title, or use placeholder if empty
    local title
    if text_only and text_only ~= "" and not text_only:match("^%s*$") then
      title = text_only:sub(1, math.min(#text_only, 80))
      if #text_only > 80 then
        title = title .. "..."
      end
    else
      -- Check if article is completely revoked (all content in strike)
      local raw_text = raw_content:gsub("<[^>]+>", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      if raw_text ~= "" and (compiled_content:gsub("<[^>]+>", ""):gsub("%s+", ""):match("^%s*$")) then
        title = "Artigo " .. article_num .. " (Revogado)"
      else
        title = "Artigo " .. article_num
      end
    end

    -- Check for strikethrough content
    local has_strike_tag = raw_content:match("<strike>") or raw_content:match("<STRIKE>")
    local has_strike_css = raw_content:match("text%-decoration%s*:%s*line%-through")
    local has_any_strike = has_strike_tag or has_strike_css

    table.insert(articles, {
      number = article_num,
      title = title,
      raw = raw_content,
      compiled = compiled_content,
      has_modifications = has_any_strike
    })
  end

  return articles, header_content
end

-- Parse page structure from HTML
function M.parse(html, url)
  local page_info = extract_page_info(url, html)
  local ementa = extract_ementa(html)
  local articles, header = parse_articles(html)

  local page_id = "Lei " .. page_info.number
  if page_info.year ~= "unknown" then
    page_id = page_id .. "/" .. page_info.year
  end

  return {
    page_id = page_id,
    number = page_info.number,
    year = page_info.year,
    title = page_info.title,
    ementa = ementa,
    articles = articles,
    header = header,
    url = url
  }
end

-- Build spine structure for raw version
function M.build_raw_spine(parsed_page)
  -- Add CSS to preserve formatting
  local content_parts = {
    [[<style>
      .law-header { margin-bottom: 2em; }
      .law-header p[align="center"], .law-header p[style*="text-align:center"] {
        text-align: center;
        margin: 1em 0;
      }
      .law-header strong, .law-header b {
        font-weight: bold;
      }
      .article { margin: 2em 0; }
      .article h2 {
        font-weight: bold;
        margin: 1.5em 0 0.5em 0;
      }
      /* Preserve centered sections/titles within articles */
      p[align="center"], p[style*="text-align:center"] {
        text-align: center;
        font-weight: bold;
        margin: 1.5em 0;
      }
      /* Ensure strikethrough styling is preserved - multiple selectors for compatibility */
      strike,
      s,
      del,
      [style*="text-decoration: line-through"],
      [style*="text-decoration:line-through"],
      span[style*="line-through"],
      font[style*="line-through"] {
        text-decoration: line-through !important;
        color: #666 !important;
      }
    </style>]]
  }

  -- Start with header content (brasão, título, ementa, preâmbulo)
  if parsed_page.header and parsed_page.header ~= "" then
    table.insert(content_parts, '<div class="law-header">')
    table.insert(content_parts, parsed_page.header)
    table.insert(content_parts, '</div>')
  end

  -- Add all articles
  for _, article in ipairs(parsed_page.articles) do
    -- Use concatenation to avoid string.format issues with % in content
    local article_html = '<div class="article" id="article-' .. article.number .. '">\n'
      .. '  <h2>Artigo ' .. article.number .. '</h2>\n'
      .. '  ' .. article.raw .. '\n'
      .. '</div>\n'
    table.insert(content_parts, article_html)
  end

  -- Create a single spine entry with all content
  local full_content = table.concat(content_parts, "\n")

  return {
    {
      content = full_content,
      href = "pagina-completa",
      title = parsed_page.title or "Página Completa",
      index = 1
    }
  }
end

-- Build spine structure for compiled version
function M.build_compiled_spine(parsed_page)
  -- Add CSS to preserve formatting
  local content_parts = {
    [[<style>
      .law-header { margin-bottom: 2em; }
      .law-header p[align="center"], .law-header p[style*="text-align:center"] {
        text-align: center;
        margin: 1em 0;
      }
      .law-header strong, .law-header b {
        font-weight: bold;
      }
      .article { margin: 2em 0; }
      .article h2 {
        font-weight: bold;
        margin: 1.5em 0 0.5em 0;
      }
      /* Preserve centered sections/titles within articles */
      p[align="center"], p[style*="text-align:center"] {
        text-align: center;
        font-weight: bold;
        margin: 1.5em 0;
      }
    </style>]]
  }

  -- Start with header content (brasão, título, ementa, preâmbulo)
  if parsed_page.header and parsed_page.header ~= "" then
    -- Apply strikethrough removal to header as well
    local compiled_header = remove_strikethrough(parsed_page.header)
    table.insert(content_parts, '<div class="law-header">')
    table.insert(content_parts, compiled_header)
    table.insert(content_parts, '</div>')
  end

  -- Add all articles
  for _, article in ipairs(parsed_page.articles) do
    -- For compiled version, check if article content is empty after removing strikethrough
    local content_text = article.compiled:gsub("<[^>]+>", ""):gsub("%s+", "")
    local article_content

    if content_text == "" or content_text:match("^%s*$") then
      -- Article is completely revoked - show placeholder
      article_content = '<p><em>(Artigo revogado)</em></p>'
    else
      article_content = article.compiled
    end

    -- Use concatenation to avoid string.format issues with % in content
    local article_html = '<div class="article" id="article-' .. article.number .. '">\n'
      .. '  <h2>Artigo ' .. article.number .. '</h2>\n'
      .. '  ' .. article_content .. '\n'
      .. '</div>\n'
    table.insert(content_parts, article_html)
  end

  -- Create a single spine entry with all content
  local full_content = table.concat(content_parts, "\n")

  return {
    {
      content = full_content,
      href = "pagina-completa",
      title = parsed_page.title or "Página Completa",
      index = 1
    }
  }
end

-- Build table of contents
function M.build_toc(parsed_page)
  local toc = {}

  for _, article in ipairs(parsed_page.articles) do
    table.insert(toc, {
      label = "Art. " .. article.number .. ": " .. article.title,
      href = "pagina-completa#article-" .. article.number,
      level = 1
    })
  end

  return toc
end

return M
