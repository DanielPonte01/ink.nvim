local M = {}

-- Apply word wrapping and formatting to text
function M.format_lines(lines, metadata, max_width)
  local formatted = {}
  local line_map = {}  -- Maps formatted line index to original line index
  local highlights = {}

  for i, line in ipairs(lines) do
    local para_meta = M.find_paragraph_at_line(metadata.paragraphs, i)

    if para_meta and para_meta.type ~= "p" then
      -- Heading - no wrapping
      local wrapped = M.wrap_text(line, max_width, false)
      for _, wline in ipairs(wrapped) do
        table.insert(formatted, wline)
        table.insert(line_map, i)
        table.insert(highlights, {
          type = para_meta.type,
          line = #formatted
        })
      end
    else
      -- Regular paragraph - apply wrapping
      local wrapped = M.wrap_text(line, max_width, true)
      for _, wline in ipairs(wrapped) do
        table.insert(formatted, wline)
        table.insert(line_map, i)
      end
    end
  end

  return {
    lines = formatted,
    line_map = line_map,
    highlights = highlights,
    metadata = metadata
  }
end

-- Find paragraph metadata at specific line
function M.find_paragraph_at_line(paragraphs, line)
  for _, para in ipairs(paragraphs) do
    if line >= para.start_line and line <= para.end_line then
      return para
    end
  end
  return nil
end

-- Wrap text to fit within max_width
function M.wrap_text(text, max_width, do_wrap)
  if #text == 0 then
    return {""}
  end

  if not do_wrap or M.display_width(text) <= max_width then
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
    if M.display_width(test) <= max_width then
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

-- Calculate display width (handles UTF-8)
function M.display_width(text)
  local width = 0
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if vim.fn.strwidth(char) > 0 then
      width = width + vim.fn.strwidth(char)
    end
  end
  return width
end

-- Apply justification if enabled
function M.apply_justification(formatted, justify_enabled)
  if not justify_enabled then
    return formatted
  end

  local lines = formatted.lines
  local max_width = 0

  -- Find max width
  for _, line in ipairs(lines) do
    local width = M.display_width(line)
    if width > max_width then
      max_width = width
    end
  end

  -- Justify lines
  local justified = {}
  for i, line in ipairs(lines) do
    local highlight = M.find_highlight_at_line(formatted.highlights, i)

    -- Don't justify headings
    if highlight and highlight.type ~= "p" then
      table.insert(justified, line)
    else
      table.insert(justified, M.justify_line(line, max_width))
    end
  end

  formatted.lines = justified
  return formatted
end

-- Find highlight at specific line
function M.find_highlight_at_line(highlights, line)
  for _, hl in ipairs(highlights) do
    if hl.line == line then
      return hl
    end
  end
  return nil
end

-- Justify a single line by distributing spaces
function M.justify_line(line, max_width)
  local width = M.display_width(line)

  -- Only justify if line is 90%+ of max_width
  if width < max_width * 0.9 then
    return line
  end

  local words = {}
  for word in line:gmatch("%S+") do
    table.insert(words, word)
  end

  if #words <= 1 then
    return line
  end

  local gaps = #words - 1
  local extra_spaces = max_width - width
  local spaces_per_gap = math.floor(extra_spaces / gaps)
  local remainder = extra_spaces % gaps

  local result = {}
  for i, word in ipairs(words) do
    table.insert(result, word)
    if i < #words then
      local spaces = 1 + spaces_per_gap
      if i <= remainder then
        spaces = spaces + 1
      end
      table.insert(result, string.rep(" ", spaces))
    end
  end

  return table.concat(result)
end

return M
