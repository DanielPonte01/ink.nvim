local entities = require("ink.html.entities")
local tokens = require("ink.html.tokens")
local formatter = require("ink.html.formatter")
local utils = require("ink.html.utils")
local table_module = require("ink.html.table")

local M = {}

function M.parse(content, max_width, class_styles, justify_text, typography)
  local lines = {}
  local highlights = {}
  local links = {}
  local images = {}
  local anchors = {}
  local no_justify = {}
  local centered_lines = {}
  local headings = {}

  local current_line = ""
  local style_stack = {}
  local list_stack = {}
  local blockquote_depth = 0
  local in_pre = false
  local in_dd = false
  local line_start_indent = 0
  local in_heading = false
  local in_title = false
  local in_head = false
  local current_heading_level = nil
  local current_heading_text = ""
  local current_heading_id = nil
  local current_heading_title_attr = nil
  local current_heading_is_title = false
  local table_state = table_module.new_table_state()

  -- Default typography settings if not provided
  typography = typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  local state = {
    lines = lines,
    highlights = highlights,
    links = links,
    images = images,
    anchors = anchors,
    no_justify = no_justify,
    centered_lines = centered_lines,
    headings = headings,
    current_line = current_line,
    style_stack = style_stack,
    list_stack = list_stack,
    blockquote_depth = blockquote_depth,
    in_pre = in_pre,
    in_dd = in_dd,
    line_start_indent = line_start_indent,
    in_heading = in_heading,
    in_title = in_title,
    in_head = in_head,
    current_heading_level = current_heading_level,
    current_heading_text = current_heading_text,
    current_heading_id = current_heading_id,
    current_heading_title_attr = current_heading_title_attr,
    current_heading_is_title = current_heading_is_title,
    max_width = max_width,
    class_styles = class_styles,
    table_state = table_state,
    typography = typography
  }

  -- Main parsing loop
  local pos = 1
  while pos <= #content do
    local start_tag, end_tag = string.find(content, "<[^>]+>", pos)

    if not start_tag then
      if not state.in_head or state.in_title then
        local text = string.sub(content, pos)
        formatter.add_text(state, entities.decode_entities(text))
      end
      break
    end

    if start_tag > pos and (not state.in_head or state.in_title) then
      local text = string.sub(content, pos, start_tag - 1)
      formatter.add_text(state, entities.decode_entities(text))
    end

    local tag_content = string.sub(content, start_tag + 1, end_tag - 1)
    local is_closing = string.sub(tag_content, 1, 1) == "/"
    local tag_name = tag_content:match("^/?([%w]+)")

    if tag_name then
      tag_name = tag_name:lower()

      local id = tag_content:match('id=["\']([^"\']+)["\']')
      if id then
        anchors[id] = #lines + 1
      end

      local new_pos = formatter.process_tag(state, tag_name, tag_content, is_closing, start_tag, end_tag, content)
      if new_pos then
        pos = new_pos + 1
      else
        pos = end_tag + 1
      end
    else
      pos = end_tag + 1
    end
  end

  -- Flush last line
  if #state.current_line > 0 then
    table.insert(lines, state.current_line)
  end

  -- Merge highlights
  highlights = utils.merge_highlights(highlights)

  -- Apply justification if enabled
  local justify_map = {}
  if justify_text then
    justify_map = formatter.apply_justification(lines, highlights, links, images, no_justify, max_width)
  end

  return {
    lines = lines,
    highlights = highlights,
    links = links,
    images = images,
    anchors = anchors,
    justify_map = justify_map,
    centered_lines = centered_lines,
    headings = headings
  }
end

return M