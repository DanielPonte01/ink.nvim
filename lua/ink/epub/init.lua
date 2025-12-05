local fs = require("ink.fs")
local container = require("ink.epub.container")
local opf = require("ink.epub.opf")
local ncx = require("ink.epub.ncx")
local nav = require("ink.epub.nav")
local css = require("ink.epub.css")
local util = require("ink.epub.util")

local M = {}

local function get_cache_dir()
  return vim.fn.stdpath("data") .. "/ink.nvim/cache"
end

function M.open(epub_path)
  epub_path = vim.fn.fnamemodify(epub_path, ":p")

  if not fs.exists(epub_path) then
    error("File not found: " .. epub_path)
  end

  local slug = util.get_slug(epub_path)
  local cache_dir = get_cache_dir() .. "/" .. slug

  -- Extraction logic (unchanged)
  local needs_extraction = false
  if not fs.exists(cache_dir) then
    needs_extraction = true
  else
    local epub_stat = vim.loop.fs_stat(epub_path)
    local cache_stat = vim.loop.fs_stat(cache_dir)
    if epub_stat and cache_stat then
      if epub_stat.mtime.sec > cache_stat.mtime.sec then
        needs_extraction = true
        vim.fn.delete(cache_dir, "rf")
      end
    else
      needs_extraction = true
    end
  end

  if needs_extraction then
    local success = fs.unzip(epub_path, cache_dir)
    if not success then error("Failed to unzip epub") end
  end

  -- 1. Container
  local container_path = cache_dir .. "/META-INF/container.xml"
  local container_xml = fs.read_file(container_path)
  if not container_xml then error("Invalid EPUB: Missing META-INF/container.xml") end
  local opf_rel_path = container.parse_container_xml(container_xml)
  local opf_path = cache_dir .. "/" .. opf_rel_path
  opf_path = util.validate_path(opf_path, cache_dir)
  local opf_dir = vim.fn.fnamemodify(opf_path, ":h")

  -- 2. OPF
  local opf_content = fs.read_file(opf_path)
  if not opf_content then error("Could not read OPF file: " .. opf_path) end
  local manifest = opf.parse_manifest(opf_content)
  local spine = opf.parse_spine(opf_content, manifest)
  local metadata = opf.parse_metadata(opf_content, slug)

  -- 3. TOC
  local toc_href = opf.find_toc_href(opf_content, manifest)
  local toc = {}
  if toc_href then
    local toc_path = opf_dir .. "/" .. toc_href
    toc_path = util.validate_path(toc_path, cache_dir)
    local toc_content = fs.read_file(toc_path)
    if toc_content then
      local toc_dir_rel = vim.fn.fnamemodify(toc_href, ":h")
      local function resolve_href(href)
        if not href then return nil end
        local path_part = href:match("^([^#]+)") or href
        local anchor_part = href:match("(#.+)$") or ""
        local full_path = path_part
        if toc_dir_rel ~= "." then full_path = toc_dir_rel .. "/" .. path_part end
        local normalized = util.normalize_path(full_path)
        return normalized .. anchor_part
      end
      if toc_href:match("%.xhtml$") or toc_href:match("%.html$") then
        toc = nav.parse_nav(toc_content, resolve_href)
      else
        toc = ncx.parse_ncx(toc_content, resolve_href, 1)
      end
    end
  end

  -- 4. CSS
  local class_styles = css.parse_all_css_files(manifest, opf_dir, cache_dir)

  return {
    title = metadata.title,
    author = metadata.author,
    language = metadata.language,
    date = metadata.date,
    description = metadata.description,
    spine = spine,
    toc = toc,
    base_dir = opf_dir,
    slug = slug,
    cache_dir = cache_dir,
    class_styles = class_styles,
    path = epub_path
  }
end

return M