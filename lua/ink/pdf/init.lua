local M = {}

local util = require("ink.pdf.util")
local parser = require("ink.pdf.parser")
local typography = require("ink.pdf.typography")
local text_builder = require("ink.pdf.text_builder")
local formatter = require("ink.pdf.formatter")
local fs = require("ink.fs")

-- Main function to open and process PDF
function M.open(pdf_path, max_width, justify_text)
  max_width = max_width or 120
  justify_text = justify_text or false

  -- Convert to absolute path
  pdf_path = vim.fn.fnamemodify(pdf_path, ":p")

  if not fs.exists(pdf_path) then
    return nil, "PDF file not found: " .. pdf_path
  end

  -- Generate slug and paths
  local slug = util.generate_slug(pdf_path)
  local paths = util.get_paths(slug)

  -- Check if already processed
  local processed = M.load_processed(paths.processed_file)
  if processed then
    -- Re-format with current settings
    local formatted = formatter.format_lines(
      processed.text.lines,
      processed.text.metadata,
      max_width
    )

    if justify_text then
      formatted = formatter.apply_justification(formatted, true)
    end

    return {
      slug = slug,
      path = pdf_path,
      title = processed.title or vim.fn.fnamemodify(pdf_path, ":t:r"),
      formatted = formatted,
      toc = processed.toc,
      total_pages = processed.total_pages,
      paths = paths
    }
  end

  -- Extract XML if needed
  if not fs.exists(paths.xml_file) then
    local success, err = util.extract_xml(pdf_path, paths.xml_file)
    if not success then
      return nil, err
    end
  end

  -- Parse XML
  local xml_content = fs.read_file(paths.xml_file)
  if not xml_content then
    return nil, "Failed to read XML file"
  end

  local parsed = parser.parse_xml(xml_content)
  if not parsed or not parsed.pages or #parsed.pages == 0 then
    return nil, "Failed to parse PDF XML"
  end

  -- Analyze typography
  local all_texts = typography.analyze_structure(parsed.pages, parsed.fonts)
  local sorted = parser.sort_reading_order(all_texts)
  local paragraphs = typography.group_paragraphs(sorted)

  -- Build text
  local text = text_builder.build_text(paragraphs)

  -- Generate TOC
  local toc = text_builder.generate_toc(text.metadata)

  -- Save processed data
  M.save_processed(paths.processed_file, {
    title = vim.fn.fnamemodify(pdf_path, ":t:r"),
    total_pages = #parsed.pages,
    text = text,
    toc = toc
  })

  -- Format for display
  local formatted = formatter.format_lines(text.lines, text.metadata, max_width)

  if justify_text then
    formatted = formatter.apply_justification(formatted, true)
  end

  return {
    slug = slug,
    path = pdf_path,
    title = vim.fn.fnamemodify(pdf_path, ":t:r"),
    formatted = formatted,
    toc = toc,
    total_pages = #parsed.pages,
    paths = paths
  }
end

-- Save processed PDF data
function M.save_processed(file_path, data)
  local dir = vim.fn.fnamemodify(file_path, ":h")
  vim.fn.mkdir(dir, "p")

  local json = vim.json.encode(data)
  local file = io.open(file_path, "w")
  if file then
    file:write(json)
    file:close()
  end
end

-- Load processed PDF data
function M.load_processed(file_path)
  if not fs.exists(file_path) then
    return nil
  end

  local content = fs.read_file(file_path)
  if not content then
    return nil
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok then
    return nil
  end

  return data
end

-- Reprocess PDF with new settings (width/justify changed)
function M.reformat(pdf_data, max_width, justify_text)
  local paths = pdf_data.paths
  local processed = M.load_processed(paths.processed_file)

  if not processed then
    return nil, "No processed data found"
  end

  local formatted = formatter.format_lines(
    processed.text.lines,
    processed.text.metadata,
    max_width
  )

  if justify_text then
    formatted = formatter.apply_justification(formatted, true)
  end

  pdf_data.formatted = formatted
  return pdf_data
end

return M
