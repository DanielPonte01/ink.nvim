-- Lazy-loaded modules for better startup performance
local _html, _fs, _state, _user_highlights, _bookmarks_data, _library, _extmarks
local context = require("ink.ui.context") -- Always needed

local M = {}

-- Lazy loaders
local function get_html()
  if not _html then _html = require("ink.html") end
  return _html
end

local function get_fs()
  if not _fs then _fs = require("ink.fs") end
  return _fs
end

local function get_state()
  if not _state then _state = require("ink.state") end
  return _state
end

local function get_user_highlights()
  if not _user_highlights then _user_highlights = require("ink.user_highlights") end
  return _user_highlights
end

local function get_bookmarks_data()
  if not _bookmarks_data then _bookmarks_data = require("ink.bookmarks") end
  return _bookmarks_data
end

local function get_library()
  if not _library then _library = require("ink.library") end
  return _library
end

local function get_extmarks()
  if not _extmarks then _extmarks = require("ink.ui.extmarks") end
  return _extmarks
end

-- Re-export TOC functions for backwards compatibility (lazy loaded)
function M.render_toc(...)
  return require("ink.ui.toc").render_toc(...)
end

function M.toggle_toc(...)
  return require("ink.ui.toc").toggle_toc(...)
end

-- Re-export footnote function (lazy loaded)
function M.show_footnote_preview(...)
  return require("ink.ui.footnotes").show_footnote_preview(...)
end

-- Extract plain text from HTML (lightweight, for search indexing)
function M.extract_plain_text(html_content)
  if not html_content or html_content == "" then
    return ""
  end

  local text = html_content

  -- Remove script and style tags with their content
  text = text:gsub("<script[^>]*>.-</script>", " ")
  text = text:gsub("<style[^>]*>.-</style>", " ")
  text = text:gsub("<head[^>]*>.-</head>", " ")

  -- Remove all HTML tags
  text = text:gsub("<[^>]+>", " ")

  -- Decode HTML entities
  local entities = require("ink.html.entities")
  text = entities.decode_entities(text)

  -- Normalize whitespace
  text = text:gsub("%s+", " ")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")

  return text
end

-- Get chapter HTML content (raw, without parsing)
function M.get_chapter_content(chapter_idx, ctx)
  ctx = ctx or context.current()
  if not ctx then return nil end

  local chapter = ctx.data.spine[chapter_idx]
  if not chapter then return nil end

  -- Get HTML content
  local content
  if chapter.content then
    -- Markdown format: content is already HTML
    content = chapter.content
  elseif chapter.href then
    -- EPUB format: need to read from file
    local chapter_path = ctx.data.base_dir .. "/" .. chapter.href
    content = get_fs().read_file(chapter_path)
    if not content then return nil end
  end

  return content
end

-- Get parsed chapter with caching (using LRU cache)
function M.get_parsed_chapter(chapter_idx, ctx)
  ctx = ctx or context.current()
  if not ctx then return nil end

  -- Migrate old table-based cache to LRU cache (backward compatibility)
  if type(ctx.parsed_chapters) == "table" and not ctx.parsed_chapters.get then
    local lru_cache = require("ink.cache.lru")
    local old_cache = ctx.parsed_chapters
    ctx.parsed_chapters = lru_cache.new(15)
    -- Migrate existing cached chapters
    for idx, parsed in pairs(old_cache) do
      ctx.parsed_chapters:put(idx, parsed)
    end
  end

  -- Return from cache if exists (LRU cache)
  local cached = ctx.parsed_chapters:get(chapter_idx)
  if cached then
    return cached
  end

  -- Get HTML content
  local content = M.get_chapter_content(chapter_idx, ctx)
  if not content then return nil end

  -- Parse HTML with current settings
  local max_width = context.config.max_width or 120
  local class_styles = ctx.data.class_styles or {}
  local justify_text = context.config.justify_text or false
  local typography = context.config.typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  local parsed = get_html().parse(content, max_width, class_styles, justify_text, typography)

  -- Cache parsed result (LRU cache)
  ctx.parsed_chapters:put(chapter_idx, parsed)

  return parsed
end

function M.update_statusline(ctx)
  ctx = ctx or context.current()
  if not ctx or not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then return end

  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local current_line = cursor[1]
  local total_lines = vim.api.nvim_buf_line_count(ctx.content_buf)
  local percent = math.floor((current_line / total_lines) * 100)

  local bar_len = 10
  local filled = math.floor((percent / 100) * bar_len)
  local bar = string.rep("█", filled) .. string.rep("▒", bar_len - filled)

  local total = #ctx.data.spine
  local current = ctx.current_chapter_idx or 1
  local chapter_name = nil

  if ctx.data.spine[current] and ctx.data.spine[current].href then
    local current_href = ctx.data.spine[current].href
    for _, toc_item in ipairs(ctx.data.toc) do
      local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
      if toc_href == current_href then
        chapter_name = toc_item.label
        break
      end
    end
  end
  if not chapter_name then chapter_name = "Chapter " .. current end

  local status = string.format(" %s %d%%%% | %s | %d/%d ", bar, percent, chapter_name, current, total)
  vim.api.nvim_set_option_value("statusline", status, { win = ctx.content_win })
end

function M.render_chapter(idx, restore_line, ctx)
  ctx = ctx or context.current()
  if not ctx or idx < 1 or idx > #ctx.data.spine then return end
  ctx.current_chapter_idx = idx
  ctx.last_statusline_percent = 0

  if not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then
    local found_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if buf == ctx.content_buf then found_win = win; break end
      end
    end
    if found_win then
      ctx.content_win = found_win
    else
      vim.cmd("vsplit")
      local new_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(new_win, ctx.content_buf)
      ctx.content_win = new_win
    end
  end

  -- Use get_parsed_chapter instead of parsing directly
  local parsed = M.get_parsed_chapter(idx, ctx)
  if not parsed then
    vim.api.nvim_buf_set_lines(ctx.content_buf, 0, -1, false, {"Error parsing chapter " .. idx})
    return
  end

  local max_width = context.config.max_width or 120
  local typography = context.config.typography or { line_spacing = 1 }

  -- Apply line spacing if needed
  local final_lines = parsed.lines
  local final_highlights = parsed.highlights
  local final_links = parsed.links
  local final_images = parsed.images
  local final_anchors = parsed.anchors
  local final_centered_lines = parsed.centered_lines
  local line_map = {} -- maps original line number to new line number

  if typography.line_spacing > 1 then
    local spaced_lines = {}
    local spacing = typography.line_spacing - 1

    for i, line in ipairs(parsed.lines) do
      table.insert(spaced_lines, line)
      line_map[i] = #spaced_lines

      -- Add spacing lines (except after last line)
      if i < #parsed.lines then
        for j = 1, spacing do
          table.insert(spaced_lines, "")
        end
      end
    end

    final_lines = spaced_lines

    -- Create deep copies and adjust all line-based references
    -- Deep copy highlights
    final_highlights = {}
    for _, hl in ipairs(parsed.highlights) do
      local new_hl = {hl[1], hl[2], hl[3], hl[4]}
      if line_map[new_hl[1]] then
        new_hl[1] = line_map[new_hl[1]]
      end
      table.insert(final_highlights, new_hl)
    end

    -- Deep copy links
    final_links = {}
    for _, link in ipairs(parsed.links) do
      local new_link = {link[1], link[2], link[3], link[4]}
      if line_map[new_link[1]] then
        new_link[1] = line_map[new_link[1]]
      end
      table.insert(final_links, new_link)
    end

    -- Deep copy images
    final_images = {}
    for _, img in ipairs(parsed.images) do
      local new_img = {}
      for k, v in pairs(img) do
        new_img[k] = v
      end
      if new_img.line and line_map[new_img.line] then
        new_img.line = line_map[new_img.line]
      end
      table.insert(final_images, new_img)
    end

    -- Create new anchors table
    final_anchors = {}
    for anchor_id, line_num in pairs(parsed.anchors) do
      final_anchors[anchor_id] = line_map[line_num] or line_num
    end

    -- Create new centered_lines table
    if parsed.centered_lines then
      final_centered_lines = {}
      for line_num, _ in pairs(parsed.centered_lines) do
        final_centered_lines[line_map[line_num] or line_num] = true
      end
    end
  else
    -- No line spacing, create identity map
    for i = 1, #parsed.lines do
      line_map[i] = i
    end
  end

  local win_width = vim.api.nvim_win_get_width(ctx.content_win)
  local padding = 0
  if win_width > max_width then
    padding = math.floor((win_width - max_width) / 2)
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.content_buf })
  vim.api.nvim_buf_set_lines(ctx.content_buf, 0, -1, false, final_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.content_buf })

  vim.api.nvim_buf_clear_namespace(ctx.content_buf, context.ns_id, 0, -1)

  for i = 1, #final_lines do
    local line_idx = i - 1
    local line_padding = padding

    -- Add extra padding to center title lines within max_width
    if final_centered_lines and final_centered_lines[i] then
      local line_width = vim.fn.strdisplaywidth(final_lines[i])
      if line_width < max_width then
        line_padding = line_padding + math.floor((max_width - line_width) / 2)
      end
    end

    if line_padding > 0 then
      local pad_str = string.rep(" ", line_padding)
      vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, line_idx, 0, {
        virt_text = {{pad_str, "Normal"}}, virt_text_pos = "inline", priority = 100
      })
    end
  end

  -- Apply syntax highlights using extmarks module
  get_extmarks().apply_syntax_highlights(ctx.content_buf, final_highlights, context.ns_id, padding)

  ctx.images = final_images or {}
  ctx.links = final_links or {}
  ctx.anchors = final_anchors or {}
  ctx.justify_map = parsed.justify_map or {}
  ctx.rendered_lines = final_lines

  -- Apply user highlights using extmarks module
  local chapter_highlights = get_user_highlights().get_chapter_highlights(ctx.data.slug, idx)
  local extmarks_module = get_extmarks()
  extmarks_module.apply_user_highlights(ctx.content_buf, chapter_highlights, context.ns_id, final_lines)

  -- Apply note indicators or margin notes based on mode
  if ctx.note_display_mode == "margin" then
    local success = extmarks_module.apply_margin_notes(
      ctx.content_buf,
      chapter_highlights,
      padding,
      max_width,
      win_width,
      context.ns_id,
      ctx._margin_toggle_attempt  -- Flag to show notification only on user toggle
    )

    -- Silent fallback to expanded mode if margin notes fail
    if not success then
      extmarks_module.apply_note_indicators(ctx.content_buf, chapter_highlights, "expanded", padding, max_width, context.ns_id)
    end

    -- Clear the flag after first attempt
    ctx._margin_toggle_attempt = false
  elseif ctx.note_display_mode ~= "off" then
    -- Use traditional note indicators for "indicator" and "expanded" modes
    extmarks_module.apply_note_indicators(ctx.content_buf, chapter_highlights, ctx.note_display_mode, padding, max_width, context.ns_id)
  end
  -- If "off", don't apply any note indicators

  -- Render bookmarks using extmarks module
  local chapter_bookmarks = get_bookmarks_data().get_chapter_bookmarks(ctx.data.slug, idx)
  local bookmark_icon = context.config.bookmark_icon or "󰃀"
  extmarks_module.apply_bookmarks(ctx.content_buf, chapter_bookmarks, padding, bookmark_icon, context.ns_id, final_lines, max_width)

  -- GLOSSARY: Detect and render glossary terms
  local glossary_data = require("ink.glossary.data").load(ctx.data.slug)

  if glossary_data and glossary_data.entries and #glossary_data.entries > 0 then
    local detection = require("ink.glossary.detection")

    -- Calculate current version hash (Level 2 optimization)
    local current_version = detection.calculate_version_hash(glossary_data.entries)

    -- Load persistent cache if in-memory cache is empty (Level 3 optimization)
    if not ctx.glossary_matches_cache.version then
      local glossary_cache = require("ink.glossary.cache")
      local persistent_cache = glossary_cache.load(ctx.data.slug)

      if persistent_cache and persistent_cache.version == current_version then
        -- Persistent cache is valid, use it
        ctx.glossary_matches_cache = persistent_cache
      end
    end

    -- Check if cache is still valid (version matches)
    if ctx.glossary_matches_cache.version ~= current_version then
      -- Version mismatch: glossary structure changed, invalidate cache
      ctx.glossary_matches_cache = {
        version = current_version,
        chapters = {}
      }
      -- Clear persistent cache (Level 3 optimization)
      local glossary_cache = require("ink.glossary.cache")
      glossary_cache.clear(ctx.data.slug)

      -- Also rebuild detection index
      ctx.glossary_detection_index = detection.build_detection_index(glossary_data.entries)
      ctx.glossary_custom_types = glossary_data.custom_types
    elseif not ctx.glossary_detection_index then
      -- Version matches but index not built yet (first load)
      ctx.glossary_detection_index = detection.build_detection_index(glossary_data.entries)
      ctx.glossary_custom_types = glossary_data.custom_types
    end

    -- Check chapter cache (Level 1 optimization)
    local cached_matches = ctx.glossary_matches_cache.chapters[idx]

    if cached_matches then
      -- Cache hit: use cached matches
      ctx.glossary_matches = cached_matches
    else
      -- Cache miss: detect and store
      ctx.glossary_matches = detection.detect_in_chapter(final_lines, ctx.glossary_detection_index)
      ctx.glossary_matches_cache.chapters[idx] = ctx.glossary_matches

      -- Persist cache to disk (Level 3 optimization)
      local glossary_cache = require("ink.glossary.cache")
      glossary_cache.save(ctx.data.slug, ctx.glossary_matches_cache)
    end

    -- Only apply glossary marks if glossary_visible is true
    if ctx.glossary_visible and #ctx.glossary_matches > 0 then
      extmarks_module.apply_glossary_marks(
        ctx.content_buf,
        ctx.glossary_matches,
        ctx.glossary_detection_index.entries,
        ctx.glossary_custom_types,
        context.ns_id
      )
    end
  else
    ctx.glossary_matches = {}
  end

  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    if restore_line then
      -- restore_line can be either a number (line only) or a table {line, col}
      if type(restore_line) == "table" then
        vim.api.nvim_win_set_cursor(ctx.content_win, restore_line)
      else
        vim.api.nvim_win_set_cursor(ctx.content_win, {restore_line, 0})
      end
    else
      vim.api.nvim_win_set_cursor(ctx.content_win, {1, 0})
    end
  end

  M.update_statusline(ctx)
  get_state().save(ctx.data.slug, { chapter = idx, line = restore_line or 1 })
  get_library().update_progress(ctx.data.slug, idx, #ctx.data.spine)
end


function M.toggle_note_display(ctx)
  ctx = ctx or context.current()
  if not ctx then return end
  if ctx.note_display_mode == "off" then
    ctx.note_display_mode = "indicator"
  elseif ctx.note_display_mode == "indicator" then
    ctx.note_display_mode = "margin"
    ctx._margin_toggle_attempt = true  -- Flag to show notification if margin fails
  elseif ctx.note_display_mode == "margin" then
    ctx.note_display_mode = "expanded"
  else
    ctx.note_display_mode = "off"
  end
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  M.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
  vim.notify("Note display: " .. ctx.note_display_mode, vim.log.levels.INFO)
end

function M.toggle_glossary_display(ctx)
  ctx = ctx or context.current()
  if not ctx then return end

  -- Toggle the visibility state
  ctx.glossary_visible = not ctx.glossary_visible

  -- Get current cursor position
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)

  -- Re-render the chapter to apply/remove glossary marks
  M.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)

  -- Notify user
  local status = ctx.glossary_visible and "visible" or "hidden"
  vim.notify("Glossary terms: " .. status, vim.log.levels.INFO)
end

-- Invalidate glossary cache (for when glossary is modified)
-- Note: With Level 2 versioning, this is rarely needed as the system
-- automatically detects version changes. This is kept for manual invalidation.
function M.invalidate_glossary_cache(ctx)
  ctx = ctx or context.current()
  if not ctx then return end

  ctx.glossary_detection_index = nil
  ctx.glossary_matches_cache = {
    version = nil,
    chapters = {}
  }
  ctx.glossary_matches = {}

  -- Clear persistent cache (Level 3 optimization)
  if ctx.data and ctx.data.slug then
    local glossary_cache = require("ink.glossary.cache")
    glossary_cache.clear(ctx.data.slug)
  end
end

return M
