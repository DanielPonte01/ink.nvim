local M = {}

-- Analyze typography to detect document structure
function M.analyze_structure(pages, fonts)
  local all_texts = {}

  -- Collect all texts with page info
  for _, page in ipairs(pages) do
    for _, text in ipairs(page.texts) do
      local t = vim.deepcopy(text)
      t.page = page.number
      t.font_info = fonts[text.font] or {}
      table.insert(all_texts, t)
    end
  end

  -- Calculate font size statistics
  local font_sizes = {}
  for _, text in ipairs(all_texts) do
    local size = text.font_info.size or 12
    font_sizes[size] = (font_sizes[size] or 0) + 1
  end

  -- Find most common (body) font size
  local body_size = M.find_body_font_size(font_sizes)

  -- Classify each text element
  for _, text in ipairs(all_texts) do
    text.type = M.classify_text(text, body_size)
  end

  return all_texts
end

-- Find the most common font size (likely body text)
function M.find_body_font_size(font_sizes)
  local max_count = 0
  local body_size = 12

  for size, count in pairs(font_sizes) do
    if count > max_count then
      max_count = count
      body_size = size
    end
  end

  return body_size
end

-- Classify text element based on typography
function M.classify_text(text, body_size)
  local size = text.font_info.size or 12
  local size_diff = size - body_size

  -- Headings are typically larger than body text
  if size_diff >= 6 then
    return "h1"
  elseif size_diff >= 4 then
    return "h2"
  elseif size_diff >= 2 then
    return "h3"
  elseif size_diff >= 1 then
    return "h4"
  else
    return "p"
  end
end

-- Group texts into paragraphs based on vertical spacing
function M.group_paragraphs(texts)
  if #texts == 0 then return {} end

  local paragraphs = {}
  local current_para = {
    type = texts[1].type,
    lines = {},
    page = texts[1].page
  }

  for i, text in ipairs(texts) do
    local prev = texts[i - 1]

    -- Start new paragraph if:
    -- 1. Type changed (heading vs paragraph)
    -- 2. Large vertical gap (> 1.5x line height)
    -- 3. Page changed
    local start_new = false

    if prev then
      local line_height = prev.height or 12
      local vertical_gap = text.top - (prev.top + prev.height)

      if text.type ~= current_para.type then
        start_new = true
      elseif vertical_gap > line_height * 1.5 then
        start_new = true
      elseif text.page ~= current_para.page then
        start_new = true
      end
    end

    if start_new then
      table.insert(paragraphs, current_para)
      current_para = {
        type = text.type,
        lines = {},
        page = text.page
      }
    end

    table.insert(current_para.lines, text)
  end

  -- Add last paragraph
  if #current_para.lines > 0 then
    table.insert(paragraphs, current_para)
  end

  return paragraphs
end

-- Build text content from paragraph lines
function M.build_paragraph_text(para)
  local words = {}

  for _, line in ipairs(para.lines) do
    if line.text and #line.text > 0 then
      table.insert(words, line.text)
    end
  end

  return table.concat(words, " ")
end

return M
