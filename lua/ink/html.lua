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
  b = "InkBold",
  strong = "InkBold",
  i = "InkItalic",
  em = "InkItalic",
  -- Note: <a> tags handled specially - only underlined if they have href
  blockquote = "Comment",
  code = "InkCode",
  pre = "InkCode",
  dt = "InkBold",
  mark = "InkHighlight",
  s = "InkStrikethrough",
  strike = "InkStrikethrough",
  del = "InkStrikethrough",
  u = "InkUnderlined"
}

function M.parse(content, max_width, class_styles, justify_text)
  local lines = {}
  local highlights = {} -- { {line_idx, col_start, col_end, group}, ... }
  local links = {} -- { {line_idx, col_start, col_end, href}, ... }
  local images = {} -- { {line_idx, col_start, col_end, src}, ... }
  local anchors = {} -- { id = line_idx }
  local no_justify = {} -- Track lines that should NOT be justified (headings, code, lists, short lines)

  local current_line = ""
  local style_stack = {} -- { {tag=, start_col=, href=} }
  local list_stack = {} -- { {type="ul"|"ol", level=N, counter=N} }
  local blockquote_depth = 0
  local in_pre = false
  local in_dd = false
  local line_start_indent = 0 -- Track indent at start of current line for wrapping
  local in_heading = false -- Track if we're in a heading
  local in_title = false -- Track if we're in a title element
  local in_head = false -- Track if we're in the <head> section (skip content)

  -- Helper to calculate current indentation
  local function get_indent()
    local indent = ""
    -- Blockquote indentation with visual markers
    if blockquote_depth > 0 then
      -- Add vertical bar markers for each nesting level
      for i = 1, blockquote_depth do
        indent = indent .. "│ "
      end
      -- Add extra spacing after the markers
      indent = indent .. "  "
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
      -- Special handling for title lines - center them
      if in_title then
        local text_length = #current_line
        if text_length < max_width then
          local padding = math.floor((max_width - text_length) / 2)
          current_line = string.rep(" ", padding) .. current_line
        end
      end

      table.insert(lines, current_line)

      -- Mark lines that should NOT be justified
      local line_idx = #lines
      if in_heading or in_pre or #list_stack > 0 or in_dd or blockquote_depth > 0 or in_title then
        no_justify[line_idx] = true
      end

      -- Apply title highlighting to the entire line
      if in_title then
        table.insert(highlights, { line_idx, 0, #current_line, "InkTitle" })
      end

      current_line = ""
      line_start_indent = 0
    elseif #lines == 0 or lines[#lines] ~= "" then
      table.insert(lines, "")
    end
  end

  -- Helper to add text
  local function add_text(text)
    -- Debug: uncomment to see state
    -- local indent_len = #get_indent()
    -- if indent_len > 0 then
    --   print(string.format("add_text: in_pre=%s, blockquote_depth=%d, list_stack=%d, in_dd=%s, indent=%d",
    --     tostring(in_pre), blockquote_depth, #list_stack, tostring(in_dd), indent_len))
    -- end

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

      for idx, line in ipairs(pre_lines) do
        if idx > 1 or #current_line == 0 then
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

    for _, word in ipairs(words) do
      -- At start of line, add blockquote/list/dd indent
      if #current_line == 0 then
        local indent = get_indent()
        current_line = indent
        line_start_indent = #indent
      end

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

      -- Add space first, then calculate start_col so highlights don't include the space
      current_line = current_line .. space
      local start_col = #current_line
      current_line = current_line .. word
      local end_col = #current_line

      -- Apply active styles
      for _, style in ipairs(style_stack) do
        -- Check if this is a CSS-based style
        if style.tag == "css_class" and style.css_group then
          table.insert(highlights, { #lines + 1, start_col, end_col, style.css_group })
        else
          local group = highlight_map[style.tag]
          -- Special case: only underline <a> tags that have href (actual links, not anchors)
          if style.tag == "a" then
            if style.href then
              table.insert(highlights, { #lines + 1, start_col, end_col, "InkUnderlined" })
              table.insert(links, { #lines + 1, start_col, end_col, style.href })
            end
            -- Skip adding highlight for anchor tags without href
          elseif group then
            table.insert(highlights, { #lines + 1, start_col, end_col, group })
          end
        end
      end
    end
  end

  -- Tokenize: find <...> or text
  local pos = 1
  while pos <= #content do
    ::continue::
    local start_tag, end_tag = string.find(content, "<[^>]+>", pos)

    if not start_tag then
      -- No more tags, add remaining text (skip if in head section, unless in title)
      if not in_head or in_title then
        local text = string.sub(content, pos)
        add_text(decode_entities(text))
      end
      break
    end

    -- Add text before tag (skip if in head section, unless in title)
    if start_tag > pos and (not in_head or in_title) then
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
        if tag_name == "head" then
          -- End of head section - resume processing content
          in_head = false
        elseif tag_name == "title" then
          -- Closing title tag - display styled regardless of head/body
          if in_title then
            new_line() -- Flush the title line while in_title is still true (for centering/highlight)
            in_title = false
            new_line() -- Add blank line after title
          end
        elseif tag_name == "ul" or tag_name == "ol" then
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
          -- Only process closing </pre> if we're still in pre mode
          -- (if we already handled it during opening tag, in_pre will be false)
          if in_pre then
            in_pre = false
            new_line()
          end
        elseif tag_name == "dd" then
          in_dd = false
          new_line()
        elseif tag_name == "code" and not in_pre then
          -- Inline code closing - add backtick
          current_line = current_line .. "`"
        elseif tag_name:match("^h[1-6]$") then
          -- Closing heading tag
          in_heading = false
          new_line()
        elseif block_tags[tag_name] then
          new_line()
        end

        -- Pop from style stack (including CSS classes)
        for i = #style_stack, 1, -1 do
          if style_stack[i].tag == tag_name then
            -- Found the tag, remove it
            table.remove(style_stack, i)
            -- Also remove any css_class entries that were added right after it
            while i <= #style_stack and style_stack[i].tag == "css_class" do
              table.remove(style_stack, i)
            end
            break
          end
        end

        -- If we're closing a block tag and we're in a title, close the title
        if in_title and block_tags[tag_name] then
          in_title = false
          new_line() -- Add blank line after title
          new_line()
        end
      else
        -- Opening tag
        if tag_name == "head" then
          -- Start of head section - skip most content (except title)
          in_head = true
        elseif tag_name == "title" then
          -- Title tag - display styled even if in head section
          new_line()
          new_line() -- Add blank line before title
          in_title = true
        elseif tag_name == "ul" then
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

          -- Special handling: extract content until </pre> without tokenizing
          -- This prevents < and > characters in code from being treated as tags
          local pre_close_pattern = "</pre>"
          local pre_content_start = end_tag + 1
          local pre_close_start, pre_close_end = string.find(content:lower(), pre_close_pattern, pre_content_start, true)

          if pre_close_start then
            -- Extract and add the pre content directly
            local pre_content = string.sub(content, pre_content_start, pre_close_start - 1)
            -- print(string.format("DEBUG: Extracted pre content: %q", pre_content:sub(1, 50)))
            add_text(decode_entities(pre_content))

            -- Close the pre block
            in_pre = false
            new_line()

            -- Skip ahead past the </pre> tag
            -- print(string.format("DEBUG: Skipping from pos=%d to pos=%d", pos, pre_close_end + 1))
            pos = pre_close_end + 1
            goto continue
          end
        elseif tag_name == "code" and not in_pre then
          -- Inline code opening - add backtick
          current_line = current_line .. "`"
        elseif tag_name == "dd" then
          new_line()
          in_dd = true
        elseif tag_name == "dt" or tag_name == "dl" then
          new_line()
        elseif tag_name:match("^h[1-6]$") then
          -- Opening heading tag
          new_line()
          in_heading = true
        elseif block_tags[tag_name] then
          new_line()
        end

        local href = nil
        if tag_name == "a" then
          href = tag_content:match('href=["\']([^"\']+)["\']')
        end

        -- Push the tag to style stack
        table.insert(style_stack, { tag = tag_name, href = href })

        -- Also check for class attribute and apply CSS-based styles
        if class_styles then
          local class_attr = tag_content:match('class=["\']([^"\']+)["\']')
          if class_attr then
            -- Handle multiple classes (space-separated)
            for class_name in class_attr:gmatch("%S+") do
              local style = class_styles[class_name]
              if style then
                -- Check if this is a title class
                if style.is_title then
                  in_title = true
                  new_line() -- Add blank line before title
                  new_line()
                end

                -- Create pseudo-tags for each style found in CSS
                local css_parser = require("ink.css_parser")
                local hl_groups = css_parser.get_highlight_groups(style)
                for _, group in ipairs(hl_groups) do
                  -- Push a special marker for CSS-based styling
                  table.insert(style_stack, { tag = "css_class", css_group = group })
                end
              end
            end
          end
        end
      end
    end

    pos = end_tag + 1
  end

  -- Flush last line
  if #current_line > 0 then
    table.insert(lines, current_line)
  end

  -- Merge consecutive highlights with the same group on the same line
  local function merge_highlights(hls)
    if #hls == 0 then return hls end

    -- Sort by line, then by start column
    table.sort(hls, function(a, b)
      if a[1] ~= b[1] then
        return a[1] < b[1]
      end
      return a[2] < b[2]
    end)

    local merged = {}
    local current = hls[1]

    for i = 2, #hls do
      local next_hl = hls[i]

      -- Check if same line and same group and adjacent/overlapping
      if current[1] == next_hl[1] and
         current[4] == next_hl[4] and
         current[3] >= next_hl[2] - 1 then  -- -1 to merge across single space gaps
        -- Merge: extend current to include next
        current[3] = math.max(current[3], next_hl[3])
      else
        -- Can't merge, save current and start new one
        table.insert(merged, current)
        current = next_hl
      end
    end

    -- Don't forget the last one
    table.insert(merged, current)
    return merged
  end

  highlights = merge_highlights(highlights)

  -- Justify mapping info for user highlights
  local justify_map = {} -- { [line_idx] = word_info_array }

  -- Apply text justification if enabled
  if justify_text then
    for i, line in ipairs(lines) do
      -- Skip lines that shouldn't be justified
      if not no_justify[i] and #line > 0 then
        -- Only justify lines that are very close to max_width (90%+)
        -- These are lines that were wrapped to fit, not naturally short lines
        local min_length = math.floor(max_width * 0.90)
        if #line >= min_length and #line < max_width then
          -- Parse words with their original positions
          local word_info = {} -- { {word=, orig_start=, orig_end=}, ... }
          local pos = 1
          while pos <= #line do
            -- Skip spaces
            while pos <= #line and line:sub(pos, pos) == " " do
              pos = pos + 1
            end
            if pos > #line then break end

            -- Find word
            local word_start = pos
            while pos <= #line and line:sub(pos, pos) ~= " " do
              pos = pos + 1
            end
            local word_end = pos - 1
            local word = line:sub(word_start, word_end)

            table.insert(word_info, {
              word = word,
              orig_start = word_start - 1, -- Convert to 0-based for highlights
              orig_end = word_end          -- 0-based end (exclusive)
            })
          end

          if #word_info > 1 then
            -- Calculate spaces to distribute
            local spaces_needed = max_width - #line
            local gaps = #word_info - 1
            local base_spaces = 1 -- Minimum one space between words
            local extra_spaces = math.floor(spaces_needed / gaps)
            local remainder = spaces_needed % gaps

            -- Rebuild line with distributed spaces and track new positions
            local new_line = word_info[1].word
            word_info[1].new_start = 0
            word_info[1].new_end = #word_info[1].word

            for j = 2, #word_info do
              local space_count = base_spaces + extra_spaces
              -- Distribute remainder across first N gaps
              if j - 1 <= remainder then
                space_count = space_count + 1
              end
              new_line = new_line .. string.rep(" ", space_count)
              word_info[j].new_start = #new_line
              new_line = new_line .. word_info[j].word
              word_info[j].new_end = #new_line
            end

            -- Store mapping info for this line (for user highlights)
            justify_map[i] = word_info

            -- Helper function to map old column to new column
            local function map_column(col)
              -- Find which word this column belongs to
              for _, wi in ipairs(word_info) do
                if col >= wi.orig_start and col < wi.orig_end then
                  -- Column is inside this word
                  local offset = col - wi.orig_start
                  return wi.new_start + offset
                elseif col == wi.orig_end then
                  -- Column is at word end (exclusive boundary)
                  return wi.new_end
                end
              end
              -- Column is in space between words or before first word
              -- Find nearest word and map to its boundary
              for idx, wi in ipairs(word_info) do
                if col < wi.orig_start then
                  -- Before this word
                  if idx == 1 then
                    return col -- Preserve leading space position
                  else
                    -- In gap before this word, map to end of previous word's space
                    return wi.new_start
                  end
                end
              end
              -- After last word
              return #new_line
            end

            -- Update highlights for this line
            for _, hl in ipairs(highlights) do
              if hl[1] == i then
                hl[2] = map_column(hl[2])
                hl[3] = map_column(hl[3])
              end
            end

            -- Update links for this line
            for _, link in ipairs(links) do
              if link[1] == i then
                link[2] = map_column(link[2])
                link[3] = map_column(link[3])
              end
            end

            -- Update images for this line
            for _, img in ipairs(images) do
              if img[1] == i then
                img[2] = map_column(img[2])
                img[3] = map_column(img[3])
              end
            end

            -- Update line
            lines[i] = new_line
          end
        end
      end
    end
  end

  return {
    lines = lines,
    highlights = highlights,
    links = links,
    images = images,
    anchors = anchors,
    justify_map = justify_map
  }
end

-- Forward map: canonical (non-justified) -> justified position
function M.forward_map_column(word_info, col)
  if not word_info then return col end

  -- Find which word this column belongs to
  for _, wi in ipairs(word_info) do
    if col >= wi.orig_start and col < wi.orig_end then
      -- Column is inside this word
      local offset = col - wi.orig_start
      return wi.new_start + offset
    elseif col == wi.orig_end then
      -- Column is at word end (exclusive boundary)
      return wi.new_end
    end
  end

  -- Column is in space between words or before first word
  for idx, wi in ipairs(word_info) do
    if col < wi.orig_start then
      if idx == 1 then
        return col -- Preserve leading space position
      else
        return wi.new_start
      end
    end
  end

  -- After last word
  local last = word_info[#word_info]
  return last and last.new_end or col
end

-- Reverse map: justified -> canonical (non-justified) position
function M.reverse_map_column(word_info, col)
  if not word_info then return col end

  -- Find which word this column belongs to (using new positions)
  for _, wi in ipairs(word_info) do
    if col >= wi.new_start and col < wi.new_end then
      -- Column is inside this word
      local offset = col - wi.new_start
      return wi.orig_start + offset
    elseif col == wi.new_end then
      -- Column is at word end (exclusive boundary)
      return wi.orig_end
    end
  end

  -- Column is in space between words or before first word
  for idx, wi in ipairs(word_info) do
    if col < wi.new_start then
      if idx == 1 then
        return col -- Preserve leading space position
      else
        -- In gap before this word, snap to previous word's end
        local prev = word_info[idx - 1]
        return prev.orig_end
      end
    end
  end

  -- After last word
  local last = word_info[#word_info]
  return last and last.orig_end or col
end

return M
