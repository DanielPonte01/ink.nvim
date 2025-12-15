-- lua/ink/html/text.lua
-- Responsabilidade: Renderização de texto com word-wrapping e estilos inline

local tokens = require("ink.html.tokens")
local entities = require("ink.html.entities")
local utils = require("ink.html.utils")

local M = {}

function M.get_indent(state)
  local indent = ""
  local typography = state.typography or { indent_size = 4, list_indent = 2 }

  if state.blockquote_depth > 0 then
    for i = 1, state.blockquote_depth do
      indent = indent .. "│ "
    end
    indent = indent .. string.rep(" ", typography.indent_size - 2)
  end
  if #state.list_stack > 0 then
    indent = indent .. string.rep(" ", typography.list_indent * #state.list_stack)
  end
  if state.in_dd then
    indent = indent .. string.rep(" ", typography.indent_size)
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

-- Add paragraph break with spacing based on typography settings
function M.paragraph_break(state)
  M.new_line(state)
  local typography = state.typography or { paragraph_spacing = 1 }
  -- Add extra blank lines for paragraph spacing (spacing - 1 because new_line already added one)
  for i = 1, typography.paragraph_spacing - 1 do
    table.insert(state.lines, "")
  end
end

function M.add_text(state, text)
  -- Track heading text
  if state.in_heading and state.current_heading_level then
    state.current_heading_text = state.current_heading_text .. text
  end

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

return M
