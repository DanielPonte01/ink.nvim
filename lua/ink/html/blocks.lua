-- lua/ink/html/blocks.lua
-- Responsabilidade: Processamento de tags block-level (headings, lists, blockquotes, pre, dl)

local tokens = require("ink.html.tokens")
local entities = require("ink.html.entities")
local text = require("ink.html.text")

local M = {}

function M.handle_closing_tag(state, tag_name)
  if tag_name == "head" then
    state.in_head = false
  elseif tag_name == "title" then
    if state.in_title then
      text.new_line(state)
      state.in_title = false
      text.new_line(state)
    end
  elseif tag_name == "ul" or tag_name == "ol" then
    if #state.list_stack > 0 then
      table.remove(state.list_stack)
    end
    text.new_line(state)
  elseif tag_name == "li" then
    text.new_line(state)
  elseif tag_name == "blockquote" then
    state.blockquote_depth = math.max(0, state.blockquote_depth - 1)
    text.new_line(state)
  elseif tag_name == "pre" then
    state.in_pre = false
    text.new_line(state)
  elseif tag_name == "dd" then
    state.in_dd = false
    text.new_line(state)
  elseif tag_name == "code" and not state.in_pre then
    state.current_line = state.current_line .. "`"
  elseif tag_name:match("^h[1-6]$") then
    -- Save heading information before closing
    if state.current_heading_level then
      local level = tonumber(tag_name:match("h([1-6])"))
      local heading_text = state.current_heading_text:match("^%s*(.-)%s*$")  -- trim

      -- Check if this is a title (has title attribute OR CSS class with title)
      local is_title = (state.current_heading_title_attr ~= nil) or state.current_heading_is_title

      -- Determine which text to use
      local display_text = heading_text
      if state.current_heading_title_attr and #state.current_heading_title_attr > 0 then
        -- Prefer title attribute over content text
        display_text = state.current_heading_title_attr:match("^%s*(.-)%s*$")
      end

      if #display_text > 0 then
        if is_title then
          -- This is a title - save with level 0 (no indentation)
          table.insert(state.headings, {
            level = 0,
            text = display_text,
            id = state.current_heading_id,
            line = #state.lines + 1
          })
        elseif level <= 3 then
          -- This is a regular H1-H3 heading
          table.insert(state.headings, {
            level = level,
            text = display_text,
            id = state.current_heading_id,
            line = #state.lines + 1
          })
        end
      end
    end

    state.in_heading = false
    state.current_heading_level = nil
    state.current_heading_text = ""
    state.current_heading_id = nil
    state.current_heading_title_attr = nil
    state.current_heading_is_title = false
    text.new_line(state)
  elseif tokens.block_tags[tag_name] then
    text.new_line(state)
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
    text.new_line(state)
    text.new_line(state)
  end
end

function M.handle_opening_tag(state, tag_name, tag_content, start_tag, end_tag, content)
  if tag_name == "head" then
    state.in_head = true
  elseif tag_name == "title" then
    text.new_line(state)
    text.new_line(state)
    state.in_title = true
  elseif tag_name == "ul" then
    text.new_line(state)
    table.insert(state.list_stack, { type = "ul", level = #state.list_stack + 1 })
  elseif tag_name == "ol" then
    text.new_line(state)
    table.insert(state.list_stack, { type = "ol", level = #state.list_stack + 1, counter = 0 })
  elseif tag_name == "li" then
    text.new_line(state)
    local indent = text.get_indent(state)
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
    text.new_line(state)
    state.blockquote_depth = state.blockquote_depth + 1
  elseif tag_name == "pre" then
    text.new_line(state)

    local pre_close_pattern = "</pre>"
    local pre_content_start = end_tag + 1
    local pre_close_start, pre_close_end = string.find(content:lower(), pre_close_pattern, pre_content_start, true)

    if pre_close_start then
      -- Process pre content inline without adding to style_stack
      state.in_pre = true
      local pre_content = string.sub(content, pre_content_start, pre_close_start - 1)
      text.add_text(state, entities.decode_entities(pre_content))
      state.in_pre = false
      text.new_line(state)
      -- Return new position to skip processed content (don't add to style_stack)
      return pre_close_end
    else
      -- Fallback: add to style_stack for normal processing
      state.in_pre = true
    end
  elseif tag_name == "code" and not state.in_pre then
    state.current_line = state.current_line .. "`"
  elseif tag_name == "dd" then
    text.new_line(state)
    state.in_dd = true
  elseif tag_name == "dt" or tag_name == "dl" then
    text.new_line(state)
  elseif tag_name:match("^h[1-6]$") then
    text.new_line(state)
    state.in_heading = true
    state.current_heading_level = tonumber(tag_name:match("h([1-6])"))
    state.current_heading_text = ""
    -- Try to extract ID from tag_content
    local id = tag_content:match('id=["\']([^"\']+)["\']')
    state.current_heading_id = id
    -- Try to extract title attribute (for section titles)
    local title_attr = tag_content:match('title=["\']([^"\']+)["\']')
    state.current_heading_title_attr = title_attr
  elseif tokens.block_tags[tag_name] then
    text.new_line(state)
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
            text.new_line(state)
            text.new_line(state)
            -- Mark heading as title if we're in a heading
            if state.in_heading then
              state.current_heading_is_title = true
            end
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

return M
