local data = require("ink.data")
local fs = require("ink.fs")
local planalto_parser = require("ink.web.planalto_parser")
local web_util = require("ink.web.util")

local M = {}

-- Get changelog file path
local function get_changelog_path(slug)
  local book_dir = data.get_book_dir(slug)
  return book_dir .. "/changelog.json"
end

-- Load changelog from disk
-- @param slug: unique identifier for the law
-- @return changelog data or nil
function M.load(slug)
  local changelog_path = get_changelog_path(slug)

  if not fs.exists(changelog_path) then
    return {
      slug = slug,
      changes = {},
      last_update = nil
    }
  end

  local content = fs.read_file(changelog_path)
  if not content then
    return nil
  end

  local changelog, err = data.json_decode_safe(content, changelog_path)
  if not changelog then
    vim.notify("Failed to load changelog: " .. err, vim.log.levels.WARN)
    return {
      slug = slug,
      changes = {},
      last_update = nil
    }
  end

  return changelog
end

-- Save changelog to disk
-- @param slug: unique identifier for the law
-- @param changelog: changelog data structure
function M.save(slug, changelog)
  local changelog_path = get_changelog_path(slug)
  local content = data.json_encode(changelog)

  local ok, err = fs.write_file(changelog_path, content)
  if not ok then
    vim.notify("Failed to save changelog: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end

  return true
end

-- Compare two article lists and detect changes
-- @param old_articles: array from parser.parse()
-- @param new_articles: array from parser.parse()
-- @return changes array
local function detect_changes(old_articles, new_articles)
  local changes = {}

  -- Create lookup maps
  local old_map = {}
  for _, article in ipairs(old_articles) do
    old_map[article.number] = article
  end

  local new_map = {}
  for _, article in ipairs(new_articles) do
    new_map[article.number] = article
  end

  -- Detect new and modified articles
  for _, new_article in ipairs(new_articles) do
    local old_article = old_map[new_article.number]

    if not old_article then
      -- New article
      table.insert(changes, {
        type = "added",
        article_number = new_article.number,
        title = new_article.title,
        timestamp = os.time()
      })
    elseif old_article.compiled ~= new_article.compiled then
      -- Modified article
      table.insert(changes, {
        type = "modified",
        article_number = new_article.number,
        title = new_article.title,
        timestamp = os.time()
      })
    end
  end

  -- Detect removed articles
  for _, old_article in ipairs(old_articles) do
    if not new_map[old_article.number] then
      table.insert(changes, {
        type = "removed",
        article_number = old_article.number,
        title = old_article.title,
        timestamp = os.time()
      })
    end
  end

  return changes
end

-- Update changelog with new version
-- @param slug: unique identifier for the page
-- @param old_html: previous HTML content (or nil for first version)
-- @param new_html: new HTML content
-- @param url: URL of the page
-- @return changelog, has_changes
function M.update(slug, old_html, new_html, url)
  local changelog = M.load(slug)

  -- If no old version, this is the first download
  if not old_html then
    changelog.last_update = os.time()
    M.save(slug, changelog)
    return changelog, false
  end

  local changes = {}

  -- For Planalto pages, detect article-level changes
  if web_util.is_planalto_url(url) then
    -- Parse both versions
    local old_parsed = planalto_parser.parse(old_html, url)
    local new_parsed = planalto_parser.parse(new_html, url)

    -- Detect changes
    changes = detect_changes(old_parsed.articles, new_parsed.articles)
  else
    -- For generic pages, just detect if content changed
    if old_html ~= new_html then
      table.insert(changes, {
        type = "modified",
        article_number = "page",
        title = "Conteúdo da página",
        timestamp = os.time()
      })
    end
  end

  -- If there are changes, add them to changelog
  if #changes > 0 then
    local change_entry = {
      timestamp = os.time(),
      changes = changes,
      total_added = 0,
      total_modified = 0,
      total_removed = 0
    }

    -- Count changes by type
    for _, change in ipairs(changes) do
      if change.type == "added" then
        change_entry.total_added = change_entry.total_added + 1
      elseif change.type == "modified" then
        change_entry.total_modified = change_entry.total_modified + 1
      elseif change.type == "removed" then
        change_entry.total_removed = change_entry.total_removed + 1
      end
    end

    table.insert(changelog.changes, change_entry)
    changelog.last_update = os.time()

    M.save(slug, changelog)

    return changelog, true
  end

  -- No changes
  changelog.last_update = os.time()
  M.save(slug, changelog)
  return changelog, false
end

-- Get list of modified articles for highlighting
-- @param changelog: changelog data structure
-- @return array of article numbers
function M.get_modified_articles(changelog)
  local modified = {}

  -- Get changes from the most recent update
  if #changelog.changes > 0 then
    local latest = changelog.changes[#changelog.changes]

    for _, change in ipairs(latest.changes) do
      if change.type == "modified" or change.type == "added" then
        table.insert(modified, change.article_number)
      end
    end
  end

  return modified
end

-- Format changelog for display
-- @param changelog: changelog data structure
-- @return formatted string
function M.format_for_display(changelog)
  if #changelog.changes == 0 then
    return "Nenhuma atualização registrada."
  end

  local lines = {}
  table.insert(lines, "# Histórico de Atualizações\n")

  for i = #changelog.changes, 1, -1 do
    local entry = changelog.changes[i]
    local date = os.date("%d/%m/%Y %H:%M", entry.timestamp)

    table.insert(lines, string.format("\n## Atualização em %s", date))
    table.insert(lines, string.format("- Artigos adicionados: %d", entry.total_added))
    table.insert(lines, string.format("- Artigos modificados: %d", entry.total_modified))
    table.insert(lines, string.format("- Artigos removidos: %d", entry.total_removed))
    table.insert(lines, "\n### Detalhes:")

    for _, change in ipairs(entry.changes) do
      local change_desc
      if change.type == "added" then
        change_desc = "➕ Adicionado"
      elseif change.type == "modified" then
        change_desc = "✏️  Modificado"
      elseif change.type == "removed" then
        change_desc = "❌ Removido"
      end

      table.insert(lines, string.format("- %s: Art. %s - %s", change_desc, change.article_number, change.title))
    end
  end

  return table.concat(lines, "\n")
end

return M
