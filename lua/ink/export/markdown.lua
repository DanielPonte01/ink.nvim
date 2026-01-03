local util = require("ink.export.util")

local M = {}

-- English month names
local MONTHS = {
  "Jan", "Feb", "Mar", "Apr", "May", "Jun",
  "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
}

-- Format timestamp to readable format
-- Example: 1735824000 -> "02 Jan 2026 14:30"
local function format_date(timestamp)
  if not timestamp then
    return "Unknown date"
  end

  local date_table = os.date("*t", timestamp)
  local day = string.format("%02d", date_table.day)
  local month = MONTHS[date_table.month]
  local year = date_table.year
  local hour = string.format("%02d", date_table.hour)
  local min = string.format("%02d", date_table.min)

  return string.format("%s %s %d %s:%s", day, month, year, hour, min)
end

-- Format metadata section as table
local function format_metadata_section(metadata)
  local lines = {}
  
  -- Title with book emoji
  table.insert(lines, "# 📖 " .. metadata.title)
  table.insert(lines, "")
  
  -- Metadata table
  table.insert(lines, "| Field | Value |")
  table.insert(lines, "|-------|-------|")
  table.insert(lines, "| **Author** | " .. metadata.author .. " |")

  if metadata.language and metadata.language ~= "" then
    table.insert(lines, "| **Language** | " .. metadata.language .. " |")
  end

  if metadata.date and metadata.date ~= "" then
    table.insert(lines, "| **Published** | " .. metadata.date .. " |")
  end

  table.insert(lines, "| **Exported on** | " .. format_date(metadata.export_date) .. " |")
  table.insert(lines, "")
  
  -- Description (if exists)
  if metadata.description and metadata.description ~= "" then
    table.insert(lines, "## Description")
    table.insert(lines, util.word_wrap(metadata.description, 80))
    table.insert(lines, "")
  end
  
  return table.concat(lines, "\n")
end

-- Format table of contents (index) with clickable links
local function format_toc_section(highlights_grouped, chapter_map)
  local lines = {}
  
  table.insert(lines, "## 📑 Table of Contents")
  table.insert(lines, "")
  table.insert(lines, "- [Highlights](#highlights)")
  
  -- Get sorted chapter numbers
  local chapters = {}
  for ch, _ in pairs(highlights_grouped) do
    table.insert(chapters, ch)
  end
  table.sort(chapters)
  
  -- Add link for each chapter with highlights
  for _, ch in ipairs(chapters) do
    local chapter_title = chapter_map[ch] or ("Chapter " .. ch)
    local full_title = "Chapter " .. ch .. ": " .. chapter_title
    local slug = util.slugify(full_title)
    table.insert(lines, "  - [" .. full_title .. "](#" .. slug .. ")")
  end
  
  table.insert(lines, "")
  
  return table.concat(lines, "\n")
end

-- Format a single highlight (simplified, no headers or location)
local function format_highlight(hl, include_context)
  local lines = {}
  local text = hl.text or ""
  local color = hl.color or "yellow"
  local symbol = util.get_color_symbol(color)
  local has_note = hl.note and hl.note ~= ""
  
  -- Highlight text with color symbol
  if #text >= 80 then
    -- Long text: use quote block with symbol
    local quoted = util.word_wrap(text, 78)
    for line in quoted:gmatch("[^\n]+") do
      table.insert(lines, "> " .. symbol .. " " .. line)
      -- Only add symbol to first line
      symbol = " "
    end
    table.insert(lines, "")
  else
    -- Short text: inline with symbol
    table.insert(lines, symbol .. " " .. text)
    table.insert(lines, "")
  end
  
  -- Note (if exists)
  if has_note then
    table.insert(lines, "📝 **Note:** " .. hl.note)
    table.insert(lines, "")
  end
  
  -- Context (if requested and exists)
  if include_context then
    local context_before = hl.context_before or ""
    local context_after = hl.context_after or ""
    
    if context_before ~= "" or context_after ~= "" then
      -- Continuous context format: ...before [highlight] after...
      local ctx_line = ""
      if context_before ~= "" then
        ctx_line = "..." .. context_before .. " "
      end
      ctx_line = ctx_line .. "[" .. text .. "]"
      if context_after ~= "" then
        ctx_line = ctx_line .. " " .. context_after .. "..."
      end
      
      table.insert(lines, "**Context:** " .. util.word_wrap(ctx_line, 80))
      table.insert(lines, "")
    end
  end
  
  return table.concat(lines, "\n")
end

-- Format highlights section (grouped by chapter)
local function format_highlights_section(highlights_grouped, chapter_map, include_context)
  local lines = {}
  
  table.insert(lines, "## Highlights")
  table.insert(lines, "")
  
  -- Get sorted chapter numbers
  local chapters = {}
  for ch, _ in pairs(highlights_grouped) do
    table.insert(chapters, ch)
  end
  table.sort(chapters)
  
  -- Process each chapter
  for _, ch in ipairs(chapters) do
    local chapter_title = chapter_map[ch] or ("Chapter " .. ch)
    local highlights = highlights_grouped[ch]
    
    -- Chapter header (serves as location for all highlights in this chapter)
    table.insert(lines, "### Chapter " .. ch .. ": " .. chapter_title)
    table.insert(lines, "")
    
    -- Format each highlight in this chapter
    for idx, hl in ipairs(highlights) do
      table.insert(lines, format_highlight(hl, include_context))
      
      -- Add separator between highlights (but not after the last one)
      if idx < #highlights then
        table.insert(lines, "---")
        table.insert(lines, "")
      end
    end
    
    -- Add blank line after chapter (for spacing before next chapter)
    table.insert(lines, "")
  end
  
  return table.concat(lines, "\n")
end

-- Format bookmarks section (simplified format)
local function format_bookmarks_section(bookmarks, chapter_map)
  if not bookmarks or #bookmarks == 0 then
    return ""
  end
  
  local lines = {}
  
  table.insert(lines, "---")
  table.insert(lines, "")
  table.insert(lines, "## Bookmarks")
  table.insert(lines, "")
  
  for idx, bm in ipairs(bookmarks) do
    local chapter_title = chapter_map[bm.chapter] or ("Chapter " .. bm.chapter)
    
    -- Bookmark name with icon
    table.insert(lines, "📑 **" .. (bm.name or "Unnamed") .. "**")
    table.insert(lines, "")

    -- Location and date
    local location_line = "📍 Ch. " .. bm.chapter .. " - " .. chapter_title
    if bm.created_at then
      location_line = location_line .. " | Created: " .. format_date(bm.created_at)
    end
    table.insert(lines, location_line)
    table.insert(lines, "")
    
    -- Preview in quote block
    if bm.text_preview and bm.text_preview ~= "" then
      local preview = util.word_wrap(bm.text_preview, 78)
      for line in preview:gmatch("[^\n]+") do
        table.insert(lines, "> " .. line)
      end
      table.insert(lines, "")
    end
    
    -- Add separator between bookmarks (but not after the last one)
    if idx < #bookmarks then
      table.insert(lines, "---")
      table.insert(lines, "")
    end
  end
  
  return table.concat(lines, "\n")
end

-- Main formatting function
function M.format(book_data, options)
  options = options or {}
  
  local sections = {}
  
  -- 1. Metadata (always)
  table.insert(sections, format_metadata_section(book_data.metadata))
  table.insert(sections, "---")
  table.insert(sections, "")
  
  -- 2. Table of Contents / Index (only if highlights exist)
  if book_data.highlights and next(book_data.highlights) ~= nil then
    table.insert(sections, format_toc_section(book_data.highlights, book_data.chapter_map))
    table.insert(sections, "---")
    table.insert(sections, "")
  end
  
  -- 3. Highlights (default, even if empty)
  if book_data.highlights and next(book_data.highlights) ~= nil then
    table.insert(sections, format_highlights_section(
      book_data.highlights,
      book_data.chapter_map,
      options.include_context
    ))
  else
    table.insert(sections, "## Highlights")
    table.insert(sections, "")
    table.insert(sections, "*No highlights found.*")
    table.insert(sections, "")
  end
  
  -- 4. Bookmarks (optional)
  if options.include_bookmarks and book_data.bookmarks and #book_data.bookmarks > 0 then
    table.insert(sections, format_bookmarks_section(book_data.bookmarks, book_data.chapter_map))
  end
  
  return table.concat(sections, "\n")
end

return M
