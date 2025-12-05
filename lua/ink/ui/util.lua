local fs = require("ink.fs")
local user_highlights = require("ink.user_highlights")
local context = require("ink.ui.context")

local M = {}

-- Helper to open image
function M.open_image(src)
  local ctx = context.ctx
  -- Image paths in HTML are relative to the chapter file, not base_dir
  local chapter_item = ctx.data.spine[ctx.current_chapter_idx]
  local chapter_path = ctx.data.base_dir .. "/" .. chapter_item.href
  local chapter_dir = vim.fn.fnamemodify(chapter_path, ":h")

  local image_path = chapter_dir .. "/" .. src
  image_path = vim.fn.resolve(image_path)

  local cache_root = vim.fn.resolve(ctx.data.cache_dir)
  if image_path:sub(1, #cache_root) ~= cache_root then
    vim.notify("Access denied: Image path outside EPUB cache", vim.log.levels.ERROR)
    return
  end

  if not fs.exists(image_path) then
    vim.notify("Image not found: " .. src, vim.log.levels.ERROR)
    return
  end

  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = {"open", image_path}
  elseif vim.fn.has("unix") == 1 then
    cmd = {"xdg-open", image_path}
  elseif vim.fn.has("win32") == 1 then
    cmd = {"cmd", "/c", "start", "", image_path}
  end

  if not cmd then
    vim.notify("Could not determine image viewer command for your OS", vim.log.levels.ERROR)
    return
  end

  local job_id = vim.fn.jobstart(cmd, {
    detach = true,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.notify("Failed to open image: " .. src, vim.log.levels.ERROR)
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
  local current_offset = 0
  for i, line in ipairs(lines) do
    local line_len = #line + 1
    if current_offset + #line >= offset then
      return i, offset - current_offset
    end
    current_offset = current_offset + line_len
  end
  return #lines, #lines[#lines]
end

function M.line_col_to_offset(lines, line, col)
  local offset = 0
  for i = 1, line - 1 do
    offset = offset + #lines[i] + 1
  end
  return offset + col
end

function M.find_text_position(lines, text, context_before, context_after)
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
  return nil
end

function M.get_highlight_at_cursor()
  local ctx = context.ctx
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]
  local cursor_offset = M.line_col_to_offset(ctx.rendered_lines, line, col)
  local chapter_highlights = user_highlights.get_chapter_highlights(ctx.data.slug, ctx.current_chapter_idx)

  for _, hl in ipairs(chapter_highlights) do
    local start_line, start_col, end_line, end_col = M.find_text_position(
      ctx.rendered_lines, hl.text, hl.context_before, hl.context_after
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

function M.get_link_at_cursor(line, col)
  local ctx = context.ctx
  for _, link in ipairs(ctx.links) do
    if link[1] == line and col >= link[2] and col < link[3] then
      return link[4]
    end
  end
  return nil
end

return M
