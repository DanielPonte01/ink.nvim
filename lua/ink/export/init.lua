local data = require("ink.export.data")
local markdown = require("ink.export.markdown")
local json = require("ink.export.json")
local glossary_md = require("ink.export.glossary_md")
local html_graph = require("ink.export.html_graph")
local util = require("ink.export.util")
local fs = require("ink.fs")

local M = {}

-- Validate export path for safety
local function validate_export_path(path)
  -- Resolve and normalize path
  local resolved = vim.fn.resolve(vim.fn.fnamemodify(path, ":p"))

  -- List of unsafe system directories
  local unsafe_dirs = {
    "/etc", "/bin", "/sbin", "/usr/bin", "/usr/sbin",
    "/boot", "/dev", "/proc", "/sys", "/var/log",
    "/root", "/lib", "/lib64"
  }

  -- Check if path starts with any unsafe directory
  for _, unsafe_dir in ipairs(unsafe_dirs) do
    if resolved:match("^" .. unsafe_dir .. "/") or resolved == unsafe_dir then
      return false, "Cannot export to system directory: " .. unsafe_dir
    end
  end

  -- Warn if path is outside home directory (but allow it)
  local home_dir = vim.fn.expand("~")
  if not resolved:match("^" .. vim.pesc(home_dir)) then
    vim.notify(
      "Warning: Exporting to location outside home directory",
      vim.log.levels.WARN
    )
  end

  return true, nil
end

-- Export glossary (MD + HTML graph)
-- @param slug: book slug identifier
-- @param book_title: title of the book
-- @param base_output_path: base path for exports (without extension)
-- @return boolean: success status
local function export_glossary(slug, book_title, base_output_path)
  local glossary = require("ink.glossary")
  local entries = glossary.get_all(slug)

  if not entries or #entries == 0 then
    vim.notify("No glossary entries to export", vim.log.levels.INFO)
    return true  -- Not an error, just nothing to export
  end

  -- Validate base export path
  local valid, err = validate_export_path(base_output_path)
  if not valid then
    vim.notify(err, vim.log.levels.ERROR)
    return false
  end

  -- Generate filenames
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local sanitized_slug = util.sanitize_filename(slug)

  local glossary_md_path = base_output_path .. "/" .. sanitized_slug .. "-glossary-" .. timestamp .. ".md"
  local glossary_html_path = base_output_path .. "/" .. sanitized_slug .. "-glossary-graph-" .. timestamp .. ".html"

  -- Ensure export directory exists
  local export_dir = vim.fn.fnamemodify(base_output_path, ":p")
  fs.ensure_dir(export_dir)

  -- Export glossary MD
  local md_content = glossary_md.format(entries, book_title)
  local md_file, md_err = io.open(glossary_md_path, "w")
  if not md_file then
    vim.notify("Failed to write glossary MD: " .. (md_err or "unknown error"), vim.log.levels.ERROR)
    return false
  end
  md_file:write(md_content)
  md_file:close()

  -- Export HTML graph
  local html_content = html_graph.generate(entries, book_title)
  local html_file, html_err = io.open(glossary_html_path, "w")
  if not html_file then
    vim.notify("Failed to write glossary HTML: " .. (html_err or "unknown error"), vim.log.levels.ERROR)
    return false
  end
  html_file:write(html_content)
  html_file:close()

  vim.notify("✓ Glossary exported:\n  " .. glossary_md_path .. "\n  " .. glossary_html_path, vim.log.levels.INFO)
  return true
end

-- Export book to file
-- @param slug: book slug identifier
-- @param format: "markdown" or "json"
-- @param options: { include_bookmarks, include_context }
-- @param output_path: full path to output file
-- @return boolean: success status
function M.export_book(slug, format, options, output_path)
  -- Validate inputs
  if not slug or slug == "" then
    vim.notify("Invalid book slug", vim.log.levels.ERROR)
    return false
  end

  if not output_path or output_path == "" then
    vim.notify("Invalid output path", vim.log.levels.ERROR)
    return false
  end

  -- Validate export path for safety
  local valid, err = validate_export_path(output_path)
  if not valid then
    vim.notify(err, vim.log.levels.ERROR)
    return false
  end

  format = format or "markdown"
  options = options or {}

  -- Collect data
  local book_data = data.collect_book_data(slug, options)
  if not book_data then
    -- Error already notified by collect_book_data
    return false
  end

  -- Format content
  local content
  if format == "markdown" then
    content = markdown.format(book_data, options)
  elseif format == "json" then
    content = json.format(book_data, options)
  else
    vim.notify("Unknown export format: " .. format, vim.log.levels.ERROR)
    return false
  end

  -- Ensure export directory exists
  local export_dir = vim.fn.fnamemodify(output_path, ":h")
  fs.ensure_dir(export_dir)

  -- Write file
  local file, err = io.open(output_path, "w")
  if not file then
    vim.notify("Failed to write export file: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return false
  end

  file:write(content)
  file:close()

  -- Export glossary if requested
  if options.include_glossary then
    local export_dir = vim.fn.fnamemodify(output_path, ":h")
    local book_title = book_data.metadata.title or "Unknown"
    export_glossary(slug, book_title, export_dir)
  end

  return true
end

-- Re-export data collection (for advanced usage)
M.collect_book_data = data.collect_book_data

-- Re-export formatters (for advanced usage)
M.format_markdown = markdown.format
M.format_json = json.format

-- Re-export utilities
M.util = util

return M
