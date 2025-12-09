local utils = require("ink.html.utils")

local M = {}

-- Box-drawing characters for table borders
local BOX = {
  TL = "┌",      -- Top-left corner
  TR = "┐",      -- Top-right corner
  BL = "└",      -- Bottom-left corner
  BR = "┘",      -- Bottom-right corner
  H = "─",       -- Horizontal line
  V = "│",       -- Vertical line
  TT = "┬",      -- Top T-joint
  BT = "┴",      -- Bottom T-joint
  LT = "├",      -- Left T-joint
  RT = "┤",      -- Right T-joint
  CROSS = "┼"    -- Cross
}

-- Create new table state
function M.new_table_state()
  return {
    in_table = false,
    in_thead = false,
    in_tbody = false,
    in_row = false,
    current_row = {},
    rows = {},
    headers = {},
    col_widths = {},
    current_cell = ""
  }
end

-- Calculate optimal column widths
function M.calculate_column_widths(headers, rows, max_width, indent_width)
  local num_cols = math.max(#headers, 0)
  for _, row in ipairs(rows) do
    num_cols = math.max(num_cols, #row)
  end

  if num_cols == 0 then return {} end

  -- Calculate available width: max_width - indent - borders - padding
  -- Borders: 2 (left/right) + (num_cols - 1) separators
  -- Padding: 2 spaces per column (1 on each side)
  local borders_width = 2 + (num_cols - 1)
  local padding_width = num_cols * 2
  local available = max_width - indent_width - borders_width - padding_width

  if available < num_cols * 10 then
    -- Not enough space, use minimum width
    available = num_cols * 10
  end

  -- Calculate natural widths
  local natural_widths = {}
  for i = 1, num_cols do
    natural_widths[i] = 0

    -- Check header width
    if headers[i] then
      natural_widths[i] = math.max(natural_widths[i], utils.display_width(headers[i]))
    end

    -- Check all rows
    for _, row in ipairs(rows) do
      if row[i] then
        natural_widths[i] = math.max(natural_widths[i], utils.display_width(row[i]))
      end
    end

    -- Minimum 10 characters per column for better wrapping
    natural_widths[i] = math.max(natural_widths[i], 10)
  end

  -- Calculate total natural width
  local total_natural = 0
  for _, w in ipairs(natural_widths) do
    total_natural = total_natural + w
  end

  -- Distribute available width proportionally
  local col_widths = {}
  if total_natural <= available then
    -- Fits naturally
    col_widths = natural_widths
  else
    -- Need to shrink proportionally
    for i, w in ipairs(natural_widths) do
      col_widths[i] = math.floor((w / total_natural) * available)
      col_widths[i] = math.max(col_widths[i], 10) -- Minimum 10
    end
  end

  return col_widths
end

-- Wrap text to fit in column width
function M.wrap_cell_text(text, width)
  -- Remove any newlines from text
  text = text:gsub("\n", " "):gsub("\r", " ")

  if utils.display_width(text) <= width then
    return {text}
  end

  local lines = {}
  local words = {}
  for word in text:gmatch("%S+") do
    table.insert(words, word)
  end

  local current = ""
  for _, word in ipairs(words) do
    local test = current == "" and word or (current .. " " .. word)
    if utils.display_width(test) <= width then
      current = test
    else
      if #current > 0 then
        table.insert(lines, current)
      end
      current = word
    end
  end

  if #current > 0 then
    table.insert(lines, current)
  end

  return #lines > 0 and lines or {""}
end

-- Pad text to column width
function M.pad_cell(text, width)
  local text_width = utils.display_width(text)
  if text_width >= width then
    return text
  end
  return text .. string.rep(" ", width - text_width)
end

-- Render a table row with wrapped cells
function M.render_row(cells, col_widths, indent)
  local wrapped_cells = {}
  local max_lines = 1

  -- Wrap all cells and find max line count
  for i, cell in ipairs(cells) do
    local width = col_widths[i] or 10
    wrapped_cells[i] = M.wrap_cell_text(cell, width)
    max_lines = math.max(max_lines, #wrapped_cells[i])
  end

  -- Fill missing columns
  for i = #cells + 1, #col_widths do
    wrapped_cells[i] = {""}
  end

  -- Render each line
  local lines = {}
  for line_idx = 1, max_lines do
    local result = indent .. BOX.V

    for i, width in ipairs(col_widths) do
      local cell_line = wrapped_cells[i][line_idx] or ""
      result = result .. " " .. M.pad_cell(cell_line, width) .. " " .. BOX.V
    end

    table.insert(lines, result)
  end

  return lines
end

-- Render horizontal border
function M.render_border(col_widths, indent, left, middle, right, fill)
  local result = indent .. left

  for i, width in ipairs(col_widths) do
    -- Add space + fill chars + space to match cell padding
    result = result .. " " .. string.rep(fill, width) .. " "
    if i < #col_widths then
      result = result .. middle
    end
  end

  result = result .. right
  return result
end

-- Render complete table
function M.render_table(table_state, max_width, indent)
  indent = indent or ""
  local indent_width = utils.display_width(indent)

  -- Calculate column widths
  local col_widths = M.calculate_column_widths(
    table_state.headers,
    table_state.rows,
    max_width,
    indent_width
  )

  if #col_widths == 0 then
    return {}
  end

  local lines = {}

  -- Top border
  table.insert(lines, M.render_border(col_widths, indent, BOX.TL, BOX.TT, BOX.TR, BOX.H))

  -- Headers (if any)
  if #table_state.headers > 0 then
    local header_lines = M.render_row(table_state.headers, col_widths, indent)
    for _, line in ipairs(header_lines) do
      table.insert(lines, line)
    end

    -- Header separator
    table.insert(lines, M.render_border(col_widths, indent, BOX.LT, BOX.CROSS, BOX.RT, BOX.H))
  end

  -- Data rows
  for row_idx, row in ipairs(table_state.rows) do
    local row_lines = M.render_row(row, col_widths, indent)
    for _, line in ipairs(row_lines) do
      table.insert(lines, line)
    end

    -- Row separator (except last row)
    if row_idx < #table_state.rows then
      table.insert(lines, M.render_border(col_widths, indent, BOX.LT, BOX.CROSS, BOX.RT, BOX.H))
    end
  end

  -- Bottom border
  table.insert(lines, M.render_border(col_widths, indent, BOX.BL, BOX.BT, BOX.BR, BOX.H))

  return lines
end

return M
