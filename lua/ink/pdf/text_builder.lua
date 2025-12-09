local M = {}

-- Build readable text from structured paragraphs
function M.build_text(paragraphs)
  local lines = {}
  local metadata = {
    headings = {},
    paragraphs = {},
    page_breaks = {}
  }

  for _, para in ipairs(paragraphs) do
    local start_line = #lines + 1
    local text = M.format_paragraph(para, lines)

    -- Track metadata for navigation and structure
    if para.type ~= "p" then
      table.insert(metadata.headings, {
        level = para.type,
        text = text,
        line = start_line,
        page = para.page
      })
    end

    table.insert(metadata.paragraphs, {
      type = para.type,
      start_line = start_line,
      end_line = #lines,
      page = para.page
    })

    -- Mark page breaks
    if #paragraphs > 0 then
      local next_idx = _ + 1
      if paragraphs[next_idx] and paragraphs[next_idx].page ~= para.page then
        table.insert(metadata.page_breaks, #lines)
      end
    end
  end

  return {
    lines = lines,
    metadata = metadata
  }
end

-- Format a single paragraph and append to lines
function M.format_paragraph(para, lines)
  local typography = require("ink.pdf.typography")
  local text = typography.build_paragraph_text(para)

  if not text or #text == 0 then
    return ""
  end

  -- Add heading prefix based on level
  if para.type == "h1" then
    table.insert(lines, "")
    table.insert(lines, text)
    table.insert(lines, "")
  elseif para.type == "h2" then
    table.insert(lines, "")
    table.insert(lines, text)
    table.insert(lines, "")
  elseif para.type == "h3" then
    table.insert(lines, "")
    table.insert(lines, text)
    table.insert(lines, "")
  elseif para.type == "h4" then
    table.insert(lines, "")
    table.insert(lines, text)
    table.insert(lines, "")
  else
    -- Regular paragraph
    table.insert(lines, text)
    table.insert(lines, "")
  end

  return text
end

-- Generate table of contents from headings
function M.generate_toc(metadata)
  local toc = {}

  for _, heading in ipairs(metadata.headings) do
    local level = tonumber(heading.level:sub(2)) or 1
    table.insert(toc, {
      label = heading.text,
      level = level,
      line = heading.line,
      page = heading.page
    })
  end

  return toc
end

return M
