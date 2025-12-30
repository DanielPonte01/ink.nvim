local M = {}

-- Format glossary entries as Markdown
-- @param entries: array of glossary entries
-- @param book_title: title of the book
-- @return string: formatted Markdown content
function M.format(entries, book_title)
  local lines = {}

  -- Title
  table.insert(lines, "# " .. (book_title or "Book") .. " - Glossary")
  table.insert(lines, "")
  table.insert(lines, "Exported: " .. os.date("%Y-%m-%d %H:%M:%S"))
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")

  if not entries or #entries == 0 then
    table.insert(lines, "*No glossary entries*")
    return table.concat(lines, "\n")
  end

  -- Sort entries alphabetically
  local sorted_entries = {}
  for _, entry in ipairs(entries) do
    table.insert(sorted_entries, entry)
  end
  table.sort(sorted_entries, function(a, b)
    return a.term:lower() < b.term:lower()
  end)

  -- Format each entry
  for _, entry in ipairs(sorted_entries) do
    -- Term as heading
    table.insert(lines, "## " .. entry.term)
    table.insert(lines, "")

    -- Aliases
    if entry.aliases and #entry.aliases > 0 then
      table.insert(lines, "**Aliases:** " .. table.concat(entry.aliases, ", "))
      table.insert(lines, "")
    end

    -- Relationships
    if entry.relationships and next(entry.relationships) ~= nil then
      table.insert(lines, "**Relationships:**")
      table.insert(lines, "")

      -- Sort relationship labels
      local labels = {}
      for label, _ in pairs(entry.relationships) do
        table.insert(labels, label)
      end
      table.sort(labels)

      for _, label in ipairs(labels) do
        local terms = entry.relationships[label]
        -- Display label with proper capitalization
        local display_label = label:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
          return first:upper() .. rest
        end)

        table.insert(lines, "- **" .. display_label .. ":** " .. table.concat(terms, ", "))
      end

      table.insert(lines, "")
    end

    -- Definition
    if entry.definition and entry.definition ~= "" then
      table.insert(lines, "**Definition:**")
      table.insert(lines, "")
      table.insert(lines, entry.definition)
    else
      table.insert(lines, "*No definition*")
    end

    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

return M
