local M = {}

-- HTML Entities decoder (basic)
local function decode_entities(str)
  str = str:gsub("&lt;", "<")
  str = str:gsub("&gt;", ">")
  str = str:gsub("&amp;", "&")
  str = str:gsub("&quot;", '"')
  str = str:gsub("&apos;", "'")
  str = str:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
  str = str:gsub("&#x(%x+);", function(n) return string.char(tonumber(n, 16)) end)
  return str
end

-- Tag definitions
local block_tags = {
  h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
  p = true, div = true, blockquote = true,
  ul = true, ol = true, li = true,
  br = true, hr = true,
  pre = true, code = true,
  table = true, tr = true, td = true, th = true,
  dl = true, dt = true, dd = true
}

local highlight_map = {
  h1 = "InkH1",
  h2 = "InkH2",
  h3 = "InkH3",
  h4 = "InkH4",
  h5 = "InkH5",
  h6 = "InkH6",
  b = "Bold",
  strong = "Bold",
  i = "Italic",
  em = "Italic",
  -- Note: <a> tags handled specially - only underlined if they have href
  blockquote = "Comment",
  code = "InkCode",
  pre = "InkCode",
  dt = "InkBold",
  mark = "InkHighlight",
  s = "InkStrikethrough",
  strike = "InkStrikethrough",
  del = "InkStrikethrough",
  u = "Underlined"
}

function M.parse(content, max_width)
  local lines = {}
  local highlights = {} -- { {line_idx, col_start, col_end, group}, ... }
  local links = {} -- { {line_idx, col_start, col_end, href}, ... }
  local images = {} -- { {line_idx, col_start, col_end, src}, ... }
  local anchors = {} -- { id = line_idx }

  local current_line = ""
  local style_stack = {} -- { {tag=, start_col=, href=} }
  local list_stack = {} -- { {type="ul"|"ol", level=N, counter=N} }
  local blockquote_depth = 0
  local in_pre = false
  local in_dd = false
  local line_start_indent = 0 -- Track indent at start of current line for wrapping

  -- Helper to calculate current indentation
  local function get_indent()
    local indent = ""
    -- Blockquote indentation (4 spaces per level)
    if blockquote_depth > 0 then
      indent = indent .. string.rep("    ", blockquote_depth)
    end
    -- List indentation (2 spaces per level)
    if #list_stack > 0 then
      indent = indent .. string.rep("  ", #list_stack)
    end
    -- Definition description indentation
    if in_dd then
      indent = indent .. "    "
    end
    return indent
  end

  -- Helper to flush current line
  local function new_line()
    if #current_line > 0 then
      table.insert(lines, current_line)
      current_line = ""
      line_start_indent = 0
    elseif #lines == 0 or lines[#lines] ~= "" then
      table.insert(lines, "")
    end
  end

  -- Helper to add text
  local function add_text(text)
    if in_pre then
      -- In pre blocks, preserve formatting, split by lines
      -- Split on newlines, preserving empty lines
      local pre_lines = {}
      local pos = 1
      while pos <= #text do
        local newline_pos = text:find("\n", pos, true)
        if newline_pos then
          table.insert(pre_lines, text:sub(pos, newline_pos - 1))
          pos = newline_pos + 1
        else
          -- Last line (no trailing newline)
          local last_line = text:sub(pos)
          if #last_line > 0 or pos > 1 then
            table.insert(pre_lines, last_line)
          end
          break
        end
      end

      -- Handle case where text is empty or just whitespace
      if #pre_lines == 0 then
        pre_lines = {""}
      end

      for i, line in ipairs(pre_lines) do
        if i > 1 or #current_line == 0 then
          -- Add indent for pre blocks
          local indent = get_indent()
          current_line = indent .. line

          -- Apply pre highlighting to entire line (only if line has content)
          if #current_line > 0 then
            local start_col = 0
            local end_col = #current_line
            table.insert(highlights, { #lines + 1, start_col, end_col, "InkCode" })
          end

          new_line()
        else
          current_line = current_line .. line
        end
      end
      return
    end

    -- Replace newlines and tabs with spaces
    text = text:gsub("[\n\r\t]", " ")

    local words = {}
    for word in text:gmatch("%S+") do
      table.insert(words, word)
    end

    for i, word in ipairs(words) do
      -- Add space if not at start of line
      local space = ""
      if #current_line > 0 and current_line:sub(-1) ~= " " then
        space = " "
      end

      -- Check if wrapping is needed
      if max_width and (#current_line + #space + #word > max_width) then
        new_line()
        -- When wrapping, add indent to continuation lines
        local indent = string.rep(" ", line_start_indent)
        current_line = indent
        space = ""
      end

      local start_col = #current_line
      current_line = current_line .. space .. word
      local end_col = #current_line

      -- Apply active styles
      for _, style in ipairs(style_stack) do
        local group = highlight_map[style.tag]
        -- Special case: only underline <a> tags that have href (actual links, not anchors)
        if style.tag == "a" then
          if style.href then
            table.insert(highlights, { #lines + 1, start_col, end_col, "Underlined" })
            table.insert(links, { #lines + 1, start_col, end_col, style.href })
          end
          -- Skip adding highlight for anchor tags without href
        elseif group then
          table.insert(highlights, { #lines + 1, start_col, end_col, group })
        end
      end
    end
  end

  -- Tokenize: find <...> or text
  local pos = 1
  while pos <= #content do
    local start_tag, end_tag = string.find(content, "<[^>]+>", pos)

    if not start_tag then
      -- No more tags, add remaining text
      local text = string.sub(content, pos)
      add_text(decode_entities(text))
      break
    end

    -- Add text before tag
    if start_tag > pos then
      local text = string.sub(content, pos, start_tag - 1)
      add_text(decode_entities(text))
    end

    -- Process tag
    local tag_content = string.sub(content, start_tag + 1, end_tag - 1)
    local is_closing = string.sub(tag_content, 1, 1) == "/"
    local tag_name = tag_content:match("^/?([%w]+)")

    if tag_name then
      tag_name = tag_name:lower()

      -- Capture ID for anchors
      local id = tag_content:match('id=["\']([^"\']+)["\']')
      if id then
        anchors[id] = #lines + 1
      end

      if tag_name == "img" then
         -- Handle Image
         local src = tag_content:match('src=["\']([^"\']+)["\']')
         if src then
            new_line()
            local indent = get_indent()
            local img_text = indent .. "[image] (press Enter to open)"
            local start_col = 0
            current_line = img_text
            table.insert(images, { #lines + 1, start_col, #img_text, src })
            table.insert(highlights, { #lines + 1, start_col, #img_text, "Special" })
            new_line()
         end
      elseif tag_name == "hr" then
         -- Handle horizontal rule
         new_line()
         local indent = get_indent()
         local rule = indent .. string.rep("─", math.min(60, max_width - #indent))
         current_line = rule
         table.insert(highlights, { #lines + 1, 0, #current_line, "InkHorizontalRule" })
         new_line()
      elseif is_closing then
        -- Closing tag
        if tag_name == "ul" or tag_name == "ol" then
          -- Pop from list stack
          if #list_stack > 0 then
            table.remove(list_stack)
          end
          new_line()
        elseif tag_name == "li" then
          new_line()
        elseif tag_name == "blockquote" then
          blockquote_depth = math.max(0, blockquote_depth - 1)
          new_line()
        elseif tag_name == "pre" then
          in_pre = false
          new_line()
        elseif tag_name == "dd" then
          in_dd = false
          new_line()
        elseif tag_name == "code" and not in_pre then
          -- Inline code closing - add backtick
          current_line = current_line .. "`"
        elseif block_tags[tag_name] then
          new_line()
        end

        -- Pop from style stack
        for i = #style_stack, 1, -1 do
          if style_stack[i].tag == tag_name then
            table.remove(style_stack, i)
            break
          end
        end
      else
        -- Opening tag
        if tag_name == "ul" then
          new_line()
          table.insert(list_stack, { type = "ul", level = #list_stack + 1 })
        elseif tag_name == "ol" then
          new_line()
          table.insert(list_stack, { type = "ol", level = #list_stack + 1, counter = 0 })
        elseif tag_name == "li" then
          new_line()
          -- Add list item prefix
          local indent = get_indent()
          local prefix = ""
          if #list_stack > 0 then
            local current_list = list_stack[#list_stack]
            if current_list.type == "ul" then
              prefix = "• "
            elseif current_list.type == "ol" then
              current_list.counter = current_list.counter + 1
              prefix = current_list.counter .. ". "
            end
          end
          current_line = indent .. prefix
          line_start_indent = #current_line
          -- Highlight the bullet/number
          if #prefix > 0 then
            table.insert(highlights, { #lines + 1, #indent, #current_line, "InkListItem" })
          end
        elseif tag_name == "blockquote" then
          new_line()
          blockquote_depth = blockquote_depth + 1
        elseif tag_name == "pre" then
          new_line()
          in_pre = true
        elseif tag_name == "code" and not in_pre then
          -- Inline code opening - add backtick
          current_line = current_line .. "`"
        elseif tag_name == "dd" then
          new_line()
          in_dd = true
        elseif tag_name == "dt" or tag_name == "dl" then
          new_line()
        elseif block_tags[tag_name] then
          new_line()
        end

        local href = nil
        if tag_name == "a" then
          href = tag_content:match('href=["\']([^"\']+)["\']')
        end

        table.insert(style_stack, { tag = tag_name, href = href })
      end
    end

    pos = end_tag + 1
  end

  -- Flush last line
  if #current_line > 0 then
    table.insert(lines, current_line)
  end

  return {
    lines = lines,
    highlights = highlights,
    links = links,
    images = images,
    anchors = anchors
  }
end

return M
