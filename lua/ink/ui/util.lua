local fs = require("ink.fs")
local user_highlights = require("ink.user_highlights")
local context = require("ink.ui.context")

local M = {}

function M.open_image(src, ctx)
  ctx = ctx or context.current()
  if not ctx then return end

  -- Check if image opening is enabled
  if context.config and context.config.image_open == false then
    vim.notify("Image opening is disabled", vim.log.levels.WARN)
    return
  end

  -- Sanitize src: prevent absolute paths and home directory
  -- Path traversal (..) is handled by the allowed_root check below
  if src:match("^/") or src:match("^~") then
    vim.notify("Access denied: Invalid image path", vim.log.levels.ERROR)
    return
  end

  local chapter_item = ctx.data.spine[ctx.current_chapter_idx]
  if not chapter_item then
    vim.notify("No chapter loaded", vim.log.levels.ERROR)
    return
  end
  local chapter_dir

  -- Determine chapter directory based on format
  if ctx.data.format == "markdown" then
    -- Markdown: images are relative to the .md file
    chapter_dir = ctx.data.base_dir
  else
    -- EPUB: images are relative to the chapter HTML file
    local chapter_path = ctx.data.base_dir .. "/" .. chapter_item.href
    chapter_dir = vim.fn.fnamemodify(chapter_path, ":h")
  end

  local image_path = chapter_dir .. "/" .. src

  -- Normalize path before resolving
  image_path = vim.fn.fnamemodify(image_path, ":p")

  -- Security check: ensure the normalized path is within allowed directory
  local allowed_root
  if ctx.data.format == "markdown" then
    allowed_root = vim.fn.fnamemodify(ctx.data.base_dir, ":p")
  elseif ctx.data.cache_dir then
    allowed_root = vim.fn.fnamemodify(ctx.data.cache_dir, ":p")
  else
    allowed_root = vim.fn.fnamemodify(chapter_dir, ":p")
  end

  if allowed_root then
    if image_path:sub(1, #allowed_root) ~= allowed_root then
      vim.notify("Access denied: Image path outside allowed directory", vim.log.levels.ERROR)
      return
    end
  end

  if not fs.exists(image_path) then
    vim.notify("Image not found: " .. src, vim.log.levels.ERROR)
    return
  end

  -- Resolve symlinks and verify the final target is still within allowed directory
  local resolved_path = vim.fn.resolve(image_path)
  if allowed_root then
    if resolved_path:sub(1, #allowed_root) ~= allowed_root then
      vim.notify("Access denied: Image symlink target outside allowed directory", vim.log.levels.ERROR)
      return
    end
  end

  -- Use resolved path for opening
  image_path = resolved_path

  local ext = image_path:lower():match("%.(%w+)$")
  local valid_images = {
    jpg = true, jpeg = true, png = true, gif = true,
    webp = true, svg = true, bmp = true, ico = true,
    tiff = true, tif = true
  }
  if not ext or not valid_images[ext] then
    vim.notify("Access denied: Not a valid image file", vim.log.levels.ERROR)
    return
  end

  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = {"open", image_path}
  elseif vim.fn.has("unix") == 1 then
    -- Get configured image viewer
    local configured_viewer = context.config and context.config.image_viewer or "default"
    local default_viewers = {"feh", "sxiv", "imv", "eog", "gwenview", "xdg-open"}

    if configured_viewer ~= "default" then
      -- Try configured viewer first
      if vim.fn.executable(configured_viewer) == 1 then
        cmd = {configured_viewer, image_path}
      else
        vim.notify("Configured viewer '" .. configured_viewer .. "' not found, trying fallback", vim.log.levels.WARN)
      end
    end

    -- Fallback to default viewers if no cmd yet
    if not cmd then
      for _, viewer in ipairs(default_viewers) do
        if vim.fn.executable(viewer) == 1 then
          cmd = {viewer, image_path}
          break
        end
      end
    end
  elseif vim.fn.has("win32") == 1 then
    cmd = {"cmd", "/c", "start", "", image_path}
  end

  if not cmd then
    vim.notify("Could not find image viewer", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart(cmd, {
    detach = true,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.notify("Failed to open image: " .. src, vim.log.levels.ERROR)
      end
    end
  })
end

function M.open_url(url)
  if type(url) ~= "string" or url == "" then
    vim.notify("Invalid URL", vim.log.levels.ERROR)
    return
  end

  local normalized_url = url:lower():match("^%s*(.-)%s*$") or url
  if not normalized_url:match("^https?://") then
    vim.notify("Only HTTP and HTTPS URLs are allowed", vim.log.levels.ERROR)
    return
  end

  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = {"open", url}
  elseif vim.fn.has("unix") == 1 then
    -- Check for common browsers and tools
    local browsers = {"xdg-open", "firefox", "chromium", "google-chrome", "brave"}
    for _, browser in ipairs(browsers) do
      if vim.fn.executable(browser) == 1 then
        cmd = {browser, url}
        break
      end
    end
  elseif vim.fn.has("win32") == 1 then
    cmd = {"cmd", "/c", "start", "", url}
  end

  if not cmd then
    vim.notify("Could not find browser to open URL", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart(cmd, {
    detach = true,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.notify("Failed to open URL: " .. url, vim.log.levels.ERROR)
      end
    end
  })
end

function M.get_full_text(lines)
  return table.concat(lines, "\n")
end

function M.normalize_whitespace(text)
  if not text then return text end
  return text:gsub("%s+", " ")
end

function M.offset_to_line_col(lines, offset)
  if not lines or #lines == 0 then
    return 1, 0
  end

  local current_offset = 0
  for i, line in ipairs(lines) do
    local line_len = #line + 1
    if current_offset + line_len > offset then
      return i, offset - current_offset
    end
    current_offset = current_offset + line_len
  end
  return #lines, #(lines[#lines] or "")
end

function M.line_col_to_offset(lines, line, col)
  if not lines or #lines == 0 then
    return 0
  end

  local offset = 0
  for i = 1, math.min(line - 1, #lines) do
    offset = offset + #lines[i] + 1
  end
  return offset + col
end

function M.find_text_position(lines, text, context_before, context_after, allow_fallback)
  -- Default to true for backwards compatibility
  if allow_fallback == nil then
    allow_fallback = true
  end

  local full_text = M.get_full_text(lines)
  local normalized_full = M.normalize_whitespace(full_text)
  local normalized_text = M.normalize_whitespace(text)
  local normalized_ctx_before = M.normalize_whitespace(context_before or "")
  local normalized_ctx_after = M.normalize_whitespace(context_after or "")

  local search_text = normalized_ctx_before .. normalized_text .. normalized_ctx_after
  local match_start = normalized_full:find(search_text, 1, true)

  if match_start then
    local norm_text_start = match_start + #normalized_ctx_before
    local norm_text_end = norm_text_start + #normalized_text - 1
    local norm_pos = 0
    local start_orig = nil
    local end_orig = nil

    for i = 1, #full_text do
      local char = full_text:sub(i, i)
      local is_space = char:match("%s")
      if is_space then
        local prev_char = i > 1 and full_text:sub(i-1, i-1) or ""
        if not prev_char:match("%s") then norm_pos = norm_pos + 1 end
      else
        norm_pos = norm_pos + 1
      end
      if norm_pos == norm_text_start and not start_orig then start_orig = i end
      if norm_pos == norm_text_end then end_orig = i; break end
    end

    if start_orig and end_orig then
      local start_line, start_col = M.offset_to_line_col(lines, start_orig - 1)
      local end_line, end_col = M.offset_to_line_col(lines, end_orig)
      return start_line, start_col, end_line, end_col
    end
  end

  -- Fallback: search without context (only if allowed)
  if allow_fallback then
    local match_start_simple = normalized_full:find(normalized_text, 1, true)
    if match_start_simple then
      local norm_pos = 0
      local start_orig = nil
      local end_orig = nil
      for i = 1, #full_text do
        local char = full_text:sub(i, i)
        local is_space = char:match("%s")
        if is_space then
          local prev_char = i > 1 and full_text:sub(i-1, i-1) or ""
          if not prev_char:match("%s") then norm_pos = norm_pos + 1 end
        else
          norm_pos = norm_pos + 1
        end
        if norm_pos == match_start_simple and not start_orig then start_orig = i end
        if norm_pos == match_start_simple + #normalized_text - 1 then end_orig = i; break end
      end
      if start_orig and end_orig then
        local start_line, start_col = M.offset_to_line_col(lines, start_orig - 1)
        local end_line, end_col = M.offset_to_line_col(lines, end_orig)
        return start_line, start_col, end_line, end_col
      end
    end
  end

  return nil
end

function M.get_highlight_at_cursor(ctx)
  ctx = ctx or context.current()
  if not ctx then return nil end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]
  local cursor_offset = M.line_col_to_offset(ctx.rendered_lines, line, col)
  local chapter_highlights = user_highlights.get_chapter_highlights(ctx.data.slug, ctx.current_chapter_idx)

  for _, hl in ipairs(chapter_highlights) do
    local start_line, start_col, end_line, end_col = M.find_text_position(
      ctx.rendered_lines, hl.text, hl.context_before, hl.context_after, false  -- Strict matching for highlights
    )
    if start_line then
      local hl_start_offset = M.line_col_to_offset(ctx.rendered_lines, start_line, start_col)
      local hl_end_offset = M.line_col_to_offset(ctx.rendered_lines, end_line, end_col)
      if cursor_offset >= hl_start_offset and cursor_offset <= hl_end_offset then
        return hl
      end
    end
  end
  return nil
end

function M.get_link_at_cursor(line, col, ctx)
  ctx = ctx or context.current()
  if not ctx then return nil end
  for _, link in ipairs(ctx.links) do
    if link[1] == line and col >= link[2] and col < link[3] then
      return link[4]
    end
  end
  return nil
end

-- Word wrap and justify text for margin notes
function M.wrap_note_text(note, max_width)
  if not note or note == "" then
    return {}
  end

  local lines = {}
  local current_words = {}

  -- Phase 1: Wrap into lines
  for word in note:gmatch("%S+") do
    local test_line = table.concat(current_words, " ")
    if #current_words > 0 then
      test_line = test_line .. " " .. word
    else
      test_line = word
    end

    if vim.fn.strwidth(test_line) > max_width then
      if #current_words > 0 then
        table.insert(lines, current_words)
        current_words = {word}
      else
        -- Word alone is larger than max_width, force break
        table.insert(lines, {word:sub(1, max_width)})
        current_words = {}
      end
    else
      table.insert(current_words, word)
    end
  end

  if #current_words > 0 then
    table.insert(lines, current_words)
  end

  -- Phase 2: Determine if note should be justified
  -- Calculate total character count
  local total_chars = #note
  local is_short_note = total_chars < (max_width * 1.5)  -- Less than 1.5 lines worth

  -- Phase 3: Format lines
  local formatted_lines = {}
  for i, words in ipairs(lines) do
    local is_last_line = (i == #lines)

    if is_short_note or is_last_line or #words == 1 then
      -- Short notes or last line: no justification, just join words
      table.insert(formatted_lines, table.concat(words, " "))
    else
      -- Justify: distribute extra spaces between words
      local text = table.concat(words, " ")
      local text_width = vim.fn.strwidth(text)
      local extra_spaces = max_width - text_width

      -- Only justify if line is at least 85% full
      if text_width >= (max_width * 0.85) and extra_spaces > 0 then
        local gaps = #words - 1  -- number of gaps between words
        local spaces_per_gap = math.floor(extra_spaces / gaps)
        local extra_spaces_remainder = extra_spaces % gaps

        local justified = ""
        for j, word in ipairs(words) do
          justified = justified .. word
          if j < #words then
            -- Add base space + extra spaces
            local spaces = 1 + spaces_per_gap
            if j <= extra_spaces_remainder then
              spaces = spaces + 1
            end
            justified = justified .. string.rep(" ", spaces)
          end
        end
        table.insert(formatted_lines, justified)
      else
        -- Not enough content to justify nicely
        table.insert(formatted_lines, text)
      end
    end
  end

  return formatted_lines
end

return M
