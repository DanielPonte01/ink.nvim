local M = {}

-- Generate ASCII graph for a single term and its relationships
-- Returns array of lines with graph structure
function M.generate_term_graph(entry, all_entries)
  local lines = {}

  -- Get type icon and name
  local context = require("ink.ui.context")
  local types_config = vim.tbl_extend("force",
    context.config.glossary_types or {},
    {}
  )
  local type_info = types_config[entry.type] or { icon = "📝", color = "InkGlossary" }
  local type_name = entry.type:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b)
    return a:upper() .. b
  end)

  -- Title: term (type)
  table.insert(lines, string.format("%s %s (%s)", type_info.icon, entry.term, type_name))

  if not entry.relationships or next(entry.relationships) == nil then
    table.insert(lines, "")
    table.insert(lines, "(No relationships)")
    return lines
  end

  -- Sort relationship labels
  local labels = {}
  for label, _ in pairs(entry.relationships) do
    table.insert(labels, label)
  end
  table.sort(labels)

  -- Build entries map and alias map for quick lookup
  local entries_map = {}
  local alias_to_term = {}
  for _, e in ipairs(all_entries) do
    entries_map[e.term:lower()] = e
    -- Map each alias to the main term
    if e.aliases then
      for _, alias in ipairs(e.aliases) do
        alias_to_term[alias:lower()] = e.term
      end
    end
  end

  -- Resolve a term name (could be main term or alias) to the main term
  local function resolve_term(term_name)
    local term_lower = term_name:lower()
    -- Check if it's a main term
    if entries_map[term_lower] then
      return entries_map[term_lower].term
    end
    -- Check if it's an alias
    if alias_to_term[term_lower] then
      return alias_to_term[term_lower]
    end
    -- Not found - return original name
    return term_name
  end

  -- Draw relationships
  for idx, label in ipairs(labels) do
    local terms = entry.relationships[label]
    local is_last_label = (idx == #labels)

    -- Display label with proper capitalization
    local display_label = label:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
      return first:upper() .. rest
    end)

    -- Branch character for label
    local label_prefix = is_last_label and "└─ " or "├─ "
    table.insert(lines, label_prefix .. display_label)

    -- Draw terms under this label
    for term_idx, term_name in ipairs(terms) do
      local is_last_term = (term_idx == #terms)

      -- Resolve term name (could be alias)
      local resolved_name = resolve_term(term_name)
      local related_entry = entries_map[resolved_name:lower()]

      -- Indentation based on whether this is the last label
      local indent = is_last_label and "   " or "│  "

      -- Branch character for term
      local term_prefix = is_last_term and "└─ " or "├─ "

      -- Format term line
      local term_line
      if related_entry then
        local rel_type_info = types_config[related_entry.type] or { icon = "📝" }

        -- Build alias info if the term has aliases
        local alias_info = ""
        if related_entry.aliases and #related_entry.aliases > 0 then
          alias_info = " [" .. table.concat(related_entry.aliases, ", ") .. "]"
        end

        term_line = string.format("%s%s%s %s%s", indent, term_prefix, rel_type_info.icon, resolved_name, alias_info)
      else
        term_line = string.format("%s%s%s (not found)", indent, term_prefix, term_name)
      end

      table.insert(lines, term_line)
    end
  end

  return lines
end

-- Generate full graph showing all terms and their relationships
-- Returns array of lines with complete graph
function M.generate_full_graph(entries)
  local lines = {}

  table.insert(lines, "Glossary Graph")
  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "")

  if not entries or #entries == 0 then
    table.insert(lines, "(No glossary entries)")
    return lines
  end

  -- Sort entries by term
  local sorted_entries = {}
  for _, entry in ipairs(entries) do
    table.insert(sorted_entries, entry)
  end
  table.sort(sorted_entries, function(a, b)
    return a.term:lower() < b.term:lower()
  end)

  -- Generate graph for each entry
  for idx, entry in ipairs(sorted_entries) do
    local entry_graph = M.generate_term_graph(entry, entries)
    for _, line in ipairs(entry_graph) do
      table.insert(lines, line)
    end

    -- Add spacing between entries (except last one)
    if idx < #sorted_entries then
      table.insert(lines, "")
    end
  end

  return lines
end

return M
