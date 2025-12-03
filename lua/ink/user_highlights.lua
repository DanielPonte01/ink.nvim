local fs = require("ink.fs")

local M = {}

-- Get the highlights file path for a book
local function get_highlights_path(slug)
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  fs.ensure_dir(data_dir)
  return data_dir .. "/" .. slug .. "_highlights.json"
end

-- Save highlights to disk
function M.save(slug, highlights)
  local path = get_highlights_path(slug)
  local data = vim.json.encode({ highlights = highlights })

  local file = io.open(path, "w")
  if file then
    file:write(data)
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

-- Remove highlight at position
function M.remove_highlight(slug, chapter, line, col)
  local data = M.load(slug)
  local new_highlights = {}

  for _, hl in ipairs(data.highlights) do
    -- Check if cursor is within this highlight
    local is_in_highlight = false

    if hl.chapter == chapter then
      if hl.start_line == hl.end_line then
        -- Single line highlight
        if line == hl.start_line and col >= hl.start_col and col < hl.end_col then
          is_in_highlight = true
        end
      else
        -- Multi-line highlight
        if line == hl.start_line and col >= hl.start_col then
          is_in_highlight = true
        elseif line == hl.end_line and col < hl.end_col then
          is_in_highlight = true
        elseif line > hl.start_line and line < hl.end_line then
          is_in_highlight = true
        end
      end
    end

    if not is_in_highlight then
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

return M
