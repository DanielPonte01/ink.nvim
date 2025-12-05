local fs = require("ink.fs")

local M = {}

-- Pretty-print JSON encoder
local function json_pretty_encode(data, indent)
  indent = indent or 0
  local spacing = string.rep("  ", indent)
  local spacing_inner = string.rep("  ", indent + 1)

  if type(data) == "table" then
    -- Check if array or object
    local is_array = #data > 0 or next(data) == nil
    if is_array and #data > 0 then
      -- Check if it's really an array (sequential numeric keys)
      for k, _ in pairs(data) do
        if type(k) ~= "number" then
          is_array = false
          break
        end
      end
    end

    if is_array then
      if #data == 0 then
        return "[]"
      end
      local items = {}
      for _, v in ipairs(data) do
        table.insert(items, spacing_inner .. json_pretty_encode(v, indent + 1))
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. spacing .. "]"
    else
      local items = {}
      for k, v in pairs(data) do
        local key = '"' .. tostring(k) .. '"'
        table.insert(items, spacing_inner .. key .. ": " .. json_pretty_encode(v, indent + 1))
      end
      if #items == 0 then
        return "{}"
      end
      -- Sort keys for consistent output
      table.sort(items)
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. spacing .. "}"
    end
  elseif type(data) == "string" then
    -- Escape special characters
    local escaped = data:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. escaped .. '"'
  elseif type(data) == "number" then
    return tostring(data)
  elseif type(data) == "boolean" then
    return data and "true" or "false"
  elseif data == nil then
    return "null"
  else
    return '"' .. tostring(data) .. '"'
  end
end

-- Get the highlights file path for a book
local function get_highlights_path(slug)
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  fs.ensure_dir(data_dir)
  return data_dir .. "/" .. slug .. "_highlights.json"
end

-- Save highlights to disk (pretty-printed for readability)
function M.save(slug, highlights)
  local path = get_highlights_path(slug)
  local data = json_pretty_encode({ highlights = highlights })

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

return M
