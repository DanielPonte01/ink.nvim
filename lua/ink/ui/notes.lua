local user_highlights = require("ink.user_highlights")
local context = require("ink.ui.context")
local util = require("ink.ui.util")
local render = require("ink.ui.render")
local modals = require("ink.ui.modals")

local M = {}

function M.add_note()
  local ctx = context.current()
  if not ctx then return end
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then
    vim.notify("Notes can only be added in the content buffer", vim.log.levels.WARN)
    return
  end
  local hl = util.get_highlight_at_cursor(ctx)
  if not hl then vim.notify("No highlight under cursor", vim.log.levels.WARN); return end
  local existing_note = hl.note or ""

  modals.open_note_input(existing_note, function(text)
    user_highlights.update_note(ctx.data.slug, hl, text)
    local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
    render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
    if text and text ~= "" then
      if existing_note ~= "" then vim.notify("Note updated", vim.log.levels.INFO)
      else vim.notify("Note added", vim.log.levels.INFO) end
    else
      if existing_note ~= "" then vim.notify("Note removed", vim.log.levels.INFO) end
    end
  end)
end

M.edit_note = M.add_note

function M.remove_note()
  local ctx = context.current()
  if not ctx then return end
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then vim.notify("Notes can only be removed in the content buffer", vim.log.levels.WARN); return end
  local hl = util.get_highlight_at_cursor(ctx)
  if not hl then vim.notify("No highlight under cursor", vim.log.levels.WARN); return end
  if not hl.note or hl.note == "" then vim.notify("No note on this highlight", vim.log.levels.INFO); return end
  user_highlights.update_note(ctx.data.slug, hl, "")
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
  vim.notify("Note removed", vim.log.levels.INFO)
end

function M.add_highlight(color)
  local ctx = context.current()
  if not ctx then return end
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then vim.notify("Highlights can only be added in the content buffer", vim.log.levels.WARN); return end
  if not context.config.highlight_colors[color] then vim.notify("Unknown highlight color: " .. color, vim.log.levels.ERROR); return end

  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local start_col = start_pos[3] - 1
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  local lines = vim.api.nvim_buf_get_lines(ctx.content_buf, start_line - 1, end_line, false)
  local text
  if #lines == 1 then text = lines[1]:sub(start_col + 1, end_col)
  else
    lines[1] = lines[1]:sub(start_col + 1)
    lines[#lines] = lines[#lines]:sub(1, end_col)
    text = table.concat(lines, "\n")
  end

  local context_len = 30
  local full_text = util.get_full_text(ctx.rendered_lines)
  local start_offset = util.line_col_to_offset(ctx.rendered_lines, start_line, start_col)
  local end_offset = util.line_col_to_offset(ctx.rendered_lines, end_line, end_col)
  local context_before = ""
  local context_after = ""

  if start_offset > 0 then
    local ctx_start = math.max(0, start_offset - context_len)
    context_before = full_text:sub(ctx_start + 1, start_offset)
  end
  if end_offset < #full_text then
    local ctx_end = math.min(#full_text, end_offset + context_len)
    context_after = full_text:sub(end_offset + 1, ctx_end)
  end

  text = util.normalize_whitespace(text)
  context_before = util.normalize_whitespace(context_before)
  context_after = util.normalize_whitespace(context_after)

  local highlight = {
    chapter = ctx.current_chapter_idx,
    text = text,
    context_before = context_before,
    context_after = context_after,
    color = color
  }
  user_highlights.add_highlight(ctx.data.slug, highlight)
  render.render_chapter(ctx.current_chapter_idx, end_line, ctx)
  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    vim.api.nvim_win_set_cursor(ctx.content_win, {end_line, end_col})
  end
  vim.notify("Highlight added", vim.log.levels.INFO)
end

function M.remove_highlight()
  local ctx = context.current()
  if not ctx then return end
  local buf = vim.api.nvim_get_current_buf()
  if buf ~= ctx.content_buf then vim.notify("Highlights can only be removed in the content buffer", vim.log.levels.WARN); return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local hl = util.get_highlight_at_cursor(ctx)
  if not hl then vim.notify("No highlight under cursor", vim.log.levels.WARN); return end
  user_highlights.remove_highlight_by_text(ctx.data.slug, hl)
  render.render_chapter(ctx.current_chapter_idx, line, ctx)
  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    vim.api.nvim_win_set_cursor(ctx.content_win, cursor)
  end
  vim.notify("Highlight removed", vim.log.levels.INFO)
end

return M
