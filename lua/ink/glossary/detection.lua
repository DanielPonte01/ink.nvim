local M = {}

-- Calculate a version hash for the glossary based on terms and aliases
-- Only includes data that affects detection (not definitions or relationships)
function M.calculate_version_hash(entries)
  if not entries or #entries == 0 then
    return "empty"
  end

  -- Sort entries by ID for consistent hashing
  local sorted = {}
  for _, entry in ipairs(entries) do
    table.insert(sorted, entry)
  end
  table.sort(sorted, function(a, b)
    return (a.id or "") < (b.id or "")
  end)

  -- Build string with detection-relevant data
  local parts = {}
  for _, entry in ipairs(sorted) do
    table.insert(parts, entry.id or "")
    table.insert(parts, entry.term or "")

    -- Include aliases (sorted for consistency)
    if entry.aliases and #entry.aliases > 0 then
      local sorted_aliases = {}
      for _, alias in ipairs(entry.aliases) do
        table.insert(sorted_aliases, alias)
      end
      table.sort(sorted_aliases)
      table.insert(parts, table.concat(sorted_aliases, ","))
    end
  end

  local hash_input = table.concat(parts, "|")

  -- Use sha256 if available, otherwise simple checksum
  if vim.fn.has('nvim-0.10') == 1 and vim.fn.exists('*sha256') == 1 then
    return vim.fn.sha256(hash_input)
  else
    -- Fallback: simple checksum (good enough for versioning)
    local sum = 0
    for i = 1, #hash_input do
      sum = sum + string.byte(hash_input, i)
    end
    return string.format("checksum_%d_%d", sum, #hash_input)
  end
end

-- Build detection index from entries
-- Returns: { exact_terms = { [normalized_term] = entry }, aliases = { [normalized_alias] = entry } }
function M.build_detection_index(entries)
  local index = {
    exact_terms = {},
    aliases = {},
    entries = {}  -- Map of entry_id -> entry for quick lookup
  }

  for _, entry in ipairs(entries) do
    -- Store entry by ID for quick lookup
    index.entries[entry.id] = entry

    -- Index primary term (case-insensitive)
    local normalized_term = (entry.term or ""):lower()
    if normalized_term ~= "" then
      index.exact_terms[normalized_term] = entry
    end

    -- Index aliases
    if entry.aliases then
      for _, alias in ipairs(entry.aliases) do
        local normalized_alias = alias:lower()
        if normalized_alias ~= "" then
          index.aliases[normalized_alias] = entry
        end
      end
    end
  end

  return index
end

-- Detect terms in a single line of text
-- Returns: array of { term, entry_id, start_pos, end_pos }
function M.detect_in_text(text, detection_index)
  local matches = {}
  local normalized = text:lower()

  -- Collect all searchable terms (both exact terms and aliases)
  local terms = {}
  for term in pairs(detection_index.exact_terms) do
    table.insert(terms, term)
  end
  for alias in pairs(detection_index.aliases) do
    table.insert(terms, alias)
  end

  -- Sort by length DESC to match longer terms first
  table.sort(terms, function(a, b)
    return #a > #b
  end)

  -- Track matched positions to avoid overlaps
  local matched_ranges = {}

  -- Detect each term
  for _, term in ipairs(terms) do
    -- Use word boundary pattern: %f[%w] = frontier pattern for word start
    -- %f[%W] = frontier pattern for word end
    local pattern = "%f[%w]" .. vim.pesc(term) .. "%f[%W]"
    local start_pos = 1

    while true do
      local s, e = normalized:find(pattern, start_pos)
      if not s then break end

      -- Check if this range overlaps with already matched ranges
      local overlaps = false
      for _, range in ipairs(matched_ranges) do
        if not (e < range.s or s > range.e) then
          overlaps = true
          break
        end
      end

      if not overlaps then
        -- Get entry and determine if it's an alias match
        local entry = detection_index.exact_terms[term]
        local is_alias = false

        if not entry then
          entry = detection_index.aliases[term]
          is_alias = true
        end

        table.insert(matches, {
          term = text:sub(s, e),  -- Original case from text
          entry_id = entry.id,
          start_pos = s,
          end_pos = e,
          is_alias = is_alias
        })

        -- Mark this range as matched
        table.insert(matched_ranges, { s = s, e = e })
      end

      start_pos = e + 1
    end
  end

  -- Sort matches by position
  table.sort(matches, function(a, b)
    return a.start_pos < b.start_pos
  end)

  return matches
end

-- Detect terms in all chapter lines
-- Returns: array of { term, entry_id, line, start_col, end_col, is_alias }
function M.detect_in_chapter(lines, detection_index)
  local matches = {}

  for line_idx, line_text in ipairs(lines) do
    local line_matches = M.detect_in_text(line_text, detection_index)

    for _, match in ipairs(line_matches) do
      table.insert(matches, {
        term = match.term,
        entry_id = match.entry_id,
        line = line_idx,
        start_col = match.start_pos - 1,  -- Convert to 0-based for Neovim
        end_col = match.end_pos,           -- end_col is exclusive in Neovim
        is_alias = match.is_alias
      })
    end
  end

  return matches
end

return M
