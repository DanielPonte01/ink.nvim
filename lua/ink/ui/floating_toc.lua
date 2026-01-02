-- lua/ink/ui/floating_toc.lua
-- Floating Table of Contents with preview

local context = require("ink.ui.context")
local render = require("ink.ui.render")

local M = {}

-- Track floating TOC state
local floating_state = {
  toc_buf = nil,
  toc_win = nil,
  preview_buf = nil,
  preview_win = nil,
  ctx = nil,
  preview_cache = {}, -- Cache parsed chapters for preview
}

-- Find TOC item index for current chapter
local function find_current_toc_index(ctx)
  local current_spine_href = ctx.data.spine[ctx.current_chapter_idx].href

  for i, item in ipairs(ctx.data.toc) do
    if item.href then
      local item_href = item.href:match("^([^#]+)") or item.href
      if item_href == current_spine_href then
        return i
      end
    end
  end

  return 1
end

-- Render TOC lines with current position indicator
local function render_toc_lines(ctx)
  local lines = {}
  local current_idx = find_current_toc_index(ctx)

  -- Title
  table.insert(lines, "")

  for i, item in ipairs(ctx.data.toc) do
    local indent = string.rep(" ", (item.level or 0) + 2)
    local label = item.label:gsub("[\r\n]+", " ")

    -- Add indicator for current position
    local indicator = ""
    if i == current_idx then
      indicator = "  ← Here"
    end

    table.insert(lines, indent .. label .. indicator)
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, "  [j/k: navigate | Enter: jump | q: close]")

  return lines, current_idx
end

-- Get preview lines for a TOC item
local function get_preview_lines(toc_item, ctx)
  if not toc_item or not toc_item.href then
    return {"", "  No preview available", ""}
  end

  -- Parse href
  local target_href = toc_item.href:match("^([^#]+)") or toc_item.href
  local anchor = toc_item.href:match("#(.+)$")

  -- Find chapter in spine
  local chapter_idx = nil
  for i, spine_item in ipairs(ctx.data.spine) do
    if spine_item.href == target_href then
      chapter_idx = i
      break
    end
  end

  if not chapter_idx then
    return {"", "  Chapter not found", ""}
  end

  -- Check cache first
  local parsed = floating_state.preview_cache[chapter_idx]

  if not parsed then
    -- Get chapter content and parse with wider width for preview
    local content = render.get_chapter_content(chapter_idx, ctx)
    if not content then
      return {"", "  Failed to load chapter", ""}
    end

    -- Parse with preview-specific width (optimized for small screens)
    local html = require("ink.html")
    local preview_width = 55 -- Fixed width for preview, works well on 1366px screens
    local class_styles = ctx.data.class_styles or {}
    parsed = html.parse(content, preview_width, class_styles, false) -- No justify for preview

    if not parsed or not parsed.lines then
      return {"", "  Failed to parse chapter", ""}
    end

    -- Cache the result
    floating_state.preview_cache[chapter_idx] = parsed
  end

  -- Extract first N lines (skip empty lines at start)
  local preview_lines = {}
  local line_count = 0
  local max_lines = 15
  local start_line = 1

  -- If there's an anchor, try to start from there
  if anchor and parsed.anchors and parsed.anchors[anchor] then
    start_line = parsed.anchors[anchor]
  end

  for i = start_line, #parsed.lines do
    local line = parsed.lines[i]
    -- Skip empty lines at the beginning
    if line_count == 0 and line:match("^%s*$") then
      goto continue
    end

    table.insert(preview_lines, "  " .. line)
    line_count = line_count + 1

    if line_count >= max_lines then
      break
    end

    ::continue::
  end

  if #preview_lines == 0 then
    return {"", "  (Empty chapter)", ""}
  end

  -- Add title
  table.insert(preview_lines, 1, "")
  table.insert(preview_lines, #preview_lines + 1, "")
  table.insert(preview_lines, #preview_lines + 1, "  [Preview - first " .. line_count .. " lines]")

  return preview_lines
end

-- Update preview window content
local function update_preview(line_num, ctx)
  if not floating_state.preview_buf or not vim.api.nvim_buf_is_valid(floating_state.preview_buf) then
    return
  end

  -- Adjust for title line (skip first line)
  local toc_idx = line_num - 1

  if toc_idx < 1 or toc_idx > #ctx.data.toc then
    return
  end

  local toc_item = ctx.data.toc[toc_idx]
  local preview_lines = get_preview_lines(toc_item, ctx)

  vim.api.nvim_set_option_value("modifiable", true, { buf = floating_state.preview_buf })
  vim.api.nvim_buf_set_lines(floating_state.preview_buf, 0, -1, false, preview_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = floating_state.preview_buf })

  -- Reset scroll to top
  if floating_state.preview_win and vim.api.nvim_win_is_valid(floating_state.preview_win) then
    vim.api.nvim_win_set_cursor(floating_state.preview_win, {1, 0})
  end
end

-- Calculate window dimensions (split layout)
local function get_window_configs()
  local ui_width = vim.o.columns
  local ui_height = vim.o.lines

  -- Total window size: optimized for small screens (1366px notebooks)
  local total_width = math.floor(ui_width * 0.70)  -- 70% instead of 80%
  local total_height = math.floor(ui_height * 0.70)

  -- Center position
  local row = math.floor((ui_height - total_height) / 2)
  local col = math.floor((ui_width - total_width) / 2)

  -- Split widths: TOC 30%, Preview 70% (more space for preview)
  local toc_width = math.floor(total_width * 0.30)
  local preview_width = total_width - toc_width - 1 -- -1 for border

  local toc_config = {
    relative = "editor",
    width = toc_width,
    height = total_height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Table of Contents ",
    title_pos = "center",
  }

  local preview_config = {
    relative = "editor",
    width = preview_width,
    height = total_height,
    row = row,
    col = col + toc_width + 1,
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
  }

  return toc_config, preview_config
end

-- Navigate to selected TOC item
local function navigate_to_item(line_num, ctx)
  -- Adjust for title line (skip first line)
  local toc_idx = line_num - 1

  if toc_idx < 1 or toc_idx > #ctx.data.toc then
    return
  end

  local toc_item = ctx.data.toc[toc_idx]
  if not toc_item or not toc_item.href then
    return
  end

  -- Parse href
  local target_href = toc_item.href:match("^([^#]+)") or toc_item.href
  local anchor = toc_item.href:match("#(.+)$")

  -- Find chapter in spine
  for i, spine_item in ipairs(ctx.data.spine) do
    if spine_item.href == target_href then
      render.render_chapter(i, nil, ctx)

      -- Jump to anchor if present
      if anchor and ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
        vim.schedule(function()
          if ctx.anchors[anchor] then
            vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[anchor], 0})
            vim.cmd("normal! zz")
          end
        end)
      end

      break
    end
  end
end

-- Close floating TOC and preview
local function close_floating_toc()
  if floating_state.toc_win and vim.api.nvim_win_is_valid(floating_state.toc_win) then
    vim.api.nvim_win_close(floating_state.toc_win, true)
  end

  if floating_state.preview_win and vim.api.nvim_win_is_valid(floating_state.preview_win) then
    vim.api.nvim_win_close(floating_state.preview_win, true)
  end

  floating_state.toc_win = nil
  floating_state.toc_buf = nil
  floating_state.preview_win = nil
  floating_state.preview_buf = nil
  floating_state.ctx = nil
  floating_state.preview_cache = {} -- Clear preview cache
end

-- Setup buffer keymaps
local function setup_keymaps(toc_buf, ctx)
  local opts = { buffer = toc_buf, noremap = true, silent = true }

  -- Close with q or Esc
  vim.keymap.set("n", "q", close_floating_toc, opts)
  vim.keymap.set("n", "<Esc>", close_floating_toc, opts)

  -- Navigate and jump
  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(floating_state.toc_win)
    navigate_to_item(cursor[1], ctx)
    close_floating_toc()
  end, opts)

  -- Update preview on cursor move
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = toc_buf,
    callback = function()
      if floating_state.toc_win and vim.api.nvim_win_is_valid(floating_state.toc_win) then
        local cursor = vim.api.nvim_win_get_cursor(floating_state.toc_win)
        update_preview(cursor[1], ctx)
      end
    end,
  })

  -- Auto-close when leaving buffer
  vim.api.nvim_create_autocmd({"BufLeave", "WinLeave"}, {
    buffer = toc_buf,
    callback = close_floating_toc,
    once = true,
  })
end

-- Show floating TOC with preview
function M.show_floating_toc(ctx)
  ctx = ctx or context.current()
  if not ctx then return end

  -- Close if already open
  if floating_state.toc_win and vim.api.nvim_win_is_valid(floating_state.toc_win) then
    close_floating_toc()
    return
  end

  -- Check if TOC is empty
  if #ctx.data.toc == 0 then
    vim.notify("Table of contents is empty", vim.log.levels.WARN)
    return
  end

  -- Create buffers
  local toc_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = toc_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = toc_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = toc_buf })
  vim.api.nvim_set_option_value("filetype", "ink-toc", { buf = toc_buf })

  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = preview_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = preview_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = preview_buf })
  vim.api.nvim_set_option_value("filetype", "ink-preview", { buf = preview_buf })

  -- Render TOC content
  local lines, current_idx = render_toc_lines(ctx)
  vim.api.nvim_buf_set_lines(toc_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = toc_buf })

  -- Create floating windows
  local toc_config, preview_config = get_window_configs()
  local toc_win = vim.api.nvim_open_win(toc_buf, true, toc_config)
  local preview_win = vim.api.nvim_open_win(preview_buf, false, preview_config)

  -- Window options for TOC
  vim.api.nvim_set_option_value("number", false, { win = toc_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = toc_win })
  vim.api.nvim_set_option_value("cursorline", true, { win = toc_win })
  vim.api.nvim_set_option_value("wrap", false, { win = toc_win })

  -- Window options for Preview
  vim.api.nvim_set_option_value("number", false, { win = preview_win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = preview_win })
  vim.api.nvim_set_option_value("cursorline", false, { win = preview_win })
  vim.api.nvim_set_option_value("wrap", true, { win = preview_win })

  -- Save state
  floating_state.toc_buf = toc_buf
  floating_state.toc_win = toc_win
  floating_state.preview_buf = preview_buf
  floating_state.preview_win = preview_win
  floating_state.ctx = ctx

  -- Set cursor to current chapter (adjust for title line)
  vim.api.nvim_win_set_cursor(toc_win, {current_idx + 1, 0})

  -- Initial preview update
  update_preview(current_idx + 1, ctx)

  -- Setup keymaps (must be after saving state)
  setup_keymaps(toc_buf, ctx)
end

-- Toggle floating TOC
function M.toggle_floating_toc(ctx)
  ctx = ctx or context.current()
  if not ctx then return end

  if floating_state.toc_win and vim.api.nvim_win_is_valid(floating_state.toc_win) then
    close_floating_toc()
  else
    M.show_floating_toc(ctx)
  end
end

return M
