local tokens = require("ink.html.tokens")
local entities = require("ink.html.entities")
local utils = require("ink.html.utils")
local table_module = require("ink.html.table")

local M = {}

function M.get_indent(state)
  local indent = ""
  if state.blockquote_depth > 0 then
    for i = 1, state.blockquote_depth do
      indent = indent .. "│ "
    end
    indent = indent .. "  "
  end
  if #state.list_stack > 0 then
    indent = indent .. string.rep("  ", #state.list_stack)
  end
  if state.in_dd then
    indent = indent .. "    "
  end
  return indent
end

function M.new_line(state)
  if #state.current_line > 0 then
    table.insert(state.lines, state.current_line)

    local line_idx = #state.lines
    if state.in_heading or state.in_pre or #state.list_stack > 0 or state.in_dd or state.blockquote_depth > 0 or state.in_title then
      state.no_justify[line_idx] = true
    end

    if state.in_title then
      table.insert(state.highlights, { line_idx, 0, #state.current_line, "InkTitle" })
      state.centered_lines[line_idx] = true
    end

    state.current_line = ""
    state.line_start_indent = 0
  elseif #state.lines == 0 or state.lines[#state.lines] ~= "" then
    table.insert(state.lines, "")
  end
end

function M.add_text(state, text)
  -- If inside table cell, accumulate text in current_cell
  if state.table_state.in_table and state.table_state.in_row then
    state.table_state.current_cell = state.table_state.current_cell .. text
    return
  end

  if state.in_pre then
    local pre_lines = {}
    local pos = 1
    while pos <= #text do
      local newline_pos = text:find("\n", pos, true)
      if newline_pos then
        table.insert(pre_lines, text:sub(pos, newline_pos - 1))
        pos = newline_pos + 1
      else
        local last_line = text:sub(pos)
        if #last_line > 0 or pos > 1 then
          table.insert(pre_lines, last_line)
        end
        break
      end
    end

    if #pre_lines == 0 then
      pre_lines = {""}
    end

    for idx, line in ipairs(pre_lines) do
      if idx > 1 or #state.current_line == 0 then
        local indent = M.get_indent(state)
        state.current_line = indent .. line

        if #state.current_line > 0 then
          table.insert(state.highlights, { #state.lines + 1, 0, #state.current_line, "InkCode" })
        end

        M.new_line(state)
      else
        state.current_line = state.current_line .. line
      end
    end
    return
  end

  text = text:gsub("[\n\r\t]", " ")

  local words = {}
  for word in text:gmatch("%S+") do
    table.insert(words, word)
  end

  for _, word in ipairs(words) do
    if #state.current_line == 0 then
      local indent = M.get_indent(state)
      state.current_line = indent
      state.line_start_indent = #indent
    end

    local space = ""
    if #state.current_line > 0 and state.current_line:sub(-1) ~= " " then
      space = " "
    end

    local line_w = utils.display_width(state.current_line)
    local word_w = utils.display_width(word)
    if state.max_width and (line_w + #space + word_w > state.max_width) then
      M.new_line(state)
      local indent = string.rep(" ", state.line_start_indent)
      state.current_line = indent
      space = ""
    end

    state.current_line = state.current_line .. space
    local start_col = #state.current_line
    state.current_line = state.current_line .. word
    local end_col = #state.current_line

    for _, style in ipairs(state.style_stack) do
      if style.tag == "css_class" and style.css_group then
        table.insert(state.highlights, { #state.lines + 1, start_col, end_col, style.css_group })
      else
        local group = tokens.highlight_map[style.tag]
        if style.tag == "a" then
          if style.href then
            table.insert(state.highlights, { #state.lines + 1, start_col, end_col, "InkUnderlined" })
            table.insert(state.links, { #state.lines + 1, start_col, end_col, style.href })
          end
        elseif group then
          table.insert(state.highlights, { #state.lines + 1, start_col, end_col, group })
        end
      end
    end
  end
end

function M.process_tag(state, tag_name, tag_content, is_closing, start_tag, end_tag, content)
  -- Skip tags inside <head> except head and title
  if state.in_head and tag_name ~= "head" and tag_name ~= "title" then
    return
  end

  if tag_name == "img" then
    local src = tag_content:match('src=["\']([^"\']+)["\']')
    if src then
      M.new_line(state)
      local indent = M.get_indent(state)
      local img_text = indent .. "[image] (press Enter to open)"
      state.current_line = img_text
      table.insert(state.images, { #state.lines + 1, 0, #img_text, src })
      table.insert(state.highlights, { #state.lines + 1, 0, #img_text, "Special" })
      M.new_line(state)
    end
  elseif tag_name == "hr" then
    M.new_line(state)
    local indent = M.get_indent(state)
    local indent_width = utils.display_width(indent)
    local rule = indent .. string.rep("─", math.min(60, state.max_width - indent_width))
    state.current_line = rule
    table.insert(state.highlights, { #state.lines + 1, 0, #state.current_line, "InkHorizontalRule" })
    M.new_line(state)
  elseif is_closing then
    M.handle_closing_tag(state, tag_name)
  else
    M.handle_opening_tag(state, tag_name, tag_content, start_tag, end_tag, content)
  end
end

-- Handle table-related tags
function M.handle_table_tag(state, tag_name, is_closing)
  local ts = state.table_state

  if tag_name == "table" then
    if is_closing then
      -- Render the complete table
      if ts.in_table then
        M.new_line(state)
        local indent = M.get_indent(state)
        local table_lines = table_module.render_table(ts, state.max_width, indent)

        for _, line in ipairs(table_lines) do
          table.insert(state.lines, line)
          -- Mark table lines as no-justify
          state.no_justify[#state.lines] = true
        end

        M.new_line(state)
        -- Reset table state
        state.table_state = table_module.new_table_state()
      end
    else
      -- Start new table
      M.new_line(state)
      ts.in_table = true
      ts.headers = {}
      ts.rows = {}
      ts.current_row = {}
      ts.current_cell = ""
    end
  elseif tag_name == "thead" then
    ts.in_thead = not is_closing
  elseif tag_name == "tbody" then
    ts.in_tbody = not is_closing
  elseif tag_name == "tr" then
    if is_closing then
      -- Finish current row
      if ts.in_row and #ts.current_row > 0 then
        if ts.in_thead then
          ts.headers = ts.current_row
        else
          table.insert(ts.rows, ts.current_row)
        end
        ts.current_row = {}
      end
      ts.in_row = false
    else
      -- Start new row
      ts.in_row = true
      ts.current_row = {}
    end
  elseif tag_name == "th" or tag_name == "td" then
    if is_closing then
      -- Finish current cell
      if ts.in_row then
        table.insert(ts.current_row, ts.current_cell)
        ts.current_cell = ""
      end
    else
      -- Start new cell
      ts.current_cell = ""
    end
  end
end

function M.handle_closing_tag(state, tag_name)
  -- Handle table tags
  if tag_name == "table" or tag_name == "thead" or tag_name == "tbody" or
     tag_name == "tr" or tag_name == "th" or tag_name == "td" then
    M.handle_table_tag(state, tag_name, true)
    return
  end

  if tag_name == "head" then
    state.in_head = false
  elseif tag_name == "title" then
    if state.in_title then
      M.new_line(state)
      state.in_title = false
      M.new_line(state)
    end
  elseif tag_name == "ul" or tag_name == "ol" then
    if #state.list_stack > 0 then
      table.remove(state.list_stack)
    end
    M.new_line(state)
  elseif tag_name == "li" then
    M.new_line(state)
  elseif tag_name == "blockquote" then
    state.blockquote_depth = math.max(0, state.blockquote_depth - 1)
    M.new_line(state)
  elseif tag_name == "pre" then
    state.in_pre = false
    M.new_line(state)
  elseif tag_name == "dd" then
    state.in_dd = false
    M.new_line(state)
  elseif tag_name == "code" and not state.in_pre then
    state.current_line = state.current_line .. "`"
  elseif tag_name:match("^h[1-6]$") then
    state.in_heading = false
    M.new_line(state)
  elseif tokens.block_tags[tag_name] then
    M.new_line(state)
  end

  for i = #state.style_stack, 1, -1 do
    if state.style_stack[i].tag == tag_name then
      table.remove(state.style_stack, i)
      while i <= #state.style_stack and state.style_stack[i].tag == "css_class" do
        table.remove(state.style_stack, i)
      end
      break
    end
  end

  if state.in_title and tokens.block_tags[tag_name] then
    state.in_title = false
    M.new_line(state)
    M.new_line(state)
  end
end

function M.handle_opening_tag(state, tag_name, tag_content, start_tag, end_tag, content)
  -- Handle table tags
  if tag_name == "table" or tag_name == "thead" or tag_name == "tbody" or
     tag_name == "tr" or tag_name == "th" or tag_name == "td" then
    M.handle_table_tag(state, tag_name, false)
    return
  end

  if tag_name == "head" then
    state.in_head = true
  elseif tag_name == "title" then
    M.new_line(state)
    M.new_line(state)
    state.in_title = true
  elseif tag_name == "ul" then
    M.new_line(state)
    table.insert(state.list_stack, { type = "ul", level = #state.list_stack + 1 })
  elseif tag_name == "ol" then
    M.new_line(state)
    table.insert(state.list_stack, { type = "ol", level = #state.list_stack + 1, counter = 0 })
  elseif tag_name == "li" then
    M.new_line(state)
    local indent = M.get_indent(state)
    local prefix = ""
    if #state.list_stack > 0 then
      local current_list = state.list_stack[#state.list_stack]
      if current_list.type == "ul" then
        prefix = "• "
      elseif current_list.type == "ol" then
        current_list.counter = current_list.counter + 1
        prefix = current_list.counter .. ". "
      end
    end
    state.current_line = indent .. prefix
    state.line_start_indent = #state.current_line
    if #prefix > 0 then
      table.insert(state.highlights, { #state.lines + 1, #indent, #state.current_line, "InkListItem" })
    end
  elseif tag_name == "blockquote" then
    M.new_line(state)
    state.blockquote_depth = state.blockquote_depth + 1
  elseif tag_name == "pre" then
    M.new_line(state)

    local pre_close_pattern = "</pre>"
    local pre_content_start = end_tag + 1
    local pre_close_start, pre_close_end = string.find(content:lower(), pre_close_pattern, pre_content_start, true)

    if pre_close_start then
      -- Process pre content inline without adding to style_stack
      state.in_pre = true
      local pre_content = string.sub(content, pre_content_start, pre_close_start - 1)
      M.add_text(state, entities.decode_entities(pre_content))
      state.in_pre = false
      M.new_line(state)
      -- Return new position to skip processed content (don't add to style_stack)
      return pre_close_end
    else
      -- Fallback: add to style_stack for normal processing
      state.in_pre = true
    end
  elseif tag_name == "code" and not state.in_pre then
    state.current_line = state.current_line .. "`"
  elseif tag_name == "dd" then
    M.new_line(state)
    state.in_dd = true
  elseif tag_name == "dt" or tag_name == "dl" then
    M.new_line(state)
  elseif tag_name:match("^h[1-6]$") then
    M.new_line(state)
    state.in_heading = true
  elseif tokens.block_tags[tag_name] then
    M.new_line(state)
  end

  local href = nil
  if tag_name == "a" then
    href = tag_content:match('href=["\']([^"\']+)["\']')
  end

  table.insert(state.style_stack, { tag = tag_name, href = href })

  if state.class_styles then
    local class_attr = tag_content:match('class=["\']([^"\']+)["\']')
    if class_attr then
      for class_name in class_attr:gmatch("%S+") do
        local style = state.class_styles[class_name]
        if style then
          if style.is_title then
            state.in_title = true
            M.new_line(state)
            M.new_line(state)
          end

          local css_parser = require("ink.css_parser")
          local hl_groups = css_parser.get_highlight_groups(style)
          for _, group in ipairs(hl_groups) do
            table.insert(state.style_stack, { tag = "css_class", css_group = group })
          end
        end
      end
    end
  end
end

function M.apply_justification(lines, highlights, links, images, no_justify, max_width)
  local justify_map = {}

  for i, line in ipairs(lines) do
    local line_width = utils.display_width(line)
    if not no_justify[i] and line_width > 0 then
      local min_length = math.floor(max_width * 0.90)
      if line_width >= min_length and line_width < max_width then
        local word_info = {}
        local pos = 1
        while pos <= #line do
          while pos <= #line and line:sub(pos, pos) == " " do
            pos = pos + 1
          end
          if pos > #line then break end

          local word_start = pos
          while pos <= #line and line:sub(pos, pos) ~= " " do
            pos = pos + 1
          end
          local word_end = pos - 1
          local word = line:sub(word_start, word_end)

          table.insert(word_info, {
            word = word,
            orig_start = word_start - 1,
            orig_end = word_end
          })
        end

        if #word_info > 1 then
          local spaces_needed = max_width - line_width
          local gaps = #word_info - 1
          local base_spaces = 1
          local extra_spaces = math.floor(spaces_needed / gaps)
          local remainder = spaces_needed % gaps

          local new_line = word_info[1].word
          word_info[1].new_start = 0
          word_info[1].new_end = #word_info[1].word

          for j = 2, #word_info do
            local space_count = base_spaces + extra_spaces
            if j - 1 <= remainder then
              space_count = space_count + 1
            end
            new_line = new_line .. string.rep(" ", space_count)
            word_info[j].new_start = #new_line
            new_line = new_line .. word_info[j].word
            word_info[j].new_end = #new_line
          end

          justify_map[i] = word_info

          for _, hl in ipairs(highlights) do
            if hl[1] == i then
              hl[2] = utils.forward_map_column(word_info, hl[2])
              hl[3] = utils.forward_map_column(word_info, hl[3])
            end
          end

          for _, link in ipairs(links) do
            if link[1] == i then
              link[2] = utils.forward_map_column(word_info, link[2])
              link[3] = utils.forward_map_column(word_info, link[3])
            end
          end

          for _, img in ipairs(images) do
            if img[1] == i then
              img[2] = utils.forward_map_column(word_info, img[2])
              img[3] = utils.forward_map_column(word_info, img[3])
            end
          end

          lines[i] = new_line
        end
      end
    end
  end

  return justify_map
end

return M