-- Module for migrating highlights after web page updates
-- Handles cases where articles are added, removed, or reordered

local fs = require("ink.fs")
local data = require("ink.data")

local M = {}

-- Extract article number from spine item
-- For Planalto pages, spine items have IDs like "article-1", "article-2-A", etc.
-- @param spine_item: item from the spine array
-- @return article number string or nil
local function get_article_number_from_spine(spine_item)
  if not spine_item or not spine_item.id then
    return nil
  end

  -- Pattern: "article-1", "article-2-A", "article-26-B", etc.
  local article_num = spine_item.id:match("^article%-(.+)$")
  return article_num
end

-- Build mapping from article number to chapter index
-- @param spine: array of spine items
-- @return table mapping article_number -> chapter_index
local function build_article_map(spine)
  local map = {}

  for idx, item in ipairs(spine) do
    local article_num = get_article_number_from_spine(item)
    if article_num then
      map[article_num] = idx
    end
  end

  return map
end

-- Migrate highlights from old spine structure to new spine structure
-- @param slug: page identifier
-- @param old_spine: previous spine array
-- @param new_spine: updated spine array
-- @return migration_stats: { migrated: N, failed: N, unchanged: N }
function M.migrate_highlights(slug, old_spine, new_spine)
  local highlights_path = data.get_book_dir(slug) .. "/highlights.json"

  -- Check if highlights file exists
  if not fs.exists(highlights_path) then
    return { migrated = 0, failed = 0, unchanged = 0 }
  end

  -- Load highlights
  local content = fs.read_file(highlights_path)
  if not content then
    return { migrated = 0, failed = 0, unchanged = 0 }
  end

  local ok, hl_data = pcall(vim.json.decode, content)
  if not ok or not hl_data or not hl_data.highlights then
    return { migrated = 0, failed = 0, unchanged = 0 }
  end

  -- If no highlights, nothing to do
  if #hl_data.highlights == 0 then
    return { migrated = 0, failed = 0, unchanged = 0 }
  end

  -- Build article number mappings
  local old_map = build_article_map(old_spine)
  local new_map = build_article_map(new_spine)

  -- Build reverse map for old spine (chapter_index -> article_number)
  local old_reverse_map = {}
  for article_num, idx in pairs(old_map) do
    old_reverse_map[idx] = article_num
  end

  -- Migrate each highlight
  local stats = { migrated = 0, failed = 0, unchanged = 0 }
  local migrated_highlights = {}

  for _, hl in ipairs(hl_data.highlights) do
    local old_chapter = hl.chapter

    -- Get article number from old position
    local article_num = old_reverse_map[old_chapter]

    if article_num then
      -- Find new position for this article
      local new_chapter = new_map[article_num]

      if new_chapter then
        if new_chapter ~= old_chapter then
          -- Article moved to different position
          hl.chapter = new_chapter
          stats.migrated = stats.migrated + 1
        else
          -- Article stayed in same position
          stats.unchanged = stats.unchanged + 1
        end
        table.insert(migrated_highlights, hl)
      else
        -- Article not found in new structure (removed?)
        -- Keep highlight at old position as fallback
        stats.failed = stats.failed + 1
        table.insert(migrated_highlights, hl)
      end
    else
      -- Highlight was in a non-article section (header, footer, etc.)
      -- Keep as-is
      stats.unchanged = stats.unchanged + 1
      table.insert(migrated_highlights, hl)
    end
  end

  -- Save migrated highlights
  if stats.migrated > 0 or stats.failed > 0 then
    hl_data.highlights = migrated_highlights
    local user_highlights = require("ink.user_highlights")
    user_highlights.save(slug, migrated_highlights)
  end

  return stats
end

-- Check if page supports highlight migration
-- Currently only Planalto pages support this
-- @param page_data: page data structure
-- @return boolean
function M.supports_migration(page_data)
  return page_data.is_planalto == true
end

return M
