-- lua/ink/ui/search_index.lua
-- Responsabilidade: Construção de índice de busca

local context = require("ink.ui.context")
local render = require("ink.ui.render")

local M = {}

-- Helper to get chapter name from TOC
function M.get_chapter_name(chapter_idx, ctx)
  local chapter = ctx.data.spine[chapter_idx]
  if not chapter then return "Chapter " .. chapter_idx end

  local chapter_href = chapter.href
  for _, toc_item in ipairs(ctx.data.toc) do
    local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
    if toc_href == chapter_href then
      -- Truncate name if too long
      local name = toc_item.label
      if #name > 20 then
        name = name:sub(1, 17) .. "..."
      end
      return name
    end
  end

  return "Ch. " .. chapter_idx
end

-- Build search index asynchronously for large books
function M.build_search_index_async(ctx, callback)
  local entries = {}
  local chapter_idx = 1
  local total = #ctx.data.spine

  vim.notify("Indexing book asynchronously...", vim.log.levels.INFO)

  local function process_next()
    if chapter_idx > total then
      vim.notify(string.format("Indexed %d lines from %d chapters", #entries, total), vim.log.levels.INFO)
      callback(entries)
      return
    end

    local parsed = render.get_parsed_chapter(chapter_idx, ctx)
    if parsed and parsed.lines then
      local chapter_name = M.get_chapter_name(chapter_idx, ctx)

      for line_num, line_text in ipairs(parsed.lines) do
        local trimmed = line_text:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
          local display_text = trimmed
          if #display_text > 60 then
            display_text = display_text:sub(1, 57) .. "..."
          end

          table.insert(entries, {
            display = string.format("[%d] %s: %s", chapter_idx, chapter_name, display_text),
            text = trimmed,
            chapter_idx = chapter_idx,
            chapter_name = chapter_name,
            line_num = line_num,
          })
        end
      end
    end

    chapter_idx = chapter_idx + 1
    vim.schedule(process_next)  -- Yield to not block UI
  end

  process_next()
end

-- Build search index from all chapters
function M.build_search_index(ctx)
  local entries = {}
  local total_chapters = #ctx.data.spine

  -- Show progress for large books
  local large_book = total_chapters > 20
  if large_book then
    vim.notify("Indexing book for search...", vim.log.levels.INFO)
  end

  for chapter_idx = 1, total_chapters do
    local parsed = render.get_parsed_chapter(chapter_idx, ctx)
    if parsed and parsed.lines then

      -- Get chapter name from TOC
      local chapter_name = M.get_chapter_name(chapter_idx, ctx)

      for line_num, line_text in ipairs(parsed.lines) do
        -- Ignore empty lines or only spaces
        local trimmed = line_text:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
          -- Create context for display (truncate if too long)
          local display_text = trimmed
          if #display_text > 60 then
            display_text = display_text:sub(1, 57) .. "..."
          end

          table.insert(entries, {
            display = string.format("[%d] %s: %s", chapter_idx, chapter_name, display_text),
            text = trimmed,  -- Full text for search
            chapter_idx = chapter_idx,
            chapter_name = chapter_name,
            line_num = line_num,
          })
        end
      end
    end
  end

  if large_book then
    vim.notify(string.format("Indexed %d lines from %d chapters", #entries, total_chapters), vim.log.levels.INFO)
  end

  return entries
end

-- Get or build search index with caching
function M.get_or_build_index(ctx, callback)
  -- Return cached index if exists
  if ctx.search_index then
    if callback then
      callback(ctx.search_index)
    else
      return ctx.search_index
    end
    return
  end

  local total_chapters = #ctx.data.spine
  local use_async = total_chapters > 50  -- Use async for books with more than 50 chapters

  if use_async and callback then
    -- Build asynchronously
    M.build_search_index_async(ctx, function(entries)
      ctx.search_index = entries
      callback(entries)
    end)
  else
    -- Build synchronously
    ctx.search_index = M.build_search_index(ctx)
    if callback then
      callback(ctx.search_index)
    else
      return ctx.search_index
    end
  end
end

return M
