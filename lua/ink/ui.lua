local html = require("ink.html")
local fs = require("ink.fs")
local state = require("ink.state")

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
  anchors = {}  -- Store anchor data for current chapter
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

  -- Check if image exists
  if not fs.exists(image_path) then
    vim.notify("Image not found: " .. src, vim.log.levels.ERROR)
    return
  end

  -- Determine open command based on OS
  local open_cmd
  if vim.fn.has("mac") == 1 then
    open_cmd = "open"
  elseif vim.fn.has("unix") == 1 then
    open_cmd = "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    open_cmd = "start"
  end

  if not open_cmd then
    vim.notify("Could not determine image viewer command for your OS", vim.log.levels.ERROR)
    return
  end

  -- Open the image directly from cache (no need to copy)
  local cmd = string.format("%s %s &", open_cmd, vim.fn.shellescape(image_path))
  local success = os.execute(cmd)

  if not success then
    vim.notify("Failed to open image: " .. src, vim.log.levels.ERROR)
  end
end

local function update_statusline()
  if not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then return end
  
  local total = #ctx.data.spine
  local current = ctx.current_chapter_idx
  local percent = math.floor((current / total) * 100)
  
  -- Simple progress bar
  local bar_len = 10
  local filled = math.floor((percent / 100) * bar_len)
  local bar = string.rep("█", filled) .. string.rep("▒", bar_len - filled)
  
  local status = string.format(" %s %d%%%% | Chapter %d/%d ", bar, percent, current, total)
  vim.api.nvim_win_set_option(ctx.content_win, "statusline", status)
end

function M.render_chapter(idx, restore_line)
  if idx < 1 or idx > #ctx.data.spine then return end
  ctx.current_chapter_idx = idx

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
  local parsed = html.parse(content, max_width)

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
  vim.api.nvim_buf_set_option(ctx.content_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(ctx.content_buf, 0, -1, false, parsed.lines)
  vim.api.nvim_buf_set_option(ctx.content_buf, "modifiable", false)
  
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
      if start_col <= end_col then
        vim.api.nvim_buf_set_extmark(ctx.content_buf, ctx.ns_id, line_idx, start_col, {
          end_col = end_col,
          hl_group = hl[4]
        })
      end
    end
  end
  
  ctx.images = parsed.images
  ctx.links = parsed.links
  ctx.anchors = parsed.anchors

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
  vim.api.nvim_buf_set_option(ctx.toc_buf, "modifiable", true)
  local lines = {}
  for _, item in ipairs(ctx.data.toc) do
    local indent = string.rep("  ", (item.level or 1) - 1)
    table.insert(lines, indent .. item.label)
  end
  vim.api.nvim_buf_set_lines(ctx.toc_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(ctx.toc_buf, "modifiable", false)
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
    vim.api.nvim_win_set_option(ctx.toc_win, "number", false)
    vim.api.nvim_win_set_option(ctx.toc_win, "relativenumber", false)
    vim.api.nvim_win_set_option(ctx.toc_win, "wrap", false)
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

function M.setup_keymaps(buf)
  local opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(buf, "n", "]c", ":lua require('ink.ui').next_chapter()<CR>", opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "[c", ":lua require('ink.ui').prev_chapter()<CR>", opts)
  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", ":lua require('ink.ui').handle_enter()<CR>", opts)
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
  vim.api.nvim_buf_set_option(ctx.toc_buf, "filetype", "ink_toc")

  ctx.content_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(ctx.content_buf, content_name)
  vim.api.nvim_buf_set_option(ctx.content_buf, "filetype", "ink_content")
  
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
  local toggle_opts = { noremap = true, silent = true }
  vim.api.nvim_buf_set_keymap(ctx.content_buf, "n", "<leader>t", ":lua require('ink.ui').toggle_toc()<CR>", toggle_opts)
  vim.api.nvim_buf_set_keymap(ctx.toc_buf, "n", "<leader>t", ":lua require('ink.ui').toggle_toc()<CR>", toggle_opts)

  -- Setup autocmd for window resize
  local augroup = vim.api.nvim_create_augroup("InkResize_" .. epub_data.slug, { clear = true })
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
end

return M
