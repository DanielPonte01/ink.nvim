local M = {}

-- Convert glossary entries to graph data (nodes and links)
local function convert_to_graph_data(entries)
  local nodes = {}
  local links = {}
  local entries_map = {}
  local alias_to_term = {}  -- Maps alias -> main term
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
      type = entry.type,
      definition = entry.definition or "",
      aliases = entry.aliases or {},
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
        exists = false
      })
    end
  end

  -- Create links from relationships (resolving aliases to main terms)
  for _, entry in ipairs(entries) do
    if entry.relationships then
      for label, terms in pairs(entry.relationships) do
        for _, term_name in ipairs(terms) do
          local resolved_target = resolve_term(term_name)
          table.insert(links, {
            source = entry.term,
            target = resolved_target,
            label = label
          })
        end
      end
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
    :root {
      --bg-primary: #f8f9fa;
      --bg-secondary: white;
      --text-primary: #2c3e50;
      --text-secondary: #7f8c8d;
      --text-muted: #95a5a6;
      --border-color: #e0e0e0;
      --shadow: rgba(0,0,0,0.1);
      --shadow-hover: rgba(0,0,0,0.15);
      --link-color: #95a5a6;
      --link-highlight: #e74c3c;
      --input-bg: white;
      --input-border: #e0e0e0;
      --input-focus: #3498db;
      --button-bg: #3498db;
      --button-hover: #2980b9;
      --tooltip-bg: white;
      --tooltip-border: #ddd;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg-primary: #1a1a1a;
        --bg-secondary: #2d2d2d;
        --text-primary: #e0e0e0;
        --text-secondary: #b0b0b0;
        --text-muted: #808080;
        --border-color: #404040;
        --shadow: rgba(0,0,0,0.3);
        --shadow-hover: rgba(0,0,0,0.5);
        --link-color: #808080;
        --link-highlight: #e74c3c;
        --input-bg: #3d3d3d;
        --input-border: #505050;
        --input-focus: #3498db;
        --button-bg: #3498db;
        --button-hover: #2980b9;
        --tooltip-bg: #3d3d3d;
        --tooltip-border: #505050;
      }
    }

    body.dark {
      --bg-primary: #1a1a1a;
      --bg-secondary: #2d2d2d;
      --text-primary: #e0e0e0;
      --text-secondary: #b0b0b0;
      --text-muted: #808080;
      --border-color: #404040;
      --shadow: rgba(0,0,0,0.3);
      --shadow-hover: rgba(0,0,0,0.5);
      --link-color: #808080;
      --link-highlight: #e74c3c;
      --input-bg: #3d3d3d;
      --input-border: #505050;
      --input-focus: #3498db;
      --button-bg: #3498db;
      --button-hover: #2980b9;
      --tooltip-bg: #3d3d3d;
      --tooltip-border: #505050;
    }

    body.light {
      --bg-primary: #f8f9fa;
      --bg-secondary: white;
      --text-primary: #2c3e50;
      --text-secondary: #7f8c8d;
      --text-muted: #95a5a6;
      --border-color: #e0e0e0;
      --shadow: rgba(0,0,0,0.1);
      --shadow-hover: rgba(0,0,0,0.15);
      --link-color: #95a5a6;
      --link-highlight: #e74c3c;
      --input-bg: white;
      --input-border: #e0e0e0;
      --input-focus: #3498db;
      --button-bg: #3498db;
      --button-hover: #2980b9;
      --tooltip-bg: white;
      --tooltip-border: #ddd;
    }

    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }

    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      background: var(--bg-primary);
      padding: 20px;
      transition: background 0.3s ease;
    }

    .header {
      background: var(--bg-secondary);
      padding: 20px;
      border-radius: 8px;
      box-shadow: 0 2px 4px var(--shadow);
      margin-bottom: 20px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .header-content {
      flex: 1;
    }

    h1 {
      color: var(--text-primary);
      margin-bottom: 8px;
      font-size: 24px;
    }

    .subtitle {
      color: var(--text-secondary);
      font-size: 14px;
    }

    .theme-toggle {
      padding: 8px 12px;
      background: var(--button-bg);
      color: white;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 18px;
      transition: background 0.2s;
      display: flex;
      align-items: center;
      gap: 5px;
    }

    .theme-toggle:hover {
      background: var(--button-hover);
    }

    .controls {
      background: var(--bg-secondary);
      padding: 20px;
      border-radius: 8px;
      box-shadow: 0 2px 4px var(--shadow);
      margin-bottom: 20px;
      display: flex;
      gap: 20px;
      flex-wrap: wrap;
      align-items: center;
    }

    .control-group {
      display: flex;
      gap: 10px;
      align-items: center;
    }

    .control-label {
      font-weight: 600;
      color: var(--text-primary);
      font-size: 14px;
    }

    .search-box {
      padding: 8px 12px;
      border: 2px solid var(--input-border);
      background: var(--input-bg);
      color: var(--text-primary);
      border-radius: 4px;
      font-size: 14px;
      width: 250px;
      transition: border-color 0.2s;
    }

    .search-box:focus {
      outline: none;
      border-color: var(--input-focus);
    }

    .filter-group {
      display: flex;
      gap: 15px;
      flex-wrap: wrap;
    }

    .filter-item {
      display: flex;
      align-items: center;
      gap: 5px;
      font-size: 13px;
      color: var(--text-primary);
    }

    .filter-item input[type="checkbox"] {
      cursor: pointer;
    }

    .filter-item label {
      cursor: pointer;
      user-select: none;
      display: flex;
      align-items: center;
      gap: 4px;
    }

    button {
      padding: 8px 16px;
      background: var(--button-bg);
      color: white;
      border: none;
      border-radius: 4px;
      cursor: pointer;
      font-size: 14px;
      font-weight: 500;
      transition: background 0.2s;
    }

    button:hover {
      background: var(--button-hover);
    }

    button:active {
      transform: translateY(1px);
    }

    #graph-container {
      background: var(--bg-secondary);
      border-radius: 8px;
      box-shadow: 0 2px 4px var(--shadow);
      overflow: hidden;
    }

    #graph {
      width: 100%;
      height: calc(100vh - 280px);
      min-height: 500px;
    }

    .node {
      cursor: pointer;
      stroke: #fff;
      stroke-width: 2px;
      transition: all 0.2s;
    }

    .node.highlighted {
      stroke: #e74c3c;
      stroke-width: 4px;
    }

    .node.dimmed {
      opacity: 0.2;
    }

    .node.not-found {
      stroke-dasharray: 5, 5;
      opacity: 0.7;
    }

    .link {
      stroke: var(--link-color);
      stroke-opacity: 0.6;
      stroke-width: 1.5px;
      fill: none;
    }

    .link.highlighted {
      stroke: var(--link-highlight);
      stroke-opacity: 1;
      stroke-width: 3px;
    }

    .link.dimmed {
      opacity: 0.1;
    }

    .link-label {
      font-size: 10px;
      fill: var(--text-secondary);
      pointer-events: none;
      text-anchor: middle;
      font-weight: 500;
    }

    .link-label.highlighted {
      fill: var(--link-highlight);
      font-size: 11px;
      font-weight: 600;
    }

    .node-icon {
      font-size: 16px;
      pointer-events: none;
      text-anchor: middle;
      dominant-baseline: central;
    }

    .node-label {
      font-size: 11px;
      pointer-events: none;
      text-anchor: middle;
      fill: var(--text-primary);
      font-weight: 600;
    }

    .tooltip {
      position: absolute;
      text-align: left;
      padding: 12px;
      font-size: 13px;
      background: var(--tooltip-bg);
      border: 1px solid var(--tooltip-border);
      border-radius: 6px;
      pointer-events: none;
      opacity: 0;
      box-shadow: 0 4px 12px var(--shadow-hover);
      max-width: 350px;
      z-index: 100;
      transition: opacity 0.2s;
    }

    .tooltip h3 {
      margin: 0 0 8px 0;
      color: var(--text-primary);
      font-size: 15px;
      border-bottom: 2px solid var(--input-focus);
      padding-bottom: 4px;
    }

    .tooltip p {
      margin: 6px 0;
      color: var(--text-secondary);
      line-height: 1.4;
    }

    .tooltip strong {
      color: var(--text-primary);
    }

    .stats {
      background: var(--bg-secondary);
      padding: 15px;
      border-radius: 8px;
      box-shadow: 0 2px 4px var(--shadow);
      margin-top: 20px;
      display: flex;
      gap: 30px;
      justify-content: center;
      font-size: 13px;
      color: var(--text-secondary);
    }

    .stat-item {
      display: flex;
      align-items: center;
      gap: 5px;
    }

    .stat-value {
      font-weight: 600;
      color: var(--text-primary);
    }
  </style>
</head>
<body>
  <div class="header">
    <div class="header-content">
      <h1>]] .. (book_title or "Book") .. [[ - Glossary Graph</h1>
      <div class="subtitle">Interactive relationship visualization • Drag nodes • Scroll to zoom</div>
    </div>
    <button class="theme-toggle" onclick="toggleTheme()" aria-label="Toggle theme">
      <span id="themeIcon">🌙</span>
    </button>
  </div>

  <div class="controls">
    <div class="control-group">
      <span class="control-label">Search:</span>
      <input type="text" class="search-box" id="searchBox" placeholder="Type to search terms...">
    </div>

    <div class="control-group">
      <span class="control-label">Filter by Type:</span>
      <div class="filter-group" id="typeFilters"></div>
    </div>

    <button onclick="resetZoom()">Reset View</button>
    <button onclick="clearSearch()">Clear Search</button>
  </div>

  <div id="graph-container">
    <svg id="graph"></svg>
  </div>

  <div class="tooltip"></div>

  <div class="stats">
    <div class="stat-item">
      <span>Total Terms:</span>
      <span class="stat-value" id="totalTerms">0</span>
    </div>
    <div class="stat-item">
      <span>Relationships:</span>
      <span class="stat-value" id="totalRelationships">0</span>
    </div>
    <div class="stat-item">
      <span>Visible:</span>
      <span class="stat-value" id="visibleTerms">0</span>
    </div>
  </div>

  <script>
    // Theme management
    function getPreferredTheme() {
      const savedTheme = localStorage.getItem('glossaryTheme');
      if (savedTheme) {
        return savedTheme;
      }
      return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }

    function setTheme(theme) {
      document.body.classList.remove('light', 'dark');
      document.body.classList.add(theme);
      localStorage.setItem('glossaryTheme', theme);

      const themeIcon = document.getElementById('themeIcon');
      themeIcon.textContent = theme === 'dark' ? '☀️' : '🌙';
    }

    function toggleTheme() {
      const currentTheme = document.body.classList.contains('dark') ? 'dark' : 'light';
      const newTheme = currentTheme === 'dark' ? 'light' : 'dark';
      setTheme(newTheme);
    }

    // Apply theme on load
    document.addEventListener('DOMContentLoaded', function() {
      setTheme(getPreferredTheme());
    });

    // Listen for system theme changes
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function(e) {
      if (!localStorage.getItem('glossaryTheme')) {
        setTheme(e.matches ? 'dark' : 'light');
      }
    });

    const allNodes = ]] .. nodes_json .. [[;
    const allLinks = ]] .. links_json .. [[;

    // Type icons and colors
    const typeConfig = {
      character: { icon: "👤", color: "#3498db" },
      place: { icon: "📍", color: "#e67e22" },
      concept: { icon: "💡", color: "#2ecc71" },
      organization: { icon: "🏛️", color: "#9b59b6" },
      object: { icon: "⚔️", color: "#1abc9c" },
      event: { icon: "⚡", color: "#f1c40f" },
      foreign_word: { icon: "🌐", color: "#27ae60" },
      other: { icon: "📝", color: "#95a5a6" },
      not_found: { icon: "❓", color: "#bdc3c7" }
    };

    // State
    let nodes = JSON.parse(JSON.stringify(allNodes));
    let links = JSON.parse(JSON.stringify(allLinks));
    let activeFilters = new Set(Object.keys(typeConfig));
    let searchTerm = "";

    // Set up SVG
    const container = document.getElementById("graph-container");
    const width = container.clientWidth;
    const height = container.clientHeight;

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
      });

    svg.call(zoom);

    function resetZoom() {
      svg.transition().duration(750).call(
        zoom.transform,
        d3.zoomIdentity
      );
    }

    // Create type filters
    const typeFiltersContainer = document.getElementById("typeFilters");
    Object.entries(typeConfig).forEach(([type, config]) => {
      const div = document.createElement("div");
      div.className = "filter-item";

      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.id = `filter-${type}`;
      checkbox.checked = true;
      checkbox.onchange = () => toggleTypeFilter(type);

      const label = document.createElement("label");
      label.htmlFor = `filter-${type}`;
      label.innerHTML = `<span>${config.icon}</span> ${type.replace(/_/g, " ")}`;

      div.appendChild(checkbox);
      div.appendChild(label);
      typeFiltersContainer.appendChild(div);
    });

    // Search functionality
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
      if (activeFilters.has(type)) {
        activeFilters.delete(type);
      } else {
        activeFilters.add(type);
      }
      updateGraph();
    }

    // Filter nodes and links based on active filters and search
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

    // Simulation
    let simulation;
    let link, linkLabel, node, nodeIcon, nodeLabel;

    function updateGraph() {
      const filtered = getFilteredData();
      nodes = JSON.parse(JSON.stringify(filtered.nodes));
      links = JSON.parse(JSON.stringify(filtered.links));

      // Update stats
      document.getElementById("totalTerms").textContent = allNodes.length;
      document.getElementById("totalRelationships").textContent = allLinks.length;
      document.getElementById("visibleTerms").textContent = nodes.length;

      // Clear existing
      g.selectAll("*").remove();

      if (nodes.length === 0) {
        g.append("text")
          .attr("x", width / 2)
          .attr("y", height / 2)
          .attr("text-anchor", "middle")
          .attr("fill", "#95a5a6")
          .attr("font-size", "16px")
          .text("No terms match the current filters");
        return;
      }

      // Create simulation
      simulation = d3.forceSimulation(nodes)
        .force("link", d3.forceLink(links).id(d => d.id).distance(120))
        .force("charge", d3.forceManyBody().strength(-400))
        .force("center", d3.forceCenter(width / 2, height / 2))
        .force("collision", d3.forceCollide().radius(50));

      // Create links
      link = g.append("g")
        .selectAll("path")
        .data(links)
        .join("path")
        .attr("class", "link")
        .attr("stroke", "#95a5a6");

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
        .attr("r", 20)
        .attr("fill", d => typeConfig[d.type]?.color || typeConfig.other.color);

      // Create node icons
      nodeIcon = nodeGroup.append("text")
        .attr("class", "node-icon")
        .text(d => typeConfig[d.type]?.icon || typeConfig.other.icon);

      // Create node labels
      nodeLabel = nodeGroup.append("text")
        .attr("class", "node-label")
        .attr("dy", 30)
        .text(d => d.label);

      // Tooltip
      const tooltip = d3.select(".tooltip");

      nodeGroup.on("mouseover", (event, d) => {
        highlightNeighbors(d);

        tooltip.transition()
          .duration(200)
          .style("opacity", 0.95);

        let html = "<h3>" + d.label + "</h3>";
        html += "<p><strong>Type:</strong> " + d.type.replace(/_/g, " ") + "</p>";

        if (d.aliases && d.aliases.length > 0) {
          html += "<p><strong>Aliases:</strong> " + d.aliases.join(", ") + "</p>";
        }

        if (d.definition) {
          const def = d.definition.length > 150 ? d.definition.substring(0, 150) + "..." : d.definition;
          html += "<p><strong>Definition:</strong> " + def + "</p>";
        }

        // Show relationships
        const relLinks = links.filter(l =>
          (l.source.id || l.source) === d.id || (l.target.id || l.target) === d.id
        );
        if (relLinks.length > 0) {
          html += "<p><strong>Relationships:</strong> " + relLinks.length + "</p>";
        }

        tooltip.html(html)
          .style("left", (event.pageX + 10) + "px")
          .style("top", (event.pageY - 28) + "px");
      })
      .on("mouseout", () => {
        clearHighlight();
        tooltip.transition()
          .duration(500)
          .style("opacity", 0);
      });

      // Update positions on tick
      simulation.on("tick", () => {
        link.attr("d", d => {
          const dx = d.target.x - d.source.x;
          const dy = d.target.y - d.source.y;
          const dr = Math.sqrt(dx * dx + dy * dy);
          return `M${d.source.x},${d.source.y}A${dr},${dr} 0 0,1 ${d.target.x},${d.target.y}`;
        });

        linkLabel
          .attr("x", d => (d.source.x + d.target.x) / 2)
          .attr("y", d => (d.source.y + d.target.y) / 2);

        nodeGroup.attr("transform", d => `translate(${d.x},${d.y})`);
      });
    }

    // Highlight neighbors on hover
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

      // Highlight connected nodes and links
      node.classed("highlighted", n => n.id === d.id)
          .classed("dimmed", n => !connectedNodes.has(n.id));

      link.classed("highlighted", l => connectedLinks.has(l))
          .classed("dimmed", l => !connectedLinks.has(l));

      linkLabel.classed("highlighted", l => connectedLinks.has(l));
    }

    function clearHighlight() {
      node.classed("highlighted", false).classed("dimmed", false);
      link.classed("highlighted", false).classed("dimmed", false);
      linkLabel.classed("highlighted", false);
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
      d.fx = null;
      d.fy = null;
    }

    // Initial render
    updateGraph();

    // Handle window resize
    window.addEventListener("resize", () => {
      const newWidth = container.clientWidth;
      const newHeight = container.clientHeight;
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
