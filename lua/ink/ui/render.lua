local html = require("ink.html")
local fs = require("ink.fs")
local state = require("ink.state")
local user_highlights = require("ink.user_highlights")
local bookmarks_data = require("ink.bookmarks")
local library = require("ink.library")
local context = require("ink.ui.context")
local util = require("ink.ui.util")
local parse = require("ink.html.parser")
local toc = require("ink.ui.toc")
local footnotes = require("ink.ui.footnotes")
local extmarks = require("ink.ui.extmarks")

local M = {}

-- Re-export TOC functions for backwards compatibility
M.render_toc = toc.render_toc
M.toggle_toc = toc.toggle_toc

-- Re-export footnote function
M.show_footnote_preview = footnotes.show_footnote_preview

-- Get parsed chapter with caching
function M.get_parsed_chapter(chapter_idx, ctx)
  ctx = ctx or context.current()
  if not ctx then return nil end

  -- Return from cache if exists
  if ctx.parsed_chapters[chapter_idx] then
    return ctx.parsed_chapters[chapter_idx]
  end

  -- Get chapter/page from spine
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
    content = fs.read_file(chapter_path)
    if not content then return nil end
  else
    return nil
  end

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

  local parsed = html.parse(content, max_width, class_styles, justify_text, typography)

  -- Cache parsed result
  ctx.parsed_chapters[chapter_idx] = parsed

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
  extmarks.apply_syntax_highlights(ctx.content_buf, final_highlights, context.ns_id, padding)

  ctx.images = final_images or {}
  ctx.links = final_links or {}
  ctx.anchors = final_anchors or {}
  ctx.justify_map = parsed.justify_map or {}
  ctx.rendered_lines = final_lines

  -- Apply user highlights using extmarks module
  local chapter_highlights = user_highlights.get_chapter_highlights(ctx.data.slug, idx)
  extmarks.apply_user_highlights(ctx.content_buf, chapter_highlights, context.ns_id, final_lines)

  -- Apply note indicators using extmarks module
  extmarks.apply_note_indicators(ctx.content_buf, chapter_highlights, ctx.note_display_mode, padding, max_width, context.ns_id)

  -- Render bookmarks using extmarks module
  local chapter_bookmarks = bookmarks_data.get_chapter_bookmarks(ctx.data.slug, idx)
  local bookmark_icon = context.config.bookmark_icon or "󰃀"
  extmarks.apply_bookmarks(ctx.content_buf, chapter_bookmarks, padding, bookmark_icon, context.ns_id, final_lines)

  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    if restore_line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {restore_line, 0})
    else
      vim.api.nvim_win_set_cursor(ctx.content_win, {1, 0})
    end
  end

  M.update_statusline(ctx)
  state.save(ctx.data.slug, { chapter = idx, line = restore_line or 1 })
  library.update_progress(ctx.data.slug, idx, #ctx.data.spine)
end


function M.toggle_note_display(ctx)
  ctx = ctx or context.current()
  if not ctx then return end
  if ctx.note_display_mode == "off" then
    ctx.note_display_mode = "indicator"
  elseif ctx.note_display_mode == "indicator" then
    ctx.note_display_mode = "expanded"
  else
    ctx.note_display_mode = "off"
  end
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  M.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
  vim.notify("Note display: " .. ctx.note_display_mode, vim.log.levels.INFO)
end

return M
