local context = require("ink.ui.context")
local util = require("ink.ui.util")
local render = require("ink.ui.render")
local modals = require("ink.ui.modals")

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

  -- Check if it's an external URL (http/https)
  if href:match("^https?://") then
    modals.open_url_confirmation(href, function(should_open)
      if should_open then
        util.open_url(href)
      end
    end)
    return
  end

  local anchor = href:match("^#(.+)$")
  if anchor then
    -- First try current chapter
    local anchor_line = ctx.anchors[anchor]
    if anchor_line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {anchor_line, 0})
      vim.cmd("normal! zz")
      return
    end

    -- If not found and this is Markdown, search in all chapters
    if ctx.data.format == "markdown" then
      for i, spine_item in ipairs(ctx.data.spine) do
        if i ~= ctx.current_chapter_idx then
          -- Parse this chapter to get its anchors
          local parsed = render.get_parsed_chapter(i, ctx)
          if parsed and parsed.anchors and parsed.anchors[anchor] then
            -- Found in another chapter, navigate there
            render.render_chapter(i, nil, ctx)
            vim.schedule(function()
              if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
                if ctx.anchors[anchor] then
                  vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[anchor], 0})
                  vim.cmd("normal! zz")
                end
              end
            end)
            return
          end
        end
      end
    end

    -- Not found anywhere
    vim.notify("Anchor not found: " .. anchor, vim.log.levels.WARN)
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
      -- Navigate by href
      if toc_item.href then
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
    end
  elseif buf == ctx.content_buf then
    -- Check for glossary terms first (highest priority)
    local glossary_ui = require("ink.glossary.ui")
    local glossary_match = glossary_ui.get_match_at_cursor(line, col)
    if glossary_match then
      glossary_ui.show_entry_preview(glossary_match)
      return
    end

    -- Check for images (second priority)
    for _, img in ipairs(ctx.images) do
      if img.line == line and img.type == "figure" then
        util.open_image(img.src, ctx)
        return
      end
    end

    -- Then check for links
    local href = util.get_link_at_cursor(line, col, ctx)
    if href then
      -- Check if it's an external URL (http/https)
      if href:match("^https?://") then
        modals.open_url_confirmation(href, function(should_open)
          if should_open then
            util.open_url(href)
          end
        end)
        return
      end

      -- Check if it's an image link (starts with common image extensions)
      if href:match("%.jpe?g$") or href:match("%.png$") or href:match("%.gif$") or
         href:match("%.webp$") or href:match("%.svg$") or href:match("%.bmp$") then
        -- It's an image, open it
        util.open_image(href, ctx)
        return
      end

      local anchor = href:match("^#(.+)$")
      if anchor then
        -- First try to find anchor in current chapter's anchors
        if ctx.anchors[anchor] then
          render.show_footnote_preview(anchor, ctx)
          return
        end

        -- If not found and this is Markdown, search in all chapters
        if ctx.data.format == "markdown" then
          -- Check current chapter first (might need re-parsing)
          local parsed_current = render.get_parsed_chapter(ctx.current_chapter_idx, ctx)
          if parsed_current and parsed_current.anchors and parsed_current.anchors[anchor] then
            -- Found in current chapter - show preview (update ctx.anchors first)
            ctx.anchors = parsed_current.anchors
            render.show_footnote_preview(anchor, ctx)
            return
          end

          -- Search in other chapters
          for i, spine_item in ipairs(ctx.data.spine) do
            if i ~= ctx.current_chapter_idx then
              -- Parse this chapter to get its anchors
              local parsed = render.get_parsed_chapter(i, ctx)
              if parsed and parsed.anchors and parsed.anchors[anchor] then
                -- Found in another chapter, navigate there
                render.render_chapter(i, nil, ctx)
                vim.schedule(function()
                  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
                    if ctx.anchors[anchor] then
                      vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[anchor], 0})
                      vim.cmd("normal! zz")
                    end
                  end
                end)
                return
              end
            end
          end
          -- Not found in any chapter
          vim.notify("Anchor not found: " .. anchor, vim.log.levels.WARN)
          return
        end

        -- For EPUB, try to show as footnote preview
        if not render.show_footnote_preview(anchor, ctx) then
          -- Preview failed, anchor doesn't exist
          vim.notify("Anchor not found: " .. anchor, vim.log.levels.WARN)
        end
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
  local current = ctx.current_max_width or context.config.max_width or 120
  ctx.current_max_width = current + step
  ctx.manual_width_override = true  -- Disable adaptive width until reset

  -- Save viewport position (text-based, survives word wrap changes)
  local viewport_ctx = render.get_viewport_text_context(ctx)

  -- Invalidate cache and re-render
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, nil, ctx)

  -- Restore viewport immediately (render_chapter is synchronous)
  if vim.api.nvim_win_is_valid(ctx.content_win) then
    vim.api.nvim_set_current_win(ctx.content_win)
    render.restore_viewport_from_context(ctx, viewport_ctx)
  end

  vim.notify("Width: " .. ctx.current_max_width .. " (adaptive disabled)", vim.log.levels.INFO)
end

function M.decrease_width()
  local ctx = context.current()
  if not ctx then return end
  local step = context.config.width_step or 10
  local current = ctx.current_max_width or context.config.max_width or 120
  local new_width = math.max(40, current - step)
  ctx.current_max_width = new_width
  ctx.manual_width_override = true  -- Disable adaptive width until reset

  -- Save viewport position (text-based, survives word wrap changes)
  local viewport_ctx = render.get_viewport_text_context(ctx)

  -- Invalidate cache and re-render
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, nil, ctx)

  -- Restore viewport immediately (render_chapter is synchronous)
  if vim.api.nvim_win_is_valid(ctx.content_win) then
    vim.api.nvim_set_current_win(ctx.content_win)
    render.restore_viewport_from_context(ctx, viewport_ctx)
  end

  vim.notify("Width: " .. ctx.current_max_width .. " (adaptive disabled)", vim.log.levels.INFO)
end

function M.reset_width()
  local ctx = context.current()
  if not ctx then return end
  if ctx.default_max_width then
    ctx.current_max_width = ctx.default_max_width
    ctx.manual_width_override = false  -- Re-enable adaptive width

    -- Recalculate adaptive width based on current window size
    local book_loader = require("ink.ui.book_loader")
    if book_loader.calculate_adaptive_width then
      local adaptive_width = book_loader.calculate_adaptive_width(ctx)
      if adaptive_width then
        ctx.current_max_width = adaptive_width
      end
    end

    -- Save viewport position (text-based, survives word wrap changes)
    local viewport_ctx = render.get_viewport_text_context(ctx)

    -- Invalidate cache since parsing depends on max_width
    ctx.parsed_chapters:clear()
    ctx.search_index = nil
    render.invalidate_glossary_cache(ctx)
    render.render_chapter(ctx.current_chapter_idx, nil, ctx)

    -- Restore viewport (text-based, keeps same content visible)
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(ctx.content_win) then
        vim.api.nvim_set_current_win(ctx.content_win)
        render.restore_viewport_from_context(ctx, viewport_ctx)
      end
    end)

    vim.notify("Width reset: " .. ctx.current_max_width .. " (adaptive enabled)", vim.log.levels.INFO)
  end
end

function M.toggle_justify()
  local ctx = context.current()
  if not ctx then return end
  context.config.justify_text = not context.config.justify_text

  -- Save viewport position (text-based, survives word wrap changes)
  local viewport_ctx = render.get_viewport_text_context(ctx)

  -- Invalidate cache since parsing depends on justify_text
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, nil, ctx)

  -- Restore viewport immediately (render_chapter is synchronous)
  if vim.api.nvim_win_is_valid(ctx.content_win) then
    vim.api.nvim_set_current_win(ctx.content_win)
    render.restore_viewport_from_context(ctx, viewport_ctx)
  end

  vim.notify("Justify: " .. (context.config.justify_text and "on" or "off"), vim.log.levels.INFO)
end

function M.increase_line_spacing()
  local ctx = context.current()
  if not ctx then return end

  -- Ensure typography config exists
  context.config.typography = context.config.typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  local current = context.config.typography.line_spacing
  local new_spacing = math.min(5, current + 1)  -- Max 5
  context.config.typography.line_spacing = new_spacing

  -- Save view (viewport position) to prevent text from jumping
  local view = vim.fn.winsaveview()

  -- Invalidate cache since parsing depends on typography
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, view.lnum, ctx)

  -- Restore view (keeps text at same visual position)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
      vim.fn.winrestview(view)
    end
  end)

  vim.notify("Line spacing: " .. new_spacing, vim.log.levels.INFO)
end

function M.decrease_line_spacing()
  local ctx = context.current()
  if not ctx then return end

  -- Ensure typography config exists
  context.config.typography = context.config.typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  local current = context.config.typography.line_spacing
  local new_spacing = math.max(1, current - 1)  -- Min 1
  context.config.typography.line_spacing = new_spacing

  -- Save view (viewport position) to prevent text from jumping
  local view = vim.fn.winsaveview()

  -- Invalidate cache since parsing depends on typography
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, view.lnum, ctx)

  -- Restore view (keeps text at same visual position)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
      vim.fn.winrestview(view)
    end
  end)

  vim.notify("Line spacing: " .. new_spacing, vim.log.levels.INFO)
end

function M.increase_paragraph_spacing()
  local ctx = context.current()
  if not ctx then return end

  -- Ensure typography config exists
  context.config.typography = context.config.typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  local current = context.config.typography.paragraph_spacing
  local new_spacing = math.min(5, current + 1)  -- Max 5
  context.config.typography.paragraph_spacing = new_spacing

  -- Save view (viewport position) to prevent text from jumping
  local view = vim.fn.winsaveview()

  -- Invalidate cache since parsing depends on typography
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, view.lnum, ctx)

  -- Restore view (keeps text at same visual position)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
      vim.fn.winrestview(view)
    end
  end)

  vim.notify("Paragraph spacing: " .. new_spacing, vim.log.levels.INFO)
end

function M.decrease_paragraph_spacing()
  local ctx = context.current()
  if not ctx then return end

  -- Ensure typography config exists
  context.config.typography = context.config.typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  local current = context.config.typography.paragraph_spacing
  local new_spacing = math.max(1, current - 1)  -- Min 1
  context.config.typography.paragraph_spacing = new_spacing

  -- Save view (viewport position) to prevent text from jumping
  local view = vim.fn.winsaveview()

  -- Invalidate cache since parsing depends on typography
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, view.lnum, ctx)

  -- Restore view (keeps text at same visual position)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
      vim.fn.winrestview(view)
    end
  end)

  vim.notify("Paragraph spacing: " .. new_spacing, vim.log.levels.INFO)
end

function M.reset_line_spacing()
  local ctx = context.current()
  if not ctx then return end

  -- Ensure typography config exists
  context.config.typography = context.config.typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  context.config.typography.line_spacing = 1

  -- Save view (viewport position) to prevent text from jumping
  local view = vim.fn.winsaveview()

  -- Invalidate cache since parsing depends on typography
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, view.lnum, ctx)

  -- Restore view (keeps text at same visual position)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
      vim.fn.winrestview(view)
    end
  end)

  vim.notify("Line spacing reset: 1", vim.log.levels.INFO)
end

function M.reset_paragraph_spacing()
  local ctx = context.current()
  if not ctx then return end

  -- Ensure typography config exists
  context.config.typography = context.config.typography or {
    line_spacing = 1,
    paragraph_spacing = 1,
    indent_size = 4,
    list_indent = 2
  }

  context.config.typography.paragraph_spacing = 1

  -- Save view (viewport position) to prevent text from jumping
  local view = vim.fn.winsaveview()

  -- Invalidate cache since parsing depends on typography
  ctx.parsed_chapters:clear()
  ctx.search_index = nil
  render.invalidate_glossary_cache(ctx)
  render.render_chapter(ctx.current_chapter_idx, view.lnum, ctx)

  -- Restore view (keeps text at same visual position)
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
      vim.fn.winrestview(view)
    end
  end)

  vim.notify("Paragraph spacing reset: 1", vim.log.levels.INFO)
end

return M
