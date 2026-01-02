local data = require("ink.glossary.data")

local M = {}

function M.add(slug, entry)
  local loaded = data.load(slug)

  -- Generate ID and timestamps
  entry.id = tostring(os.time()) .. "_" .. math.random(1000, 9999)
  entry.created_at = os.time()
  entry.updated_at = os.time()

  -- Ensure required fields
  entry.term = entry.term or ""
  entry.type = entry.type or "other"
  entry.definition = entry.definition or ""
  entry.aliases = entry.aliases or {}
  entry.relationships = entry.relationships or {}

  table.insert(loaded.entries, entry)

  -- Handle bidirectional relationships
  M._sync_bidirectional_relationships(slug, entry, loaded.entries)

  data.save(slug, loaded.entries, loaded.custom_types)
  return entry
end

function M.update(slug, id, updates)
  local loaded = data.load(slug)

  local updated_entry = nil
  for _, entry in ipairs(loaded.entries) do
    if entry.id == id then
      -- Merge updates
      for key, value in pairs(updates) do
        entry[key] = value
      end
      entry.updated_at = os.time()
      updated_entry = entry
      break
    end
  end

  -- Handle bidirectional relationships if updated
  if updated_entry and updates.relationships then
    M._sync_bidirectional_relationships(slug, updated_entry, loaded.entries)
  end

  data.save(slug, loaded.entries, loaded.custom_types)
end

function M.remove(slug, id)
  local loaded = data.load(slug)
  local new_entries = {}

  -- Simply remove the entry - keep all relationships intact
  -- They will show as "(not found)" until the term is recreated
  for _, entry in ipairs(loaded.entries) do
    if entry.id ~= id then
      table.insert(new_entries, entry)
    end
  end

  data.save(slug, new_entries, loaded.custom_types)
end

function M.add_alias(slug, id, alias)
  local loaded = data.load(slug)

  for _, entry in ipairs(loaded.entries) do
    if entry.id == id then
      entry.aliases = entry.aliases or {}
      -- Check if alias already exists
      local exists = false
      for _, a in ipairs(entry.aliases) do
        if a == alias then
          exists = true
          break
        end
      end
      if not exists then
        table.insert(entry.aliases, alias)
        entry.updated_at = os.time()
      end
      break
    end
  end

  data.save(slug, loaded.entries, loaded.custom_types)
end

function M.remove_alias(slug, id, alias)
  local loaded = data.load(slug)

  for _, entry in ipairs(loaded.entries) do
    if entry.id == id and entry.aliases then
      local new_aliases = {}
      for _, a in ipairs(entry.aliases) do
        if a ~= alias then
          table.insert(new_aliases, a)
        end
      end
      entry.aliases = new_aliases
      entry.updated_at = os.time()
      break
    end
  end

  data.save(slug, loaded.entries, loaded.custom_types)
end

function M.add_related(slug, id, related_id)
  local loaded = data.load(slug)

  -- Add bidirectional relationship
  for _, entry in ipairs(loaded.entries) do
    if entry.id == id then
      entry.related = entry.related or {}
      -- Check if already related
      local exists = false
      for _, rel in ipairs(entry.related) do
        if rel == related_id then
          exists = true
          break
        end
      end
      if not exists then
        table.insert(entry.related, related_id)
        entry.updated_at = os.time()
      end
    elseif entry.id == related_id then
      entry.related = entry.related or {}
      -- Add reverse relationship
      local exists = false
      for _, rel in ipairs(entry.related) do
        if rel == id then
          exists = true
          break
        end
      end
      if not exists then
        table.insert(entry.related, id)
        entry.updated_at = os.time()
      end
    end
  end

  data.save(slug, loaded.entries, loaded.custom_types)
end

function M.remove_related(slug, id, related_id)
  local loaded = data.load(slug)

  -- Remove bidirectional relationship
  for _, entry in ipairs(loaded.entries) do
    if (entry.id == id or entry.id == related_id) and entry.related then
      local new_related = {}
      for _, rel in ipairs(entry.related) do
        if rel ~= id and rel ~= related_id then
          table.insert(new_related, rel)
        end
      end
      entry.related = new_related
      entry.updated_at = os.time()
    end
  end

  data.save(slug, loaded.entries, loaded.custom_types)
end

function M.add_custom_type(slug, type_name, icon, color)
  local loaded = data.load(slug)

  loaded.custom_types[type_name] = {
    icon = icon or "📝",
    color = color or "InkGlossary"
  }

  data.save(slug, loaded.entries, loaded.custom_types)
end

-- Internal function to sync bidirectional relationships
-- When A has relationship to B, automatically add B → A relationship
function M._sync_bidirectional_relationships(slug, updated_entry, all_entries)
  if not updated_entry.relationships then return end

  -- For each relationship label in the updated entry
  for label, terms in pairs(updated_entry.relationships) do
    for _, term_name in ipairs(terms) do
      -- Find the related entry by term name
      for _, other_entry in ipairs(all_entries) do
        if other_entry.id ~= updated_entry.id and other_entry.term:lower() == term_name:lower() then
          -- Found the related entry, add reverse relationship
          other_entry.relationships = other_entry.relationships or {}
          other_entry.relationships[label] = other_entry.relationships[label] or {}

          -- Check if reverse relationship already exists
          local already_exists = false
          for _, existing_term in ipairs(other_entry.relationships[label]) do
            if existing_term:lower() == updated_entry.term:lower() then
              already_exists = true
              break
            end
          end

          -- Add reverse relationship if not exists
          if not already_exists then
            table.insert(other_entry.relationships[label], updated_entry.term)
            other_entry.updated_at = os.time()
          end
          break
        end
      end
    end
  end
end

return M
