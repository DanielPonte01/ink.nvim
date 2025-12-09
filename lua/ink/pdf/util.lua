local M = {}

-- Generate slug from PDF path
function M.generate_slug(pdf_path)
  local name = vim.fn.fnamemodify(pdf_path, ":t:r")
  return name:gsub("[^%w%-_]", "_"):lower()
end

-- Get cache directory for PDF
function M.get_cache_dir(slug)
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  return data_dir .. "/cache/pdf/" .. slug
end

-- Get paths for PDF data
function M.get_paths(slug)
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  return {
    cache_dir = M.get_cache_dir(slug),
    xml_file = M.get_cache_dir(slug) .. "/content.xml",
    processed_file = M.get_cache_dir(slug) .. "/processed.json",
    state_file = data_dir .. "/pdf-" .. slug .. ".json",
    highlights_file = data_dir .. "/pdf-" .. slug .. "_highlights.json",
    bookmarks_file = data_dir .. "/pdf-" .. slug .. "_bookmarks.json"
  }
end

-- Check if pdftohtml is available
function M.check_pdftohtml()
  local handle = io.popen("which pdftohtml 2>/dev/null")
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and #result > 0
end

-- Extract XML from PDF using pdftohtml
function M.extract_xml(pdf_path, output_xml)
  if not M.check_pdftohtml() then
    return false, "pdftohtml not found. Please install poppler-utils."
  end

  -- Ensure output directory exists
  local output_dir = vim.fn.fnamemodify(output_xml, ":h")
  vim.fn.mkdir(output_dir, "p")

  -- Run pdftohtml -xml
  local cmd = string.format('pdftohtml -xml "%s" "%s"', pdf_path, output_xml:gsub("%.xml$", ""))
  local result = os.execute(cmd)

  if result ~= 0 and result ~= true then
    return false, "pdftohtml failed to extract XML"
  end

  return true
end

return M
