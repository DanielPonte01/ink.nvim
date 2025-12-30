local data = require("ink.glossary.data")

local M = {}

function M.get_all(slug)
  local loaded = data.load(slug)
  local entries = loaded.entries or {}
  -- Sort alphabetically by term
  table.sort(entries, function(a, b)
    return (a.term or ""):lower() < (b.term or ""):lower()
  end)
  return entries
end

function M.get_by_id(slug, id)
  local entries = M.get_all(slug)
  for _, entry in ipairs(entries) do
    if entry.id == id then
      return entry
    end
  end
  return nil
end

function M.get_by_term(slug, term)
  local entries = M.get_all(slug)
  local normalized_term = term:lower()
  for _, entry in ipairs(entries) do
    if (entry.term or ""):lower() == normalized_term then
      return entry
    end
  end
  return nil
end

function M.get_by_type(slug, type_name)
  local entries = M.get_all(slug)
  local result = {}
  for _, entry in ipairs(entries) do
    if entry.type == type_name then
      table.insert(result, entry)
    end
  end
  return result
end

function M.search(slug, query)
  local entries = M.get_all(slug)
  local results = {}
  local normalized_query = query:lower()

  for _, entry in ipairs(entries) do
    local score = 0

    -- Check term (highest weight)
    if (entry.term or ""):lower():find(normalized_query, 1, true) then
      score = score + 10
    end

    -- Check aliases
    if entry.aliases then
      for _, alias in ipairs(entry.aliases) do
        if alias:lower():find(normalized_query, 1, true) then
          score = score + 8
          break
        end
      end
    end

    -- Check definition (lower weight)
    if entry.definition and entry.definition:lower():find(normalized_query, 1, true) then
      score = score + 3
    end

    if score > 0 then
      table.insert(results, { entry = entry, score = score })
    end
  end

  -- Sort by score descending
  table.sort(results, function(a, b)
    return a.score > b.score
  end)

  -- Extract entries
  local final = {}
  for _, r in ipairs(results) do
    table.insert(final, r.entry)
  end

  return final
end

function M.get_related(slug, entry_id)
  local entry = M.get_by_id(slug, entry_id)
  if not entry or not entry.related then
    return {}
  end

  local results = {}
  for _, related_id in ipairs(entry.related) do
    local related_entry = M.get_by_id(slug, related_id)
    if related_entry then
      table.insert(results, related_entry)
    end
  end

  return results
end

function M.get_types(slug)
  local entries = M.get_all(slug)
  local types = {}
  local seen = {}

  for _, entry in ipairs(entries) do
    if entry.type and not seen[entry.type] then
      seen[entry.type] = true
      table.insert(types, entry.type)
    end
  end

  table.sort(types)
  return types
end

return M
