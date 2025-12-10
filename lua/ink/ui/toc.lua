-- lua/ink/ui/toc.lua
-- Responsabilidade: Gerenciamento de Table of Contents (TOC)

local context = require("ink.ui.context")

local M = {}

function M.render_toc(ctx)
  ctx = ctx or context.current()
  if not ctx then return end

  -- Lazy load TOC if not yet generated (happens when skip_toc_generation was used)
  if #ctx.data.toc == 0 then
    vim.notify("Building table of contents...", vim.log.levels.INFO)

    -- Build TOC from content in background
    vim.schedule(function()
      local epub = require("ink.epub")
      local toc_cache = require("ink.toc_cache")

      local content_toc = epub.build_toc_from_content(ctx.data.spine, ctx.data.base_dir, ctx.data.class_styles)

      if #content_toc > 0 then
        ctx.data.toc = content_toc
        -- Save to cache
        toc_cache.save(ctx.data.slug, content_toc)
      end

      -- Render the TOC now that it's built
      vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.toc_buf })
      local lines = {}
      for _, item in ipairs(ctx.data.toc) do
        -- Level 0 (titles) = no indent, Level 1/2/3 (H1/H2/H3) = 1/2/3 spaces
        local indent = string.rep(" ", item.level or 0)
        table.insert(lines, indent .. item.label)
      end
      vim.api.nvim_buf_set_lines(ctx.toc_buf, 0, -1, false, lines)
      vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.toc_buf })

      vim.notify("Table of contents ready!", vim.log.levels.INFO)
    end)

    return
  end

  -- Normal render if TOC already exists
  vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.toc_buf })
  local lines = {}
  for _, item in ipairs(ctx.data.toc) do
    -- Level 0 (titles) = no indent, Level 1/2/3 (H1/H2/H3) = 1/2/3 spaces
    local indent = string.rep(" ", item.level or 0)
    table.insert(lines, indent .. item.label)
  end
  vim.api.nvim_buf_set_lines(ctx.toc_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.toc_buf })
end

function M.toggle_toc(ctx)
  ctx = ctx or context.current()
  if not ctx then return end
  if ctx.toc_win and vim.api.nvim_win_is_valid(ctx.toc_win) then
    vim.api.nvim_win_close(ctx.toc_win, true)
    ctx.toc_win = nil
  else
    vim.cmd("topleft vsplit")
    ctx.toc_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(ctx.toc_win, ctx.toc_buf)
    vim.api.nvim_win_set_width(ctx.toc_win, 30)
    vim.api.nvim_set_option_value("number", false, { win = ctx.toc_win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = ctx.toc_win })
    vim.api.nvim_set_option_value("wrap", false, { win = ctx.toc_win })
  end
end

return M
