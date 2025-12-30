local context = require("ink.ui.context")
local export = require("ink.export")
local util = require("ink.export.util")

local M = {}

-- Generate default export filename
local function generate_filename(slug, format)
  local timestamp = os.date("%Y%m%d-%H%M%S")
  local extension = format == "markdown" and "md" or "json"
  local sanitized_slug = util.sanitize_filename(slug)
  return string.format("%s-%s.%s", sanitized_slug, timestamp, extension)
end

-- Get default export directory from config
local function get_default_export_dir()
  local config = require("ink").config
  if config and config.export_defaults and config.export_defaults.export_dir then
    return vim.fn.expand(config.export_defaults.export_dir)
  end
  return vim.fn.expand("~/Documents")
end

-- Parse export command: <fmt> <flags> <path>
-- Examples: "md -bc ~/Documents", "json", "md -b", "md -g"
local function parse_export_command(input, slug)
  local format = "markdown"  -- default
  local options = {
    include_bookmarks = false,
    include_context = false,
    include_glossary = false
  }
  local output_path = nil

  if not input or input == "" then
    input = "md"
  end

  -- Split by spaces
  local parts = {}
  for part in input:gmatch("%S+") do
    table.insert(parts, part)
  end

  -- Parse format (first part)
  if #parts >= 1 then
    local fmt = parts[1]:lower()
    if fmt == "md" or fmt == "markdown" then
      format = "markdown"
    elseif fmt == "json" then
      format = "json"
    end
  end

  -- Parse flags and path (remaining parts)
  for i = 2, #parts do
    local part = parts[i]
    if part:match("^%-") then
      -- It's a flag
      if part:find("b") then
        options.include_bookmarks = true
      end
      if part:find("c") then
        options.include_context = true
      end
      if part:find("g") then
        options.include_glossary = true
      end
    else
      -- It's a path
      output_path = part
      break
    end
  end

  -- Build output path
  if not output_path then
    local export_dir = get_default_export_dir()
    local filename = generate_filename(slug, format)
    output_path = export_dir .. "/" .. filename
  else
    output_path = vim.fn.expand(output_path)
    -- If path is a directory, append filename
    if vim.fn.isdirectory(output_path) == 1 then
      local filename = generate_filename(slug, format)
      output_path = output_path .. "/" .. filename
    end
  end

  return format, options, output_path
end

-- Main entry point: show export dialog
function M.show_export_dialog()
  -- Verify book is open
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("Please open a book first to export", vim.log.levels.ERROR)
    return
  end

  local slug = ctx.data.slug
  local title = ctx.data.title or "Unknown"

  -- Single prompt for everything
  vim.ui.input({
    prompt = "Export [md|json] [-bcg] [path]: ",
    default = "md"
  }, function(input)
    if not input then
      return  -- User cancelled
    end

    -- Parse command
    local format, options, output_path = parse_export_command(input, slug)

    -- Execute export
    local success = export.export_book(slug, format, options, output_path)

    if success then
      vim.notify("✓ Exported: " .. output_path, vim.log.levels.INFO)
    end
  end)
end

return M
