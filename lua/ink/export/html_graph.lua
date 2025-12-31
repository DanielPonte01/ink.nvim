local M = {}

-- Convert glossary entries to graph data (nodes and links)
local function convert_to_graph_data(entries)
  local nodes = {}
  local links = {}
  local entries_map = {}
  local alias_to_term = {}
  local all_mentioned_terms = {}

  -- Build entries map and alias map for quick lookup
  for _, entry in ipairs(entries) do
    entries_map[entry.term:lower()] = entry

    -- Map each alias to the main term
    if entry.aliases then
      for _, alias in ipairs(entry.aliases) do
        alias_to_term[alias:lower()] = entry.term
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

  -- Track all terms mentioned in relationships (resolved to main terms)
  for _, entry in ipairs(entries) do
    if entry.relationships then
      for _, terms in pairs(entry.relationships) do
        for _, term_name in ipairs(terms) do
          local resolved = resolve_term(term_name)
          all_mentioned_terms[resolved:lower()] = resolved
        end
      end
    end
  end

  -- Create nodes for existing entries
  for _, entry in ipairs(entries) do
    table.insert(nodes, {
      id = entry.term,
      label = entry.term,
      type = entry.type or "other",
      definition = entry.definition or "",
      aliases = entry.aliases or {},
      relationships = entry.relationships or {},
      exists = true
    })
  end

  -- Create ghost nodes for terms that don't exist and aren't aliases
  for term_lower, term_name in pairs(all_mentioned_terms) do
    if not entries_map[term_lower] then
      table.insert(nodes, {
        id = term_name,
        label = term_name,
        type = "not_found",
        definition = "This term is referenced but not yet defined in the glossary",
        aliases = {},
        relationships = {},
        exists = false
      })
    end
  end

  -- Create links from relationships (resolving aliases to main terms)
  local all_links = {}
  for _, entry in ipairs(entries) do
    if entry.relationships then
      for label, terms in pairs(entry.relationships) do
        for _, term_name in ipairs(terms) do
          local resolved_target = resolve_term(term_name)
          table.insert(all_links, {
            source = entry.term,
            target = resolved_target,
            label = label
          })
        end
      end
    end
  end

  -- Deduplicate bidirectional links with same label
  local seen = {}
  for _, link in ipairs(all_links) do
    -- Create normalized key (alphabetically ordered pair + label)
    local pair_key
    if link.source < link.target then
      pair_key = link.source .. "|" .. link.target .. "|" .. link.label
    else
      pair_key = link.target .. "|" .. link.source .. "|" .. link.label
    end

    -- Only add if we haven't seen this bidirectional pair+label before
    if not seen[pair_key] then
      seen[pair_key] = true
      table.insert(links, link)
    end
  end

  return nodes, links
end

-- Escape string for JSON embedding in HTML
local function json_escape(str)
  str = str:gsub("\\", "\\\\")
  str = str:gsub('"', '\\"')
  str = str:gsub("\n", "\\n")
  str = str:gsub("\r", "\\r")
  str = str:gsub("\t", "\\t")
  return str
end

-- Check if table is array (has only consecutive numeric keys starting from 1)
local function is_array(t)
  if type(t) ~= "table" then return false end
  local count = 0
  for k, _ in pairs(t) do
    count = count + 1
    if type(k) ~= "number" or k ~= count then
      return false
    end
  end
  return true
end

-- Convert Lua table to JSON string (simple implementation)
local function to_json(obj)
  if type(obj) == "table" then
    if is_array(obj) then
      local items = {}
      for _, v in ipairs(obj) do
        table.insert(items, to_json(v))
      end
      return "[" .. table.concat(items, ",") .. "]"
    else
      local items = {}
      for k, v in pairs(obj) do
        table.insert(items, '"' .. k .. '":' .. to_json(v))
      end
      return "{" .. table.concat(items, ",") .. "}"
    end
  elseif type(obj) == "string" then
    return '"' .. json_escape(obj) .. '"'
  elseif type(obj) == "number" then
    return tostring(obj)
  elseif type(obj) == "boolean" then
    return obj and "true" or "false"
  else
    return "null"
  end
end

-- Generate HTML with embedded D3.js graph
function M.generate(entries, book_title)
  local nodes, links = convert_to_graph_data(entries)

  -- Convert to JSON strings
  local nodes_json = to_json(nodes)
  local links_json = to_json(links)

  local html = [[
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>]] .. (book_title or "Book") .. [[ - Glossary Graph</title>
  <script src="https://d3js.org/d3.v7.min.js"></script>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      background: linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%);
      overflow: hidden;
      height: 100vh;
      transition: background 0.3s ease;
    }

    body.dark {
      background: linear-gradient(135deg, #0a0a0a 0%, #1a1a1a 100%);
    }

    body.dark .header {
      background: rgba(20, 20, 20, 0.95);
      border-bottom-color: #2a2a2a;
    }

    body.dark .header-content h1,
    body.dark .stat-value,
    body.dark .metadata-value,
    body.dark .term-name {
      color: #ffffff;
    }

    body.dark .header-content p,
    body.dark .stat-label,
    body.dark .sidebar-section h3,
    body.dark .detail-section h4,
    body.dark .metadata-label {
      color: #a0a0a0;
    }

    body.dark .sidebar-left,
    body.dark .sidebar-right,
    body.dark .canvas-footer,
    body.dark .analytics-content {
      background: #1a1a1a;
      border-color: #2a2a2a;
    }

    body.dark .search-input,
    body.dark .layout-select,
    body.dark .btn,
    body.dark .metadata-item,
    body.dark .alias-badge {
      background: #0f0f0f;
      border-color: #2a2a2a;
      color: #e0e0e0;
    }

    body.dark .relationship-card {
      background: #252525;
      border-color: #3a3a3a;
      color: #e0e0e0;
    }

    body.dark .center-area {
      background: linear-gradient(135deg, #0a0a0a 0%, #141414 100%);
    }

    body.dark .zoom-btn,
    body.dark .zoom-indicator {
      background: rgba(20, 20, 20, 0.95);
      border-color: #2a2a2a;
      color: #ffffff;
    }

    body.dark .node-label {
      fill: #ffffff;
      stroke: #0a0a0a;
    }

    body.dark .link {
      stroke: #404040;
    }

    body.dark .link-label {
      fill: #a0a0a0;
    }

    body.dark .close-btn {
      background: #0f0f0f;
      color: #a0a0a0;
    }

    body.dark .close-btn:hover {
      background: #2a2a2a;
      color: #ffffff;
    }

    body.dark .filter-checkbox label,
    body.dark .legend-label,
    body.dark .detail-section p {
      color: #d0d0d0;
    }

    body.dark .detail-section h4 {
      color: #a0a0a0;
    }

    body.dark .alias-badge {
      background: #1a1a1a;
      border-color: #3a3a3a;
      color: #d0d0d0;
    }

    body.dark .relationship-label {
      color: #ffffff;
      font-weight: 700;
    }

    body.dark .relationship-count {
      background: #1a1a1a;
      color: #a0a0a0;
      border: 1px solid #3a3a3a;
    }

    body.dark .relationship-link {
      background: #1a1a1a;
      border-color: #3a3a3a;
      color: #60a5fa;
    }

    body.dark .relationship-link:hover {
      background: #2a2a2a;
      border-color: #60a5fa;
      color: #93c5fd;
    }

    body.dark .term-connections {
      background: #1a1a1a;
      color: #a0a0a0;
      border: 1px solid #3a3a3a;
    }

    body.dark .analytics-card {
      background: linear-gradient(135deg, #0f0f0f 0%, #1a1a1a 100%);
      border-color: #2a2a2a;
    }

    body.dark .top-terms {
      background: #0f0f0f;
      border-color: #2a2a2a;
    }

    body.dark .top-terms li {
      background: #1a1a1a;
      border-color: #2a2a2a;
    }

    body.dark .analytics-header {
      border-bottom-color: #2a2a2a;
    }

    body.dark .analytics-header h2 {
      color: #ffffff;
    }

    body.dark .analytics-card h4 {
      color: #a0a0a0;
    }

    body.dark .analytics-card .value {
      color: #ffffff;
    }

    body.dark .analytics-card .label {
      color: #d0d0d0;
    }

    body.dark .top-terms h3 {
      color: #ffffff;
    }

    body.dark .top-terms li {
      color: #e0e0e0;
    }

    body.dark .top-terms .term-name {
      color: #ffffff;
    }

    body.dark .sidebar-right-header h2 {
      color: #ffffff;
    }

    body.dark .type-badge {
      color: #ffffff;
      font-weight: 700;
    }

    body.dark .badge-concept {
      background: #1e40af;
    }

    body.dark .badge-term {
      background: #4338ca;
    }

    body.dark .badge-other {
      background: #475569;
    }

    body.dark .badge-not_found {
      background: #991b1b;
    }

    /* Header */
    .header {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      height: 89px;
      background: rgba(255, 255, 255, 0.95);
      backdrop-filter: blur(10px);
      border-bottom: 1px solid #e2e8f0;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0 32px;
      z-index: 100;
    }

    .header-left {
      display: flex;
      align-items: center;
      gap: 16px;
    }

    .header-icon {
      width: 48px;
      height: 48px;
      background: linear-gradient(135deg, #3b82f6 0%, #8b5cf6 100%);
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 24px;
    }

    .header-content h1 {
      font-size: 20px;
      font-weight: 700;
      color: #0f172a;
      margin-bottom: 4px;
    }

    .header-content p {
      font-size: 13px;
      color: #64748b;
    }

    .quick-search-btn {
      padding: 10px 20px;
      background: #3b82f6;
      color: white;
      border: none;
      border-radius: 8px;
      font-size: 14px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s;
      box-shadow: 0 1px 2px rgba(59, 130, 246, 0.2);
    }

    .quick-search-btn:hover {
      background: #2563eb;
      transform: translateY(-1px);
      box-shadow: 0 4px 6px rgba(59, 130, 246, 0.25);
    }

    /* Main Layout */
    .app-container {
      position: fixed;
      top: 89px;
      left: 0;
      right: 0;
      bottom: 0;
      display: flex;
    }

    /* Left Sidebar */
    .sidebar-left {
      width: 320px;
      background: white;
      border-right: 1px solid #e2e8f0;
      display: flex;
      flex-direction: column;
      overflow-y: auto;
    }

    .sidebar-section {
      padding: 24px;
      border-bottom: 1px solid #e2e8f0;
    }

    .sidebar-section h3 {
      font-size: 12px;
      font-weight: 600;
      color: #64748b;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
    }

    .search-input {
      width: 100%;
      padding: 10px 12px 10px 38px;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      font-size: 14px;
      color: #0f172a;
      background: #f8fafc url('data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="%2364748b" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/></svg>') no-repeat 12px center;
      transition: all 0.2s;
    }

    .search-input:focus {
      outline: none;
      border-color: #3b82f6;
      background-color: white;
    }

    .layout-select {
      width: 100%;
      padding: 10px 12px;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      font-size: 14px;
      color: #0f172a;
      background: #f8fafc;
      cursor: pointer;
      transition: all 0.2s;
    }

    .layout-select:focus {
      outline: none;
      border-color: #3b82f6;
      background-color: white;
    }

    .filter-checkbox {
      display: flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 10px;
    }

    .filter-checkbox input {
      width: 18px;
      height: 18px;
      cursor: pointer;
    }

    .filter-checkbox label {
      font-size: 14px;
      color: #334155;
      cursor: pointer;
    }

    .actions-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
      margin-bottom: 8px;
    }

    .btn {
      padding: 10px;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 500;
      cursor: pointer;
      transition: all 0.2s;
      background: white;
      color: #334155;
    }

    .btn:hover {
      border-color: #cbd5e1;
      background: #f8fafc;
    }

    .btn-primary {
      background: #3b82f6;
      color: white;
      border: none;
    }

    .btn-primary:hover {
      background: #2563eb;
    }

    .btn-full {
      width: 100%;
      margin-bottom: 8px;
    }

    .legend-item {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-bottom: 10px;
    }

    .legend-dot {
      width: 14px;
      height: 14px;
      border-radius: 50%;
      border: 2px solid white;
      box-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
    }

    .legend-label {
      font-size: 13px;
      color: #334155;
      font-weight: 500;
    }

    /* Center Area */
    .center-area {
      flex: 1;
      display: flex;
      flex-direction: column;
      position: relative;
      background: linear-gradient(135deg, #f8fafc 0%, #e0e7ff 100%);
    }

    #graph-container {
      flex: 1;
      position: relative;
      overflow: hidden;
    }

    #graph {
      width: 100%;
      height: 100%;
    }

    /* Zoom Controls */
    .zoom-controls {
      position: absolute;
      top: 20px;
      right: 20px;
      display: flex;
      flex-direction: column;
      gap: 8px;
      z-index: 10;
    }

    .zoom-btn {
      width: 40px;
      height: 40px;
      background: rgba(255, 255, 255, 0.95);
      backdrop-filter: blur(10px);
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      color: #334155;
      transition: all 0.2s;
      box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
    }

    .zoom-btn:hover {
      background: white;
      color: #3b82f6;
      border-color: #3b82f6;
      transform: scale(1.05);
    }

    .zoom-indicator {
      position: absolute;
      top: 20px;
      left: 20px;
      padding: 8px 16px;
      background: rgba(255, 255, 255, 0.95);
      backdrop-filter: blur(10px);
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      font-size: 13px;
      font-weight: 600;
      color: #334155;
      box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
    }

    /* Canvas Footer */
    .canvas-footer {
      position: absolute;
      bottom: 0;
      left: 0;
      right: 0;
      padding: 16px 24px;
      background: rgba(255, 255, 255, 0.95);
      backdrop-filter: blur(10px);
      border-top: 1px solid #e2e8f0;
      display: flex;
      justify-content: center;
      gap: 40px;
    }

    .stat-item {
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 4px;
    }

    .stat-label {
      font-size: 12px;
      color: #64748b;
      font-weight: 500;
    }

    .stat-value {
      font-size: 20px;
      font-weight: 700;
      color: #0f172a;
    }

    /* Right Sidebar */
    .sidebar-right {
      width: 384px;
      background: white;
      border-left: 1px solid #e2e8f0;
      display: flex;
      flex-direction: column;
      transform: translateX(100%);
      transition: transform 0.3s ease;
    }

    .sidebar-right.open {
      transform: translateX(0);
    }

    .sidebar-right-header {
      padding: 24px;
      border-bottom: 1px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      align-items: start;
    }

    .sidebar-right-header h2 {
      font-size: 18px;
      font-weight: 700;
      color: #0f172a;
      margin-bottom: 8px;
    }

    .close-btn {
      width: 32px;
      height: 32px;
      border: none;
      background: #f8fafc;
      border-radius: 6px;
      cursor: pointer;
      font-size: 20px;
      color: #64748b;
      transition: all 0.2s;
    }

    .close-btn:hover {
      background: #e2e8f0;
      color: #0f172a;
    }

    .type-badge {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 6px;
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .badge-concept { background: #dbeafe; color: #1e40af; }
    .badge-term { background: #e0e7ff; color: #4338ca; }
    .badge-other { background: #f1f5f9; color: #475569; }
    .badge-not_found { background: #fee2e2; color: #991b1b; }

    .sidebar-right-content {
      flex: 1;
      overflow-y: auto;
      padding: 24px;
    }

    .detail-section {
      margin-bottom: 24px;
    }

    .detail-section h4 {
      font-size: 12px;
      font-weight: 600;
      color: #64748b;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .detail-section p {
      font-size: 14px;
      line-height: 1.6;
      color: #334155;
    }

    .alias-badges {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
    }

    .alias-badge {
      padding: 4px 10px;
      background: #f1f5f9;
      border: 1px solid #e2e8f0;
      border-radius: 6px;
      font-size: 13px;
      color: #475569;
    }

    .relationship-card {
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      padding: 16px;
      margin-bottom: 12px;
    }

    .relationship-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 12px;
    }

    .relationship-label {
      font-size: 14px;
      font-weight: 700;
      color: #0f172a;
      text-transform: capitalize;
      letter-spacing: 0.3px;
    }

    .relationship-count {
      font-size: 12px;
      font-weight: 600;
      color: #64748b;
      background: white;
      padding: 2px 8px;
      border-radius: 4px;
      border: 1px solid #e2e8f0;
    }

    .relationship-links {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }

    .relationship-link {
      padding: 8px 12px;
      background: white;
      border: 1px solid #e2e8f0;
      border-radius: 6px;
      font-size: 14px;
      font-weight: 500;
      color: #3b82f6;
      cursor: pointer;
      transition: all 0.2s;
    }

    .relationship-link:hover {
      background: #eff6ff;
      border-color: #3b82f6;
    }

    .metadata-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }

    .metadata-item {
      padding: 12px;
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
    }

    .metadata-label {
      font-size: 11px;
      color: #64748b;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 4px;
    }

    .metadata-value {
      font-size: 13px;
      color: #0f172a;
      font-weight: 500;
    }

    /* Graph Elements */
    .node {
      cursor: pointer;
      stroke: white;
      stroke-width: 3px;
      transition: all 0.2s;
    }

    .node:hover {
      stroke-width: 4px;
      filter: brightness(1.1);
    }

    .node.selected {
      stroke: #3b82f6;
      stroke-width: 5px;
    }

    .node.dimmed {
      opacity: 0.2;
    }

    .node.not-found {
      stroke-dasharray: 5, 5;
      opacity: 0.7;
    }

    .link {
      stroke: #cbd5e1;
      stroke-opacity: 0.85;
      stroke-width: 2px;
      fill: none;
      transition: all 0.2s;
    }

    .link.highlighted {
      stroke: #3b82f6;
      stroke-opacity: 1;
      stroke-width: 3px;
    }

    .link.dimmed {
      opacity: 0.1;
    }

    .link-label {
      font-size: 11px;
      fill: #64748b;
      pointer-events: none;
      text-anchor: middle;
      font-weight: 600;
    }

    .link-label.highlighted {
      fill: #3b82f6;
      font-size: 12px;
    }

    .link-label.dimmed {
      opacity: 0.1;
    }

    .node-icon {
      font-size: 18px;
      pointer-events: none;
      text-anchor: middle;
      dominant-baseline: central;
    }

    .node-label {
      font-size: 12px;
      pointer-events: none;
      text-anchor: middle;
      fill: #0f172a;
      font-weight: 600;
      paint-order: stroke;
      stroke: white;
      stroke-width: 3px;
      stroke-linecap: round;
      stroke-linejoin: round;
    }

    /* Analytics Modal */
    .analytics-modal {
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0, 0, 0, 0.5);
      backdrop-filter: blur(4px);
      display: none;
      align-items: center;
      justify-content: center;
      z-index: 200;
    }

    .analytics-modal.open {
      display: flex;
    }

    .analytics-content {
      width: 90%;
      max-width: 1000px;
      max-height: 80vh;
      background: white;
      border-radius: 16px;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1);
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }

    .analytics-header {
      padding: 24px 32px;
      border-bottom: 1px solid #e2e8f0;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .analytics-header h2 {
      font-size: 20px;
      font-weight: 700;
      color: #0f172a;
    }

    .analytics-body {
      padding: 32px;
      overflow-y: auto;
    }

    .analytics-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 20px;
      margin-bottom: 32px;
    }

    .analytics-card {
      padding: 20px;
      background: linear-gradient(135deg, #f8fafc 0%, #f1f5f9 100%);
      border: 1px solid #e2e8f0;
      border-radius: 12px;
    }

    .analytics-card h4 {
      font-size: 12px;
      font-weight: 600;
      color: #64748b;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 12px;
    }

    .analytics-card .value {
      font-size: 32px;
      font-weight: 700;
      color: #0f172a;
      margin-bottom: 4px;
    }

    .analytics-card .label {
      font-size: 13px;
      color: #64748b;
    }

    .top-terms {
      background: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 12px;
      padding: 20px;
    }

    .top-terms h3 {
      font-size: 14px;
      font-weight: 600;
      color: #0f172a;
      margin-bottom: 16px;
    }

    .top-terms ul {
      list-style: none;
    }

    .top-terms li {
      padding: 12px;
      background: white;
      border: 1px solid #e2e8f0;
      border-radius: 8px;
      margin-bottom: 8px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .term-name {
      font-size: 15px;
      font-weight: 700;
      color: #0f172a;
      letter-spacing: 0.2px;
    }

    .term-connections {
      font-size: 13px;
      font-weight: 600;
      color: #64748b;
      background: #f1f5f9;
      padding: 4px 10px;
      border-radius: 6px;
      border: 1px solid #e2e8f0;
    }
  </style>
</head>
<body>
  <!-- Header -->
  <div class="header">
    <div class="header-left">
      <div class="header-icon">📖</div>
      <div class="header-content">
        <h1>]] .. (book_title or "Book") .. [[ - Glossary Graph</h1>
        <p>Interactive Relationship Visualization</p>
      </div>
    </div>
    <button class="quick-search-btn" onclick="toggleDarkMode()" id="themeToggle">
      <span id="themeIcon">🌙</span>
    </button>
  </div>

  <!-- Main App Container -->
  <div class="app-container">
    <!-- Left Sidebar -->
    <div class="sidebar-left">
      <div class="sidebar-section">
        <h3>Search</h3>
        <input type="text" class="search-input" id="searchBox" placeholder="Search terms...">
      </div>

      <div class="sidebar-section">
        <h3>Layout Type</h3>
        <select class="layout-select" id="layoutSelect" onchange="changeLayout(this.value)">
          <option value="force">Force-Directed</option>
          <option value="tree">Hierarchical</option>
          <option value="circular">Circular</option>
          <option value="radial">Radial</option>
        </select>
      </div>

      <div class="sidebar-section">
        <h3>Filters</h3>
        <div id="filterContainer">
          <!-- Filters will be generated dynamically -->
        </div>
      </div>

      <div class="sidebar-section">
        <h3>Actions</h3>
        <div class="actions-grid">
          <button class="btn" onclick="resetZoom()">Reset View</button>
          <button class="btn" onclick="clearSearch()">Clear Filter</button>
        </div>
        <button class="btn btn-primary btn-full" onclick="toggleAnalytics()">📊 View Analytics</button>
        <div class="actions-grid">
          <button class="btn" onclick="exportPNG()">💾 PNG</button>
          <button class="btn" onclick="exportSVG()">💾 SVG</button>
        </div>
      </div>

      <div class="sidebar-section">
        <h3>Legend</h3>
        <div id="legendContainer">
          <!-- Legend will be generated dynamically -->
        </div>
      </div>
    </div>

    <!-- Center Area -->
    <div class="center-area">
      <div id="graph-container">
        <svg id="graph"></svg>

        <!-- Zoom Controls -->
        <div class="zoom-controls">
          <button class="zoom-btn" onclick="zoomIn()" title="Zoom In">+</button>
          <button class="zoom-btn" onclick="zoomOut()" title="Zoom Out">−</button>
          <button class="zoom-btn" onclick="resetZoom()" title="Reset Zoom">⊙</button>
        </div>

        <!-- Zoom Indicator -->
        <div class="zoom-indicator" id="zoomIndicator">Zoom: 100%</div>
      </div>

      <!-- Canvas Footer with Stats -->
      <div class="canvas-footer">
        <div class="stat-item">
          <div class="stat-label">Total Terms</div>
          <div class="stat-value" id="totalTerms">0</div>
        </div>
        <div class="stat-item">
          <div class="stat-label">Relationships</div>
          <div class="stat-value" id="totalRelationships">0</div>
        </div>
        <div class="stat-item">
          <div class="stat-label">Visible</div>
          <div class="stat-value" id="visibleTerms">0</div>
        </div>
        <div class="stat-item">
          <div class="stat-label">Avg. Connections</div>
          <div class="stat-value" id="avgConnections">0</div>
        </div>
      </div>
    </div>

    <!-- Right Sidebar -->
    <div class="sidebar-right" id="sidebarRight">
      <div class="sidebar-right-header">
        <div>
          <h2 id="detailTitle">Annotation Details</h2>
          <div id="detailBadge"></div>
        </div>
        <button class="close-btn" onclick="closeSidebar()">×</button>
      </div>

      <div class="sidebar-right-content" id="detailContent">
        <p style="color: #64748b; text-align: center; padding: 60px 20px;">
          Select a node to view details
        </p>
      </div>
    </div>
  </div>

  <!-- Analytics Modal -->
  <div class="analytics-modal" id="analyticsModal" onclick="closeAnalytics(event)">
    <div class="analytics-content" onclick="event.stopPropagation()">
      <div class="analytics-header">
        <h2>📊 Network Analytics</h2>
        <button class="close-btn" onclick="closeAnalytics()">×</button>
      </div>
      <div class="analytics-body" id="analyticsBody">
        <!-- Analytics content will be inserted here -->
      </div>
    </div>
  </div>

  <script>
    const allNodes = ]] .. nodes_json .. [[;
    const allLinks = ]] .. links_json .. [[;

    console.log('Loaded nodes:', allNodes.length);
    console.log('Loaded links:', allLinks.length);
    console.log('First node:', allNodes[0]);

    // Type configuration
    const typeConfig = {
      character: { icon: "👤", color: "#3b82f6" },
      place: { icon: "📍", color: "#e67e22" },
      concept: { icon: "💡", color: "#2ecc71" },
      organization: { icon: "🏛️", color: "#9b59b6" },
      object: { icon: "⚔️", color: "#1abc9c" },
      event: { icon: "⚡", color: "#f1c40f" },
      foreign_word: { icon: "🌐", color: "#27ae60" },
      term: { icon: "📖", color: "#8b5cf6" },
      other: { icon: "📝", color: "#64748b" },
      not_found: { icon: "❓", color: "#cbd5e1" }
    };

    // Get unique types from data
    const uniqueTypes = new Set(allNodes.map(n => n.type));
    console.log('Unique types:', Array.from(uniqueTypes));

    // State
    let nodes = JSON.parse(JSON.stringify(allNodes));
    let links = JSON.parse(JSON.stringify(allLinks));
    let activeFilters = new Set(uniqueTypes); // Initialize with all types
    let searchTerm = "";
    let currentLayout = "force";
    let selectedNode = null;
    let currentZoom = 1;

    // Setup SVG
    const container = document.getElementById("graph-container");
    const width = container.clientWidth;
    const height = container.clientHeight - 70; // Account for footer

    console.log('SVG dimensions:', width, 'x', height);

    const svg = d3.select("#graph")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height]);

    const g = svg.append("g");

    // Zoom behavior
    const zoom = d3.zoom()
      .scaleExtent([0.1, 4])
      .on("zoom", (event) => {
        g.attr("transform", event.transform);
        currentZoom = event.transform.k;
        updateZoomIndicator();
      });

    svg.call(zoom);

    function updateZoomIndicator() {
      document.getElementById('zoomIndicator').textContent = 'Zoom: ' + Math.round(currentZoom * 100) + '%';
    }

    function zoomIn() {
      svg.transition().duration(300).call(zoom.scaleBy, 1.3);
    }

    function zoomOut() {
      svg.transition().duration(300).call(zoom.scaleBy, 0.7);
    }

    function resetZoom() {
      svg.transition().duration(750).call(
        zoom.transform,
        d3.zoomIdentity
      );
    }

    // Dark mode toggle
    function toggleDarkMode() {
      const body = document.body;
      const themeIcon = document.getElementById('themeIcon');

      if (body.classList.contains('dark')) {
        body.classList.remove('dark');
        themeIcon.textContent = '🌙';
        localStorage.setItem('glossaryTheme', 'light');
      } else {
        body.classList.add('dark');
        themeIcon.textContent = '☀️';
        localStorage.setItem('glossaryTheme', 'dark');
      }
    }

    // Load saved theme
    function loadTheme() {
      const savedTheme = localStorage.getItem('glossaryTheme');
      const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
      const theme = savedTheme || (prefersDark ? 'dark' : 'light');

      if (theme === 'dark') {
        document.body.classList.add('dark');
        document.getElementById('themeIcon').textContent = '☀️';
      }
    }

    // Sidebar management
    function openSidebar(nodeData) {
      selectedNode = nodeData;
      const sidebar = document.getElementById('sidebarRight');
      const title = document.getElementById('detailTitle');
      const badge = document.getElementById('detailBadge');
      const content = document.getElementById('detailContent');

      title.textContent = nodeData.label;

      const badgeClass = 'badge-' + nodeData.type;
      badge.innerHTML = '<span class="type-badge ' + badgeClass + '">' + nodeData.type + '</span>';

      let html = '';

      // Aliases
      if (nodeData.aliases && nodeData.aliases.length > 0) {
        html += '<div class="detail-section">';
        html += '<h4>🏷️ ALIASES</h4>';
        html += '<div class="alias-badges">';
        nodeData.aliases.forEach(alias => {
          html += '<span class="alias-badge">' + alias + '</span>';
        });
        html += '</div></div>';
      }

      // Definition
      html += '<div class="detail-section">';
      html += '<h4>📄 DEFINITION</h4>';
      html += '<p>' + (nodeData.definition || 'No definition available') + '</p>';
      html += '</div>';

      // Relationships
      if (nodeData.relationships && Object.keys(nodeData.relationships).length > 0) {
        html += '<div class="detail-section">';
        html += '<h4>🔗 RELATIONSHIPS</h4>';

        for (const [label, terms] of Object.entries(nodeData.relationships)) {
          html += '<div class="relationship-card">';
          html += '<div class="relationship-header">';
          html += '<div class="relationship-label">' + label.replace(/_/g, ' ') + '</div>';
          html += '<div class="relationship-count">' + terms.length + '</div>';
          html += '</div>';
          html += '<div class="relationship-links">';
          terms.forEach(term => {
            html += '<div class="relationship-link" onclick="navigateToTerm(\'' + term + '\')">' + term + '</div>';
          });
          html += '</div></div>';
        }
        html += '</div>';
      }

      // Metadata
      const connections = links.filter(l =>
        (l.source.id || l.source) === nodeData.id ||
        (l.target.id || l.target) === nodeData.id
      );

      html += '<div class="detail-section">';
      html += '<h4>📊 METADATA</h4>';
      html += '<div class="metadata-grid">';
      html += '<div class="metadata-item"><div class="metadata-label">Created</div><div class="metadata-value">N/A</div></div>';
      html += '<div class="metadata-item"><div class="metadata-label">Modified</div><div class="metadata-value">N/A</div></div>';
      html += '<div class="metadata-item"><div class="metadata-label">References</div><div class="metadata-value">' + connections.length + '</div></div>';
      html += '<div class="metadata-item"><div class="metadata-label">Status</div><div class="metadata-value">' + (nodeData.exists ? 'Active' : 'Missing') + '</div></div>';
      html += '</div></div>';

      content.innerHTML = html;
      sidebar.classList.add('open');

      // Highlight node
      if (node) {
        node.classed('selected', n => n.id === nodeData.id);
      }
    }

    function closeSidebar() {
      selectedNode = null;
      const sidebar = document.getElementById('sidebarRight');
      sidebar.classList.remove('open');
      if (node) {
        node.classed('selected', false);
      }
      clearHighlight();
    }

    function navigateToTerm(termName) {
      const targetNode = allNodes.find(n => n.label === termName);
      if (targetNode) {
        openSidebar(targetNode);
        highlightNeighbors(targetNode);
      }
    }

    // Analytics
    function toggleAnalytics() {
      const modal = document.getElementById('analyticsModal');
      if (!modal.classList.contains('open')) {
        calculateAnalytics();
      }
      modal.classList.add('open');
    }

    function closeAnalytics(event) {
      const modal = document.getElementById('analyticsModal');
      if (!event || event.target === modal) {
        modal.classList.remove('open');
      }
    }

    function calculateAnalytics() {
      const body = document.getElementById('analyticsBody');

      // Calculate degrees
      const degrees = {};
      allNodes.forEach(n => degrees[n.id] = 0);
      allLinks.forEach(l => {
        const sourceId = l.source.id || l.source;
        const targetId = l.target.id || l.target;
        degrees[sourceId] = (degrees[sourceId] || 0) + 1;
        degrees[targetId] = (degrees[targetId] || 0) + 1;
      });

      const sortedNodes = Object.entries(degrees)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 10);

      const n = allNodes.length;
      const maxLinks = (n * (n - 1)) / 2;
      const density = maxLinks > 0 ? (allLinks.length / maxLinks * 100).toFixed(1) : 0;
      const avgDegree = allLinks.length > 0 ? (allLinks.length * 2 / allNodes.length).toFixed(1) : 0;
      const isolated = Object.values(degrees).filter(d => d === 0).length;

      let html = '<div class="analytics-grid">';
      html += '<div class="analytics-card"><h4>Graph Density</h4><div class="value">' + density + '%</div><div class="label">Connection saturation</div></div>';
      html += '<div class="analytics-card"><h4>Avg Degree</h4><div class="value">' + avgDegree + '</div><div class="label">Connections per term</div></div>';
      html += '<div class="analytics-card"><h4>Isolated Terms</h4><div class="value">' + isolated + '</div><div class="label">Terms without links</div></div>';
      html += '<div class="analytics-card"><h4>Network Size</h4><div class="value">' + allNodes.length + '</div><div class="label">Total nodes</div></div>';
      html += '</div>';

      html += '<div class="top-terms"><h3>🏆 Most Connected Terms</h3><ul>';
      sortedNodes.forEach(([id, degree]) => {
        const node = allNodes.find(n => n.id === id);
        if (node) {
          html += '<li><span class="term-name">' + node.label + '</span><span class="term-connections">' + degree + ' connections</span></li>';
        }
      });
      html += '</ul></div>';

      body.innerHTML = html;
    }

    // Export functions
    function exportSVG() {
      const svgElement = document.getElementById('graph');
      const serializer = new XMLSerializer();
      let source = serializer.serializeToString(svgElement);
      source = '<?xml version="1.0" standalone="no"?>\\r\\n' + source;

      const blob = new Blob([source], {type: "image/svg+xml;charset=utf-8"});
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = 'glossary-graph.svg';
      link.click();
      URL.revokeObjectURL(url);
    }

    function exportPNG() {
      const svgElement = document.getElementById('graph');
      const serializer = new XMLSerializer();
      const source = serializer.serializeToString(svgElement);

      const img = new Image();
      const blob = new Blob([source], {type: 'image/svg+xml;charset=utf-8'});
      const url = URL.createObjectURL(blob);

      img.onload = function() {
        const canvas = document.createElement('canvas');
        canvas.width = svgElement.getAttribute('width');
        canvas.height = svgElement.getAttribute('height');
        const ctx = canvas.getContext('2d');

        ctx.fillStyle = 'white';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0);
        URL.revokeObjectURL(url);

        canvas.toBlob(function(blob) {
          const url = URL.createObjectURL(blob);
          const link = document.createElement('a');
          link.href = url;
          link.download = 'glossary-graph.png';
          link.click();
          URL.revokeObjectURL(url);
        });
      };

      img.src = url;
    }

    // Search and filters
    const searchBox = document.getElementById("searchBox");
    searchBox.addEventListener("input", (e) => {
      searchTerm = e.target.value.toLowerCase();
      updateGraph();
    });

    function clearSearch() {
      searchBox.value = "";
      searchTerm = "";
      updateGraph();
    }

    function toggleTypeFilter(type) {
      const checkbox = document.getElementById('filter-' + type);
      if (activeFilters.has(type)) {
        activeFilters.delete(type);
      } else {
        activeFilters.add(type);
      }
      updateGraph();
    }

    function getFilteredData() {
      let filteredNodes = allNodes.filter(n => {
        const typeMatch = activeFilters.has(n.type);
        const searchMatch = searchTerm === "" ||
          n.label.toLowerCase().includes(searchTerm) ||
          (n.definition && n.definition.toLowerCase().includes(searchTerm)) ||
          (n.aliases && n.aliases.some(a => a.toLowerCase().includes(searchTerm)));
        return typeMatch && searchMatch;
      });

      const nodeIds = new Set(filteredNodes.map(n => n.id));

      let filteredLinks = allLinks.filter(l =>
        nodeIds.has(l.source.id || l.source) &&
        nodeIds.has(l.target.id || l.target)
      );

      return { nodes: filteredNodes, links: filteredLinks };
    }

    // Layout functions
    function getForceLayout() {
      return d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(d => d.id).distance(300))
        .force("charge", d3.forceManyBody().strength(-1000))
        .force("center", d3.forceCenter(width / 2, height / 2))
        .force("collision", d3.forceCollide().radius(100));
    }

    function getRadialLayout() {
      return d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(d => d.id).distance(320))
        .force("charge", d3.forceManyBody().strength(-1100))
        .force("r", d3.forceRadial(600, width / 2, height / 2).strength(0.5))
        .force("collision", d3.forceCollide().radius(110));
    }

    function getCircularLayout() {
      const radius = Math.min(width, height) / 2 - 60;
      const angleStep = (2 * Math.PI) / nodes.length;

      nodes.forEach((node, i) => {
        const angle = i * angleStep;
        node.fx = width / 2 + radius * Math.cos(angle);
        node.fy = height / 2 + radius * Math.sin(angle);
      });

      return d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(d => d.id).distance(150))
        .force("charge", d3.forceManyBody().strength(-200));
    }

    function getTreeLayout() {
      nodes.forEach(node => {
        node.fx = null;
        node.fy = null;
      });

      return d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(d => d.id).distance(320))
        .force("charge", d3.forceManyBody().strength(-900))
        .force("x", d3.forceX(width / 2).strength(0.07))
        .force("y", d3.forceY(height / 2).strength(0.07))
        .force("collision", d3.forceCollide().radius(100));
    }

    function changeLayout(layoutType) {
      currentLayout = layoutType;
      updateGraph();
    }

    // Simulation
    let simulation;
    let link, linkLabel, node, nodeIcon, nodeLabel;

    function updateGraph() {
      try {
        console.log('updateGraph called');
        const filtered = getFilteredData();
        nodes = JSON.parse(JSON.stringify(filtered.nodes));
        links = JSON.parse(JSON.stringify(filtered.links));

        console.log('Filtered nodes:', nodes.length, 'links:', links.length);

      // Update stats
      document.getElementById("totalTerms").textContent = allNodes.length;
      document.getElementById("totalRelationships").textContent = allLinks.length;
      document.getElementById("visibleTerms").textContent = nodes.length;
      const avgConn = nodes.length > 0 ? (links.length * 2 / nodes.length).toFixed(1) : 0;
      document.getElementById("avgConnections").textContent = avgConn;

      // Clear existing
      g.selectAll("*").remove();

      if (nodes.length === 0) {
        console.warn('No nodes to display!');
        g.append("text")
          .attr("x", width / 2)
          .attr("y", height / 2)
          .attr("text-anchor", "middle")
          .attr("fill", "#64748b")
          .attr("font-size", "16px")
          .text("No terms match the current filters");
        return;
      }

      console.log('Creating simulation with layout:', currentLayout);

      // Create simulation
      switch (currentLayout) {
        case 'radial':
          simulation = getRadialLayout();
          break;
        case 'circular':
          simulation = getCircularLayout();
          break;
        case 'tree':
          simulation = getTreeLayout();
          break;
        default:
          simulation = getForceLayout();
      }

      // Create links
      link = g.append("g")
        .selectAll("path")
        .data(links)
        .join("path")
        .attr("class", "link");

      // Create link labels
      linkLabel = g.append("g")
        .selectAll("text")
        .data(links)
        .join("text")
        .attr("class", "link-label")
        .text(d => d.label.replace(/_/g, " "));

      // Create node groups
      const nodeGroup = g.append("g")
        .selectAll("g")
        .data(nodes)
        .join("g")
        .call(d3.drag()
          .on("start", dragstarted)
          .on("drag", dragged)
          .on("end", dragended));

      // Create node circles
      node = nodeGroup.append("circle")
        .attr("class", d => d.type === "not_found" ? "node not-found" : "node")
        .attr("r", 24)
        .attr("fill", d => typeConfig[d.type]?.color || typeConfig.other.color);

      // Create node icons
      nodeIcon = nodeGroup.append("text")
        .attr("class", "node-icon")
        .text(d => typeConfig[d.type]?.icon || typeConfig.other.icon);

      // Create node labels
      nodeLabel = nodeGroup.append("text")
        .attr("class", "node-label")
        .attr("dy", 38)
        .text(d => d.label);

      // Event handlers
      nodeGroup.on("mouseover", (event, d) => {
        if (selectedNode && selectedNode.id === d.id) return;
        highlightNeighbors(d);
      })
      .on("mouseout", () => {
        if (!selectedNode) {
          clearHighlight();
        }
      })
      .on("click", (event, d) => {
        event.stopPropagation();
        openSidebar(d);
      });

      svg.on("click", () => {
        closeSidebar();
      });

      // Update positions on tick
      simulation.on("tick", () => {
        link.attr("d", d => {
          const dx = d.target.x - d.source.x;
          const dy = d.target.y - d.source.y;
          const dr = Math.sqrt(dx * dx + dy * dy);
          return `M${d.source.x},${d.source.y}A${dr},${dr} 0 0,1 ${d.target.x},${d.target.y}`;
        });

        // Calculate label positions with offset for duplicate links
        const linkPairs = new Map();
        links.forEach(link => {
          const sourceId = link.source.id || link.source;
          const targetId = link.target.id || link.target;
          const pairKey = sourceId < targetId ? `${sourceId}-${targetId}` : `${targetId}-${sourceId}`;

          if (!linkPairs.has(pairKey)) {
            linkPairs.set(pairKey, []);
          }
          linkPairs.get(pairKey).push(link);
        });

        linkLabel
          .attr("x", d => (d.source.x + d.target.x) / 2)
          .attr("y", d => {
            const sourceId = d.source.id || d.source;
            const targetId = d.target.id || d.target;
            const pairKey = sourceId < targetId ? `${sourceId}-${targetId}` : `${targetId}-${sourceId}`;
            const pairLinks = linkPairs.get(pairKey);

            if (pairLinks.length === 1) {
              return (d.source.y + d.target.y) / 2;
            }

            // Multiple links between same nodes - apply offset
            const index = pairLinks.indexOf(d);
            const totalLinks = pairLinks.length;
            const offsetSpacing = 14;

            // Calculate offset: center the group, then space them
            const baseY = (d.source.y + d.target.y) / 2;
            const totalOffset = (totalLinks - 1) * offsetSpacing;
            const startOffset = -totalOffset / 2;

            return baseY + startOffset + (index * offsetSpacing);
          });

        nodeGroup.attr("transform", d => `translate(${d.x},${d.y})`);
      });

        console.log('Graph updated successfully');
      } catch (error) {
        console.error('Error in updateGraph:', error);
        alert('Error updating graph: ' + error.message);
      }
    }

    function highlightNeighbors(d) {
      const connectedNodes = new Set([d.id]);
      const connectedLinks = new Set();

      links.forEach(l => {
        const sourceId = l.source.id || l.source;
        const targetId = l.target.id || l.target;

        if (sourceId === d.id) {
          connectedNodes.add(targetId);
          connectedLinks.add(l);
        } else if (targetId === d.id) {
          connectedNodes.add(sourceId);
          connectedLinks.add(l);
        }
      });

      node.classed("dimmed", n => !connectedNodes.has(n.id));
      link.classed("highlighted", l => connectedLinks.has(l))
          .classed("dimmed", l => !connectedLinks.has(l));
      linkLabel.classed("highlighted", l => connectedLinks.has(l))
          .classed("dimmed", l => !connectedLinks.has(l));
    }

    function clearHighlight() {
      node.classed("dimmed", false);
      link.classed("highlighted", false).classed("dimmed", false);
      linkLabel.classed("highlighted", false).classed("dimmed", false);
    }

    function dragstarted(event, d) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      d.fx = d.x;
      d.fy = d.y;
    }

    function dragged(event, d) {
      d.fx = event.x;
      d.fy = event.y;
    }

    function dragended(event, d) {
      if (!event.active) simulation.alphaTarget(0);
      if (currentLayout !== 'circular') {
        d.fx = null;
        d.fy = null;
      }
    }

    // Create dynamic filters
    function createFilters() {
      const filterContainer = document.getElementById('filterContainer');
      filterContainer.innerHTML = '';

      uniqueTypes.forEach(type => {
        const config = typeConfig[type] || typeConfig.other;
        const div = document.createElement('div');
        div.className = 'filter-checkbox';

        const checkbox = document.createElement('input');
        checkbox.type = 'checkbox';
        checkbox.id = 'filter-' + type;
        checkbox.checked = true;
        checkbox.onchange = () => toggleTypeFilter(type);

        const label = document.createElement('label');
        label.htmlFor = 'filter-' + type;
        label.textContent = 'Show "' + type + '" type';

        div.appendChild(checkbox);
        div.appendChild(label);
        filterContainer.appendChild(div);
      });
    }

    // Create dynamic legend
    function createLegend() {
      const legendContainer = document.getElementById('legendContainer');
      legendContainer.innerHTML = '';

      uniqueTypes.forEach(type => {
        const config = typeConfig[type] || typeConfig.other;
        const div = document.createElement('div');
        div.className = 'legend-item';

        const dot = document.createElement('div');
        dot.className = 'legend-dot';
        dot.style.background = config.color;
        if (type === 'not_found') {
          dot.style.borderStyle = 'dashed';
        }

        const label = document.createElement('div');
        label.className = 'legend-label';
        label.textContent = config.icon + ' ' + type.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());

        div.appendChild(dot);
        div.appendChild(label);
        legendContainer.appendChild(div);
      });
    }

    // Initialize
    try {
      loadTheme();
      createFilters();
      createLegend();
      console.log('Starting initial render...');
      updateGraph();
      console.log('Initial render complete');
    } catch (error) {
      console.error('Error during initialization:', error);
      alert('Error loading graph: ' + error.message);
    }

    // Window resize
    window.addEventListener("resize", () => {
      const newWidth = container.clientWidth;
      const newHeight = container.clientHeight - 70;
      svg.attr("width", newWidth).attr("height", newHeight);
      svg.attr("viewBox", [0, 0, newWidth, newHeight]);
      if (simulation) {
        simulation.force("center", d3.forceCenter(newWidth / 2, newHeight / 2));
        simulation.alpha(0.3).restart();
      }
    });
  </script>
</body>
</html>
]]

  return html
end

return M
