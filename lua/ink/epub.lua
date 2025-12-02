local fs = require("ink.fs")

local M = {}

local function get_cache_dir()
  return vim.fn.stdpath("data") .. "/ink.nvim/cache"
end

local function get_slug(path)
  local filename = vim.fn.fnamemodify(path, ":t:r")
  return filename:gsub("[^%w]", "_")
end

-- Simple XML tag extractor
local function get_tag_content(xml, tag)
  local pattern = "<" .. tag .. "[^>]*>(.-)</" .. tag .. ">"
  return xml:match(pattern)
end

local function get_attribute(tag_string, attr)
  local escaped_attr = attr:gsub("([%-%^%$%(%)%%%.%[%]%*%+%?])", "%%%1")
  return tag_string:match(escaped_attr .. '=["\']([^"\']+)["\']')
end

function M.open(epub_path)
  if not fs.exists(epub_path) then
    error("File not found: " .. epub_path)
  end

  local slug = get_slug(epub_path)
  local cache_dir = get_cache_dir() .. "/" .. slug
  
  -- Unzip if not already there (or maybe always unzip to be safe/update?)
  -- For now, let's assume if dir exists, it's fine.
  if not fs.exists(cache_dir) then
    local success = fs.unzip(epub_path, cache_dir)
    if not success then
      error("Failed to unzip epub")
    end
  end

  -- 1. Read META-INF/container.xml
  local container_path = cache_dir .. "/META-INF/container.xml"
  local container_xml = fs.read_file(container_path)
  if not container_xml then
    error("Invalid EPUB: Missing META-INF/container.xml")
  end

  local rootfile_tag = container_xml:match("<rootfile%s+[^>]+>")
  local opf_rel_path = get_attribute(rootfile_tag, "full-path")
  local opf_path = cache_dir .. "/" .. opf_rel_path
  local opf_dir = vim.fn.fnamemodify(opf_path, ":h")

  -- 2. Read OPF
  local opf_content = fs.read_file(opf_path)
  if not opf_content then
    error("Could not read OPF file: " .. opf_path)
  end

  -- Parse Manifest (id -> href)
  local manifest = {}
  for item in opf_content:gmatch("<item%s+[^>]+>") do
    local id = get_attribute(item, "id")
    local href = get_attribute(item, "href")
    local media_type = get_attribute(item, "media-type")
    manifest[id] = { href = href, media_type = media_type }
  end

  -- Parse Spine (reading order)
  local spine = {}
  for itemref in opf_content:gmatch("<itemref[^>]+>") do
    local idref = get_attribute(itemref, "idref")
    if manifest[idref] then
      table.insert(spine, manifest[idref])
    end
  end

  -- Parse Metadata (Title)
  local title = get_tag_content(opf_content, "dc:title") or slug

  -- 3. TOC (NCX or NAV)
  -- Try to find TOC item in manifest
  local toc_href = nil
  -- Check for item with properties="nav" (EPUB 3)
  for item in opf_content:gmatch("<item[^>]+>") do
    local props = get_attribute(item, "properties")
    if props and props:match("nav") then
      toc_href = get_attribute(item, "href")
      break
    end
  end
  
  -- Fallback to id="ncx" or media-type="application/x-dtbncx+xml" (EPUB 2)
  if not toc_href then
    for id, item in pairs(manifest) do
      if item.media_type == "application/x-dtbncx+xml" then
        toc_href = item.href
        break
      end
    end
  end

  local toc = {}
  if toc_href then
    local toc_path = opf_dir .. "/" .. toc_href
    local toc_content = fs.read_file(toc_path)
    
    -- Helper to normalize path
    local function normalize_path(path)
      local parts = {}
      for part in path:gmatch("[^/]+") do
        if part == ".." then
          if #parts > 0 and parts[#parts] ~= ".." then
            table.remove(parts)
          else
            table.insert(parts, part)
          end
        elseif part ~= "." then
          table.insert(parts, part)
        end
      end
      return table.concat(parts, "/")
    end

    local toc_dir_rel = vim.fn.fnamemodify(toc_href, ":h")
    
    local function resolve_href(href)
      if not href then return nil end
      local path_part = href:match("^([^#]+)") or href
      local anchor_part = href:match("(#.+)$") or ""
      
      local full_path = path_part
      if toc_dir_rel ~= "." then
        full_path = toc_dir_rel .. "/" .. path_part
      end
      
      local normalized = normalize_path(full_path)
      return normalized .. anchor_part
    end

    if toc_content then
      -- EPUB 3 (XHTML NAV)
      if toc_href:match("%.xhtml$") or toc_href:match("%.html$") then
         -- Simple regex approach for flat list
         -- TODO: Implement proper hierarchical parsing for NAV
         for link in toc_content:gmatch("<a[^>]+>.-</a>") do
             local href = get_attribute(link, "href")
             local text = link:match(">([^<]+)<")
             if href and text then
                href = resolve_href(href)
                table.insert(toc, { label = text, href = href, level = 1 })
             end
          end
         
      else
        -- EPUB 2 (NCX)
        local function parse_ncx(xml, level)
           local items = {}
           local pos = 1
           while true do
              local s, e, tag_content = xml:find("<navPoint([^>]+)>", pos)
              if not s then break end
              
              -- Find matching closing tag
              local balance = 1
              local inner_start = e + 1
              local inner_end = inner_start
              local p = inner_start
              
              while balance > 0 and p <= #xml do
                 local s2, e2, t2 = xml:find("<(/?navPoint)", p)
                 if not s2 then break end
                 if t2 == "navPoint" then balance = balance + 1
                 else balance = balance - 1 end
                 p = e2 + 1
                 if balance == 0 then inner_end = s2 - 1 end
              end
              
              local inner_xml = xml:sub(inner_start, inner_end)
              
              -- Extract label and src
              local label = inner_xml:match("<text>([^<]+)</text>")
              local content_tag = inner_xml:match("<content[^>]+>")
              local src = get_attribute(content_tag or "", "src")
              
              if label and src then
                 src = resolve_href(src)
                 table.insert(toc, { label = label, href = src, level = level })
                 -- Recurse
                 parse_ncx(inner_xml, level + 1)
              end
              
              pos = p
           end
        end
        
        parse_ncx(toc_content, 1)
      end
    end
  end

  return {
    title = title,
    spine = spine, -- List of { href=... }
    toc = toc,     -- List of { label=..., href=... }
    base_dir = opf_dir,
    slug = slug,
    cache_dir = cache_dir
  }
end

return M
