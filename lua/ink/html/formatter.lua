-- lua/ink/html/formatter.lua
-- Responsabilidade: Dispatcher central e orquestração de formatação HTML

local tokens = require("ink.html.tokens")
local entities = require("ink.html.entities")
local utils = require("ink.html.utils")
local table_module = require("ink.html.table")
local text = require("ink.html.text")
local blocks = require("ink.html.blocks")
local justification = require("ink.html.justification")

local M = {}

-- Re-export functions from text module for backwards compatibility
M.get_indent = text.get_indent
M.new_line = text.new_line
M.add_text = text.add_text

-- Re-export function from justification module
M.apply_justification = justification.apply_justification

-- Classify image type and return symbol if bullet
local function classify_image(src)
  local filename = src:match("([^/]+)$")
  if not filename then return "figure", nil end

  filename = filename:lower()

  -- Bullet patterns
  if filename:match("^squ") or
     filename:match("bullet") or
     filename:match("^icon") or
     filename:match("^arrow") then
    -- Return bullet type and symbol
    if filename:match("^squ") then return "bullet", "■" end
    if filename:match("arrow") then return "bullet", "→" end
    return "bullet", "▪"
  end

  return "figure", nil
end

function M.process_tag(state, tag_name, tag_content, is_closing, start_tag, end_tag, content)
  -- Skip tags inside <head> except head and title
  if state.in_head and tag_name ~= "head" and tag_name ~= "title" then
    return
  end

  if tag_name == "img" then
    local src = tag_content:match('src=["\']([^"\']+)["\']')
    if src then
      local img_type, symbol = classify_image(src)

      if img_type == "bullet" and not state.table_state.in_table then
        -- Inline bullet symbol - don't break line (except inside tables)
        state.current_line = state.current_line .. symbol .. " "
        -- Store as bullet type (no render)
        table.insert(state.images, {
          line = #state.lines + 1,
          col_start = 0,
          col_end = 0,
          src = src,
          type = "bullet",
          symbol = symbol
        })
      elseif img_type == "bullet" and state.table_state.in_table then
        -- Inside table: ignore bullet images completely
        -- Don't render anything, table will handle content
      else
        -- Figure image - add placeholder
        text.new_line(state)
        local indent = text.get_indent(state)
        local img_text = indent .. "[image] (press Enter to open)"
        state.current_line = img_text
        -- Store as figure type (for render)
        table.insert(state.images, {
          line = #state.lines + 1,
          col_start = 0,
          col_end = #img_text,
          src = src,
          type = "figure"
        })
        table.insert(state.highlights, { #state.lines + 1, 0, #img_text, "Special" })
        text.new_line(state)
      end
    end
  elseif tag_name == "hr" then
    text.new_line(state)
    local indent = text.get_indent(state)
    local indent_width = utils.display_width(indent)
    local rule = indent .. string.rep("─", math.min(60, state.max_width - indent_width))
    state.current_line = rule
    table.insert(state.highlights, { #state.lines + 1, 0, #state.current_line, "InkHorizontalRule" })
    text.new_line(state)
  elseif is_closing then
    M.handle_closing_tag(state, tag_name)
  else
    local result = M.handle_opening_tag(state, tag_name, tag_content, start_tag, end_tag, content)
    if result then
      return result
    end
  end
end

-- Handle table-related tags
function M.handle_table_tag(state, tag_name, is_closing)
  local ts = state.table_state

  if tag_name == "table" then
    if is_closing then
      -- Render the complete table
      if ts.in_table then
        text.new_line(state)
        local indent = text.get_indent(state)
        local table_lines = table_module.render_table(ts, state.max_width, indent)

        for _, line in ipairs(table_lines) do
          table.insert(state.lines, line)
          -- Mark table lines as no-justify
          state.no_justify[#state.lines] = true
        end

        text.new_line(state)
        -- Reset table state
        state.table_state = table_module.new_table_state()
      end
    else
      -- Start new table
      text.new_line(state)
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

  -- Delegate to blocks module for block-level tags
  blocks.handle_closing_tag(state, tag_name)
end

function M.handle_opening_tag(state, tag_name, tag_content, start_tag, end_tag, content)
  -- Handle table tags
  if tag_name == "table" or tag_name == "thead" or tag_name == "tbody" or
     tag_name == "tr" or tag_name == "th" or tag_name == "td" then
    M.handle_table_tag(state, tag_name, false)
    return
  end

  -- Delegate to blocks module for block-level tags
  return blocks.handle_opening_tag(state, tag_name, tag_content, start_tag, end_tag, content)
end

return M
