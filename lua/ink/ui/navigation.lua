local context = require("ink.ui.context")
local util = require("ink.ui.util")
local render = require("ink.ui.render")

local M = {}

function M.jump_to_link()
  local ctx = context.current()
  if not ctx then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]
  local buf = vim.api.nvim_get_current_buf()

  if buf ~= ctx.content_buf then return end

  local href = util.get_link_at_cursor(line, col, ctx)
  if not href then
    vim.notify("No link at cursor", vim.log.levels.INFO)
    return
  end

  local anchor = href:match("^#(.+)$")
  if anchor then
    local anchor_line = ctx.anchors[anchor]
    if anchor_line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {anchor_line, 0})
      vim.cmd("normal! zz")
      return
    else
      vim.notify("Anchor not found: " .. anchor, vim.log.levels.WARN)
      return
    end
  end

  local target_href = href:match("^([^#]+)") or href
  local target_anchor = href:match("#(.+)$")

  for i, spine_item in ipairs(ctx.data.spine) do
    local spine_filename = spine_item.href:match("([^/]+)$")
    local target_filename = target_href:match("([^/]+)$")
    if spine_filename == target_filename then
      render.render_chapter(i, nil, ctx)
      if target_anchor and ctx.anchors[target_anchor] then
        vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[target_anchor], 0})
        vim.cmd("normal! zz")
      end
      return
    end
  end
  vim.notify("Link target not found: " .. href, vim.log.levels.WARN)
end

function M.next_chapter()
  local ctx = context.current()
  if not ctx then return end
  render.render_chapter(ctx.current_chapter_idx + 1, nil, ctx)
end

function M.prev_chapter()
  local ctx = context.current()
  if not ctx then return end
  render.render_chapter(ctx.current_chapter_idx - 1, nil, ctx)
end

function M.handle_enter()
  local ctx = context.current()
  if not ctx then return end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]
  local buf = vim.api.nvim_get_current_buf()

  if buf == ctx.toc_buf then
    local toc_item = ctx.data.toc[line]
    if toc_item then
      local target_href = toc_item.href:match("^([^#]+)") or toc_item.href
      local anchor = toc_item.href:match("#(.+)$")
      for i, spine_item in ipairs(ctx.data.spine) do
        if spine_item.href == target_href then
          render.render_chapter(i, nil, ctx)
          if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
            vim.api.nvim_set_current_win(ctx.content_win)
            if anchor and ctx.anchors[anchor] then
               vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[anchor], 0})
            end
          end
          break
        end
      end
    end
  elseif buf == ctx.content_buf then
    for _, img in ipairs(ctx.images) do
      if img[1] == line then
        util.open_image(img[4])
        return
      end
    end
    local href = util.get_link_at_cursor(line, col, ctx)
    if href then
      local anchor = href:match("^#(.+)$")
      if anchor then
        render.show_footnote_preview(anchor, ctx)
        return
      end
      local target_href = href:match("^([^#]+)") or href
      local target_anchor = href:match("#(.+)$")
      for i, spine_item in ipairs(ctx.data.spine) do
        local spine_filename = spine_item.href:match("([^/]+)$")
        local target_filename = target_href:match("([^/]+)$")
        if spine_filename == target_filename then
          render.render_chapter(i, nil, ctx)
          if target_anchor and ctx.anchors[target_anchor] then
            vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[target_anchor], 0})
          end
          return
        end
      end
      vim.notify("Link: " .. href, vim.log.levels.INFO)
    end
  end
end

function M.increase_width()
  local ctx = context.current()
  if not ctx then return end
  local step = context.config.width_step or 10
  local current = context.config.max_width or 120
  context.config.max_width = current + step
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
  vim.notify("Width: " .. context.config.max_width, vim.log.levels.INFO)
end

function M.decrease_width()
  local ctx = context.current()
  if not ctx then return end
  local step = context.config.width_step or 10
  local current = context.config.max_width or 120
  local new_width = math.max(40, current - step)
  context.config.max_width = new_width
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
  vim.notify("Width: " .. context.config.max_width, vim.log.levels.INFO)
end

function M.reset_width()
  local ctx = context.current()
  if not ctx then return end
  if ctx.default_max_width then
    context.config.max_width = ctx.default_max_width
    local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
    render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
    vim.notify("Width reset: " .. context.config.max_width, vim.log.levels.INFO)
  end
end

function M.toggle_justify()
  local ctx = context.current()
  if not ctx then return end
  context.config.justify_text = not context.config.justify_text
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
  vim.notify("Justify: " .. (context.config.justify_text and "on" or "off"), vim.log.levels.INFO)
end

return M
