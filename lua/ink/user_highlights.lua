local fs = require("ink.fs")
local data = require("ink.data")
local migrate = require("ink.data.migrate")

local M = {}

local function get_highlights_path(slug)
  migrate.migrate_book(slug)
  return data.get_book_dir(slug) .. "/highlights.json"
end

function M.save(slug, highlights)
  local path = get_highlights_path(slug)
  local json = data.json_encode({ highlights = highlights })

  local file = io.open(path, "w")
  if file then
    file:write(json)
    file:close()
    return true
  end
  return false
end

-- Load highlights from disk
function M.load(slug)
  local path = get_highlights_path(slug)

  if not fs.exists(path) then
    return { highlights = {} }
  end

  local content = fs.read_file(path)
  if not content then
    return { highlights = {} }
  end

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data then
    return { highlights = {} }
  end

  return data
end

-- Add a new highlight
function M.add_highlight(slug, highlight)
  local data = M.load(slug)
  table.insert(data.highlights, highlight)
  M.save(slug, data.highlights)
  return data.highlights
end

-- Remove highlight by text matching
function M.remove_highlight_by_text(slug, highlight)
  local data = M.load(slug)
  local new_highlights = {}

  for _, hl in ipairs(data.highlights) do
    -- Match by chapter and text content
    local is_match = hl.chapter == highlight.chapter and
                     hl.text == highlight.text and
                     hl.context_before == highlight.context_before and
                     hl.context_after == highlight.context_after

    if not is_match then
      table.insert(new_highlights, hl)
    end
  end

  M.save(slug, new_highlights)
  return new_highlights
end

-- Get highlights for a specific chapter
function M.get_chapter_highlights(slug, chapter)
  local data = M.load(slug)
  local chapter_highlights = {}

  for _, hl in ipairs(data.highlights) do
    if hl.chapter == chapter then
      table.insert(chapter_highlights, hl)
    end
  end

  return chapter_highlights
end

-- Update note on a highlight (match by text)
function M.update_note(slug, highlight, note_text)
  local data = M.load(slug)

  for _, hl in ipairs(data.highlights) do
    -- Match by chapter and text content
    if hl.chapter == highlight.chapter and
       hl.text == highlight.text and
       hl.context_before == highlight.context_before and
       hl.context_after == highlight.context_after then
      -- Update note
      if note_text and note_text ~= "" then
        hl.note = note_text
        hl.updated_at = os.time()
        if not hl.created_at then
          hl.created_at = os.time()
        end
      else
        -- Remove note if empty
        hl.note = nil
        hl.created_at = nil
        hl.updated_at = nil
      end
      break
    end
  end

  M.save(slug, data.highlights)
  return data.highlights
end

-- Update color on a highlight (match by text)
function M.update_color(slug, highlight, new_color)
  local data = M.load(slug)

  for _, hl in ipairs(data.highlights) do
    -- Match by chapter and text content
    if hl.chapter == highlight.chapter and
       hl.text == highlight.text and
       hl.context_before == highlight.context_before and
       hl.context_after == highlight.context_after then
      -- Update color
      hl.color = new_color
      hl.updated_at = os.time()
      if not hl.created_at then
        hl.created_at = os.time()
      end
      break
    end
  end

  M.save(slug, data.highlights)
  return data.highlights
end

return M
