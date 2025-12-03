local html = require("ink.html")
local fs = require("ink.fs")
local state = require("ink.state")
local user_highlights = require("ink.user_highlights")

local M = {
  config = { max_width = 120 }
}

function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config or {})
end

-- Current book context
local ctx = {
  data = nil,
  current_chapter_idx = 1,
  toc_buf = nil,
  content_buf = nil,
  toc_win = nil,
  content_win = nil,
  ns_id = vim.api.nvim_create_namespace("ink_nvim"),
  images = {}, -- Store image data for current chapter
  links = {},   -- Store link data for current chapter
  anchors = {},  -- Store anchor data for current chapter
  last_statusline_percent = 0  -- Track last percentage to reduce updates
}

-- Helper to open image
local function open_image(src)
  -- Image paths in HTML are relative to the chapter file, not base_dir
  -- Get the current chapter's directory
  local chapter_item = ctx.data.spine[ctx.current_chapter_idx]
  local chapter_path = ctx.data.base_dir .. "/" .. chapter_item.href
  local chapter_dir = vim.fn.fnamemodify(chapter_path, ":h")

  -- Resolve image path relative to chapter directory
  local image_path = chapter_dir .. "/" .. src
  -- Normalize the path (resolve .. and . components)
  image_path = vim.fn.resolve(image_path)

  -- SECURITY: Validate image is within cache directory (prevent path traversal)
  local cache_root = vim.fn.resolve(ctx.data.cache_dir)
  if image_path:sub(1, #cache_root) ~= cache_root then
    vim.notify("Access denied: Image path outside EPUB cache", vim.log.levels.ERROR)
    return
  end

  -- Check if image exists
  if not fs.exists(image_path) then
    vim.notify("Image not found: " .. src, vim.log.levels.ERROR)
    return
  end

  -- Determine open command based on OS and build command array
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = {"open", image_path}
  elseif vim.fn.has("unix") == 1 then
    cmd = {"xdg-open", image_path}
  elseif vim.fn.has("win32") == 1 then
    -- Windows cmd requires special handling
    cmd = {"cmd", "/c", "start", "", image_path}
  end

  if not cmd then
    vim.notify("Could not determine image viewer command for your OS", vim.log.levels.ERROR)
    return
  end

  -- Use vim.fn.jobstart for safer async command execution
  local job_id = vim.fn.jobstart(cmd, {
    detach = true,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.notify("Failed to open image: " .. src, vim.log.levels.ERROR)
      end
    end
  })

  if job_id <= 0 then
    vim.notify("Failed to start image viewer", vim.log.levels.ERROR)
  end
end

local function update_statusline()
  if not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then return end

  local total = #ctx.data.spine
  local current = ctx.current_chapter_idx

  -- Calculate percentage of current chapter
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local current_line = cursor[1]
  local total_lines = vim.api.nvim_buf_line_count(ctx.content_buf)
  local percent = math.floor((current_line / total_lines) * 100)

  -- Simple progress bar
  local bar_len = 10
  local filled = math.floor((percent / 100) * bar_len)
  local bar = string.rep("█", filled) .. string.rep("▒", bar_len - filled)

  -- Get chapter name from TOC
  local chapter_name = nil
  local current_href = ctx.data.spine[current].href

  -- Try to find matching TOC entry
  for _, toc_item in ipairs(ctx.data.toc) do
    -- Normalize href (remove anchor)
    local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
    if toc_href == current_href then
      chapter_name = toc_item.label
      break
    end
  end

  -- Fallback to "Chapter X" if no TOC entry found
  if not chapter_name then
    chapter_name = "Chapter " .. current
  end

  local status = string.format(" %s %d%%%% | %s | %d/%d ", bar, percent, chapter_name, current, total)
  vim.api.nvim_set_option_value("statusline", status, { win = ctx.content_win })
end

function M.render_chapter(idx, restore_line)
  if idx < 1 or idx > #ctx.data.spine then return end
  ctx.current_chapter_idx = idx
  ctx.last_statusline_percent = 0  -- Reset percentage tracking for new chapter

  -- Check if content window is still valid, if not recreate it
  if not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then
    -- Find if there's already a window showing the content buffer
    local found_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if buf == ctx.content_buf then
          found_win = win
          break
        end
      end
    end

    if found_win then
      -- Reuse existing window
      ctx.content_win = found_win
    else
      -- Create new window - split from current window
      vim.cmd("vsplit")
      local new_win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(new_win, ctx.content_buf)
      ctx.content_win = new_win
    end
  end

  local item = ctx.data.spine[idx]
  local path = ctx.data.base_dir .. "/" .. item.href
  local content = fs.read_file(path)

  if not content then
    vim.api.nvim_buf_set_lines(ctx.content_buf, 0, -1, false, {"Error reading chapter"})
    return
  end

  local max_width = M.config.max_width or 120
  local class_styles = ctx.data.class_styles or {}
  local parsed = html.parse(content, max_width, class_styles)

  -- Calculate padding for centering
  local win_width = vim.api.nvim_win_get_width(ctx.content_win)
  local padding = 0
  if win_width > max_width then
    padding = math.floor((win_width - max_width) / 2)
  end
  
  -- Apply padding
  if padding > 0 then
    local pad_str = string.rep(" ", padding)
    for i, line in ipairs(parsed.lines) do
      parsed.lines[i] = pad_str .. line
    end
    
    -- Shift highlights
    for _, hl in ipairs(parsed.highlights) do
      hl[2] = hl[2] + padding
      hl[3] = hl[3] + padding
    end
    
    -- Shift links
    for _, link in ipairs(parsed.links) do
      link[2] = link[2] + padding
      link[3] = link[3] + padding
    end
    
    -- Shift images
    for _, img in ipairs(parsed.images) do
      img[2] = img[2] + padding
      img[3] = img[3] + padding
    end
  end
  
  -- Set text
  vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.content_buf })
  vim.api.nvim_buf_set_lines(ctx.content_buf, 0, -1, false, parsed.lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.content_buf })
  
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(ctx.content_buf, ctx.ns_id, 0, -1)
  
  -- Apply highlights (with validation to prevent out-of-range errors)
  for _, hl in ipairs(parsed.highlights) do
    -- hl: { line (1-based), col_start, col_end, group }
    local line_idx = hl[1] - 1  -- Convert to 0-based
    local start_col = hl[2]
    local end_col = hl[3]

    -- Validate line exists
    if line_idx >= 0 and line_idx < #parsed.lines then
      local line_length = #parsed.lines[line_idx + 1]

      -- Clamp columns to line length
      start_col = math.min(start_col, line_length)
      end_col = math.min(end_col, line_length)

      -- Only apply if we have a valid range
      if start_col < end_col then
        vim.api.nvim_buf_set_extmark(ctx.content_buf, ctx.ns_id, line_idx, start_col, {
          end_col = end_col,
          hl_group = hl[4],
          priority = 1000,  -- Very high priority
          hl_mode = "combine"  -- Combine with existing highlights
        })
      end
    end
  end
  
  ctx.images = parsed.images
  ctx.links = parsed.links
  ctx.anchors = parsed.anchors

  -- Apply user highlights
  local chapter_highlights = user_highlights.get_chapter_highlights(ctx.data.slug, idx)
  for _, hl in ipairs(chapter_highlights) do
    local start_line = hl.start_line - 1  -- Convert to 0-based
    local end_line = hl.end_line - 1

    -- Apply padding shift to columns
    local start_col = hl.start_col + padding
    local end_col = hl.end_col + padding

    -- Validate lines exist
    if start_line >= 0 and start_line < #parsed.lines and end_line >= 0 and end_line < #parsed.lines then
      -- Validate and clamp columns
      local start_line_length = #parsed.lines[start_line + 1]
      local end_line_length = #parsed.lines[end_line + 1]

      start_col = math.min(start_col, start_line_length)
      end_col = math.min(end_col, end_line_length)

      -- Apply highlight
      local hl_group = "InkUserHighlight_" .. hl.color
      vim.api.nvim_buf_set_extmark(ctx.content_buf, ctx.ns_id, start_line, start_col, {
        end_line = end_line,
        end_col = end_col,
        hl_group = hl_group,
        priority = 2000  -- Higher priority than text formatting
      })
    end
  end

  -- Restore position (with safety check)
  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    if restore_line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {restore_line, 0})
    else
      vim.api.nvim_win_set_cursor(ctx.content_win, {1, 0})
    end
  end

  update_statusline()
  
  -- Save state
  state.save(ctx.data.slug, { chapter = idx, line = restore_line or 1 })
end

function M.render_toc()
  vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.toc_buf })
  local lines = {}
  for _, item in ipairs(ctx.data.toc) do
    local indent = string.rep("  ", (item.level or 1) - 1)
    table.insert(lines, indent .. item.label)
  end
  vim.api.nvim_buf_set_lines(ctx.toc_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.toc_buf })
end

function M.toggle_toc()
  if ctx.toc_win and vim.api.nvim_win_is_valid(ctx.toc_win) then
    vim.api.nvim_win_close(ctx.toc_win, true)
    ctx.toc_win = nil
  else
    -- Open TOC sidebar
    vim.cmd("topleft vsplit")
    ctx.toc_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(ctx.toc_win, ctx.toc_buf)
    vim.api.nvim_win_set_width(ctx.toc_win, 30)
    vim.api.nvim_set_option_value("number", false, { win = ctx.toc_win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = ctx.toc_win })
    vim.api.nvim_set_option_value("wrap", false, { win = ctx.toc_win })
  end
end

function M.next_chapter()
  M.render_chapter(ctx.current_chapter_idx + 1)
end

function M.prev_chapter()
  M.render_chapter(ctx.current_chapter_idx - 1)
end

function M.handle_enter()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local buf = vim.api.nvim_get_current_buf()
  
  if buf == ctx.toc_buf then
    -- Jump to chapter from TOC
    local toc_item = ctx.data.toc[line]
    if toc_item then
      -- Normalize href (remove anchor)
      local target_href = toc_item.href:match("^([^#]+)") or toc_item.href
      local anchor = toc_item.href:match("#(.+)$")
      
      for i, spine_item in ipairs(ctx.data.spine) do
        if spine_item.href == target_href then
          M.render_chapter(i)
          -- Switch focus to content window
          if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
            vim.api.nvim_set_current_win(ctx.content_win)
            
            -- Jump to anchor if present
            if anchor and ctx.anchors[anchor] then
               vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[anchor], 0})
            end
          end
          break
        end
      end
    end
  elseif buf == ctx.content_buf then
    -- Check for image
    for _, img in ipairs(ctx.images) do
      -- Check if cursor is on the image line
      if img[1] == line then
        open_image(img[4])
        return
      end
    end
  end
end

-- Add highlight to current visual selection
function M.add_highlight(color)
  local buf = vim.api.nvim_get_current_buf()

  -- Only work in content buffer
  if buf ~= ctx.content_buf then
    vim.notify("Highlights can only be added in the content buffer", vim.log.levels.WARN)
    return
  end

  -- Verify color exists in config
  if not M.config.highlight_colors[color] then
    vim.notify("Unknown highlight color: " .. color, vim.log.levels.ERROR)
    return
  end

  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local start_col = start_pos[3] - 1  -- Convert to 0-based
  local end_line = end_pos[2]
  local end_col = end_pos[3]  -- Already exclusive

  -- Calculate window padding to adjust positions back
  local win_width = vim.api.nvim_win_get_width(ctx.content_win)
  local max_width = M.config.max_width or 120
  local padding = 0
  if win_width > max_width then
    padding = math.floor((win_width - max_width) / 2)
  end

  -- Store highlight with positions adjusted for padding (unpadded positions)
  -- Clamp to ensure we don't highlight padding area
  local adjusted_start_col = math.max(0, start_col - padding)
  local adjusted_end_col = math.max(0, end_col - padding)

  -- If the selection starts in the padding area, move it to the start of actual content
  if start_col < padding then
    adjusted_start_col = 0
  end

  -- Skip if the entire selection is in the padding area
  if end_col <= padding then
    vim.notify("Selection is in padding area, no highlight added", vim.log.levels.WARN)
    return
  end

  local highlight = {
    chapter = ctx.current_chapter_idx,
    start_line = start_line,
    start_col = adjusted_start_col,
    end_line = end_line,
    end_col = adjusted_end_col,
    color = color
  }

  user_highlights.add_highlight(ctx.data.slug, highlight)

  -- Re-render to show the new highlight
  -- Place cursor at the END of selection (for reading flow)
  M.render_chapter(ctx.current_chapter_idx, end_line)

  -- Restore cursor position at end of selection
  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    vim.api.nvim_win_set_cursor(ctx.content_win, {end_line, end_col})
  end

  vim.notify("Highlight added", vim.log.levels.INFO)
end

-- Remove highlight under cursor
function M.remove_highlight()
  local buf = vim.api.nvim_get_current_buf()

  -- Only work in content buffer
  if buf ~= ctx.content_buf then
    vim.notify("Highlights can only be removed in the content buffer", vim.log.levels.WARN)
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  -- Calculate window padding to adjust positions
  local win_width = vim.api.nvim_win_get_width(ctx.content_win)
  local max_width = M.config.max_width or 120
  local padding = 0
  if win_width > max_width then
    padding = math.floor((win_width - max_width) / 2)
  end

  -- Adjust for padding (convert to unpadded position)
  local adjusted_col = col - padding

  local removed = user_highlights.remove_highlight(ctx.data.slug, ctx.current_chapter_idx, line, adjusted_col)

  -- Re-render to remove the highlight
  M.render_chapter(ctx.current_chapter_idx, line)

  -- Restore cursor position exactly where it was
  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    vim.api.nvim_win_set_cursor(ctx.content_win, cursor)
  end

  vim.notify("Highlight removed", vim.log.levels.INFO)
end

function M.setup_keymaps(buf)
  local opts = { noremap = true, silent = true }
  local keymaps = M.config.keymaps or {}

  if keymaps.next_chapter then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.next_chapter, ":lua require('ink.ui').next_chapter()<CR>", opts)
  end

  if keymaps.prev_chapter then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.prev_chapter, ":lua require('ink.ui').prev_chapter()<CR>", opts)
  end

  if keymaps.activate then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.activate, ":lua require('ink.ui').handle_enter()<CR>", opts)
  end
end

function M.open_book(epub_data)
  ctx.data = epub_data

  -- Helper function to find buffer by name
  local function find_buf_by_name(name)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(buf) then
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name == name then
          return buf
        end
      end
    end
    return nil
  end

  -- Generate buffer names
  local toc_name = "ink://" .. epub_data.slug .. "/TOC"
  local content_name = "ink://" .. epub_data.slug .. "/content"

  -- Check if buffers already exist and delete them
  local existing_toc = find_buf_by_name(toc_name)
  if existing_toc then
    vim.api.nvim_buf_delete(existing_toc, { force = true })
  end

  local existing_content = find_buf_by_name(content_name)
  if existing_content then
    vim.api.nvim_buf_delete(existing_content, { force = true })
  end

  -- Create new buffers
  ctx.toc_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(ctx.toc_buf, toc_name)
  vim.api.nvim_set_option_value("filetype", "ink_toc", { buf = ctx.toc_buf })

  ctx.content_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(ctx.content_buf, content_name)
  vim.api.nvim_set_option_value("filetype", "ink_content", { buf = ctx.content_buf })
  vim.api.nvim_set_option_value("syntax", "off", { buf = ctx.content_buf })  -- Disable syntax highlighting
  
  -- Setup Layout
  vim.cmd("tabnew")
  ctx.content_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(ctx.content_win, ctx.content_buf)
  
  -- Render TOC
  M.render_toc()
  M.toggle_toc() -- Open TOC by default
  
  -- Restore state or start at 1
  local saved = state.load(epub_data.slug)
  if saved then
    M.render_chapter(saved.chapter, saved.line)
  else
    M.render_chapter(1)
  end
  
  -- Keymaps
  M.setup_keymaps(ctx.content_buf)
  M.setup_keymaps(ctx.toc_buf)

  -- Add toggle TOC keymap to both buffers
  local keymaps = M.config.keymaps or {}
  if keymaps.toggle_toc then
    local toggle_opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(ctx.content_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", toggle_opts)
    vim.api.nvim_buf_set_keymap(ctx.toc_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", toggle_opts)
  end

  -- Setup user highlight keymaps (visual mode only, content buffer only)
  local highlight_keymaps = M.config.highlight_keymaps or {}
  local hl_opts = { noremap = true, silent = true }

  for color_name, keymap in pairs(highlight_keymaps) do
    if color_name == "remove" then
      -- Remove highlight (normal mode)
      vim.api.nvim_buf_set_keymap(ctx.content_buf, "n", keymap,
        ":lua require('ink.ui').remove_highlight()<CR>", hl_opts)
    else
      -- Add highlight (visual mode)
      vim.api.nvim_buf_set_keymap(ctx.content_buf, "v", keymap,
        string.format(":lua require('ink.ui').add_highlight('%s')<CR>", color_name), hl_opts)
    end
  end

  -- Setup autocmds
  local augroup = vim.api.nvim_create_augroup("Ink_" .. epub_data.slug, { clear = true })

  -- Window resize
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup,
    callback = function()
      -- Only re-render if the content window was resized and is still valid
      if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
        local resized_wins = vim.v.event.windows or {}
        for _, win_id in ipairs(resized_wins) do
          if win_id == ctx.content_win then
            -- Preserve cursor position
            local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
            local current_line = cursor[1]
            -- Re-render current chapter with preserved position
            M.render_chapter(ctx.current_chapter_idx, current_line)
            break
          end
        end
      end
    end,
  })

  -- Update statusline on cursor movement (for chapter progress)
  -- Only update when percentage changes by 10% or more to reduce distraction
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = augroup,
    buffer = ctx.content_buf,
    callback = function()
      if not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then return end

      -- Calculate current percentage
      local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
      local current_line = cursor[1]
      local total_lines = vim.api.nvim_buf_line_count(ctx.content_buf)
      local percent = math.floor((current_line / total_lines) * 100)

      -- Only update if percentage changed by 10% or more
      if math.abs(percent - ctx.last_statusline_percent) >= 10 then
        ctx.last_statusline_percent = percent
        update_statusline()
      end
    end,
  })
end

return M
