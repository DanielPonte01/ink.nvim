local html = require("ink.html")
local fs = require("ink.fs")
local state = require("ink.state")
local user_highlights = require("ink.user_highlights")
local library = require("ink.library")

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
  justify_map = {},  -- Store justify mapping for user highlights
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

-- Helper to show footnote in floating window
local function show_footnote_preview(anchor_id)
  local anchor_line = ctx.anchors[anchor_id]
  if not anchor_line then
    vim.notify("Footnote not found: " .. anchor_id, vim.log.levels.WARN)
    return false
  end

  -- Get buffer lines starting from anchor
  local total_lines = vim.api.nvim_buf_line_count(ctx.content_buf)
  local max_preview_lines = 15
  local end_line = math.min(anchor_line + max_preview_lines - 1, total_lines)

  local lines = vim.api.nvim_buf_get_lines(ctx.content_buf, anchor_line - 1, end_line, false)

  -- Trim empty lines from start and end
  while #lines > 0 and lines[1]:match("^%s*$") do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end

  -- Find where footnote ends (next blank line or reasonable cutoff)
  local footnote_lines = {}
  local found_content = false
  for _, line in ipairs(lines) do
    -- Skip leading empty lines
    if not found_content and line:match("^%s*$") then
      goto continue
    end
    found_content = true

    -- Stop at empty line after content (end of footnote)
    if found_content and line:match("^%s*$") then
      break
    end

    -- Trim leading/trailing whitespace for display
    table.insert(footnote_lines, line:match("^%s*(.-)%s*$"))

    ::continue::
  end

  if #footnote_lines == 0 then
    vim.notify("Empty footnote", vim.log.levels.WARN)
    return false
  end

  -- Calculate window dimensions
  local max_width = 60
  local width = 0
  for _, line in ipairs(footnote_lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 2, max_width)  -- Add padding, cap at max

  -- Wrap long lines
  local wrapped_lines = {}
  for _, line in ipairs(footnote_lines) do
    if #line > width - 2 then
      -- Simple word wrap
      local current = ""
      for word in line:gmatch("%S+") do
        if #current + #word + 1 > width - 2 then
          if #current > 0 then
            table.insert(wrapped_lines, current)
          end
          current = word
        else
          if current == "" then
            current = word
          else
            current = current .. " " .. word
          end
        end
      end
      if #current > 0 then
        table.insert(wrapped_lines, current)
      end
    else
      table.insert(wrapped_lines, line)
    end
  end

  local height = math.min(#wrapped_lines, 10)

  -- Create floating window
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, wrapped_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })

  -- Position near cursor
  local win_opts = {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Footnote ",
    title_pos = "center",
  }

  local float_win = vim.api.nvim_open_win(float_buf, false, win_opts)
  vim.api.nvim_set_option_value("winblend", 0, { win = float_win })
  vim.api.nvim_set_option_value("winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = float_win })

  -- Function to close the floating window and clean up
  local function close_float()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    -- Remove keymaps
    pcall(vim.keymap.del, "n", "q", { buffer = ctx.content_buf })
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = ctx.content_buf })
  end

  -- Close on cursor move or key press
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" }, {
    callback = function()
      close_float()
      return true  -- Delete this autocmd
    end,
    buffer = ctx.content_buf,
  })

  -- Also close on q or Escape
  vim.keymap.set("n", "q", close_float, { buffer = ctx.content_buf })
  vim.keymap.set("n", "<Esc>", close_float, { buffer = ctx.content_buf })

  return true
end

-- Helper to find link at cursor position
local function get_link_at_cursor(line, col)
  for _, link in ipairs(ctx.links) do
    if link[1] == line and col >= link[2] and col < link[3] then
      return link[4]  -- Return href
    end
  end
  return nil
end

-- Jump to link target (for Shift+Enter navigation)
local function jump_to_link()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]
  local buf = vim.api.nvim_get_current_buf()

  if buf ~= ctx.content_buf then
    return
  end

  local href = get_link_at_cursor(line, col)
  if not href then
    vim.notify("No link at cursor", vim.log.levels.INFO)
    return
  end

  -- Check if it's an internal anchor
  local anchor = href:match("^#(.+)$")
  if anchor then
    local anchor_line = ctx.anchors[anchor]
    if anchor_line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {anchor_line, 0})
      -- Center the view on the target
      vim.cmd("normal! zz")
      return
    else
      vim.notify("Anchor not found: " .. anchor, vim.log.levels.WARN)
      return
    end
  end

  -- Cross-chapter link
  local target_href = href:match("^([^#]+)") or href
  local target_anchor = href:match("#(.+)$")

  for i, spine_item in ipairs(ctx.data.spine) do
    local spine_filename = spine_item.href:match("([^/]+)$")
    local target_filename = target_href:match("([^/]+)$")
    if spine_filename == target_filename then
      M.render_chapter(i)
      if target_anchor and ctx.anchors[target_anchor] then
        vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[target_anchor], 0})
        vim.cmd("normal! zz")
      end
      return
    end
  end

  vim.notify("Link target not found: " .. href, vim.log.levels.WARN)
end

-- Expose jump_to_link for keymap
M.jump_to_link = jump_to_link

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
  local justify_text = M.config.justify_text or false
  local parsed = html.parse(content, max_width, class_styles, justify_text)

  -- Calculate padding for centering
  local win_width = vim.api.nvim_win_get_width(ctx.content_win)
  local padding = 0
  if win_width > max_width then
    padding = math.floor((win_width - max_width) / 2)
  end

  -- Set text (no physical padding)
  vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.content_buf })
  vim.api.nvim_buf_set_lines(ctx.content_buf, 0, -1, false, parsed.lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.content_buf })

  -- Clear existing extmarks (highlights and virtual text)
  vim.api.nvim_buf_clear_namespace(ctx.content_buf, ctx.ns_id, 0, -1)

  -- Apply virtual text padding for centering
  if padding > 0 then
    local pad_str = string.rep(" ", padding)
    for i = 1, #parsed.lines do
      local line_idx = i - 1  -- Convert to 0-based
      vim.api.nvim_buf_set_extmark(ctx.content_buf, ctx.ns_id, line_idx, 0, {
        virt_text = {{pad_str, "Normal"}},
        virt_text_pos = "inline",
        priority = 100
      })
    end
  end

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
  ctx.justify_map = parsed.justify_map or {}

  -- Apply user highlights (forward-map positions if justify is enabled)
  local chapter_highlights = user_highlights.get_chapter_highlights(ctx.data.slug, idx)
  for _, hl in ipairs(chapter_highlights) do
    local start_line = hl.start_line - 1  -- Convert to 0-based
    local end_line = hl.end_line - 1
    local start_col = hl.start_col
    local end_col = hl.end_col

    -- Forward-map columns if justify is enabled (stored positions are canonical/non-justified)
    if justify_text then
      local start_word_info = ctx.justify_map[hl.start_line]
      local end_word_info = ctx.justify_map[hl.end_line]
      start_col = html.forward_map_column(start_word_info, start_col)
      end_col = html.forward_map_column(end_word_info, end_col)
    end

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

  -- Update library progress
  library.update_progress(ctx.data.slug, idx, #ctx.data.spine)
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

-- Search TOC/Chapters (shows all chapters with preview)
function M.search_toc(initial_text)
  -- Check if telescope is installed
  local ok_pickers, pickers = pcall(require, 'telescope.pickers')
  local ok_finders, finders = pcall(require, 'telescope.finders')
  local ok_conf, conf = pcall(require, 'telescope.config')
  local ok_previewers, previewers = pcall(require, 'telescope.previewers')
  local ok_actions, actions = pcall(require, 'telescope.actions')
  local ok_action_state, action_state = pcall(require, 'telescope.actions.state')

  if not (ok_pickers and ok_finders and ok_conf and ok_previewers and ok_actions and ok_action_state) then
    vim.notify("Telescope not found. Install telescope.nvim to use search.", vim.log.levels.ERROR)
    return
  end

  -- Check if a book is currently open
  if not ctx.data then
    vim.notify("No book currently open", vim.log.levels.WARN)
    return
  end

  -- Build list of searchable entries (all chapters)
  local entries = {}
  for idx, chapter in ipairs(ctx.data.spine) do
    local chapter_path = ctx.data.base_dir .. "/" .. chapter.href

    -- Try to get chapter name from TOC
    local chapter_name = nil
    local chapter_href = chapter.href
    for _, toc_item in ipairs(ctx.data.toc) do
      local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
      if toc_href == chapter_href then
        chapter_name = toc_item.label
        break
      end
    end

    -- Fallback to chapter number
    if not chapter_name then
      chapter_name = "Chapter " .. idx
    end

    table.insert(entries, {
      display = string.format("[%d/%d] %s", idx, #ctx.data.spine, chapter_name),
      ordinal = chapter_name, -- What to search against
      chapter_idx = idx,
      chapter_path = chapter_path,
      chapter_name = chapter_name
    })
  end

  -- Get toggle key from config
  local toggle_key = M.config.keymaps.search_mode_toggle or "<C-f>"
  local toggle_key_display = toggle_key:gsub("<", ""):gsub(">", "")

  -- Create custom picker
  pickers.new({}, {
    prompt_title = string.format("Search Book Chapters (%s for content search)", toggle_key_display),
    default_text = initial_text or "",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
          path = entry.chapter_path,
          chapter_idx = entry.chapter_idx
        }
      end
    }),
    previewer = previewers.new_buffer_previewer({
      title = "Chapter Preview",
      define_preview = function(self, entry)
        -- Read and parse the chapter HTML
        local content = fs.read_file(entry.path)
        if not content then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"Error reading chapter"})
          return
        end

        -- Parse HTML to plain text
        local max_width = M.config.max_width or 120
        local class_styles = ctx.data.class_styles or {}
        local justify_text = M.config.justify_text or false
        local parsed = html.parse(content, max_width, class_styles, justify_text)

        -- Show parsed lines in preview
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, parsed.lines)

        -- Apply basic syntax highlighting to preview
        vim.api.nvim_set_option_value("filetype", "ink_content", { buf = self.state.bufnr })
      end
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        -- Navigate to the selected chapter
        M.render_chapter(selection.chapter_idx)

        -- Focus on content window
        if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
          vim.api.nvim_set_current_win(ctx.content_win)
        end
      end)

      -- Add configurable key to switch to content search mode
      if toggle_key then
        map('i', toggle_key, function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local current_prompt = current_picker:_get_prompt()
          actions.close(prompt_bufnr)

          -- Switch to content search
          M.search_content(current_prompt)
        end)
      end

      return true
    end
  }):find()
end

-- Search content (live_grep directly)
function M.search_content(initial_text)
  -- Check if telescope is installed
  local ok, builtin = pcall(require, 'telescope.builtin')
  if not ok then
    vim.notify("Telescope not found. Install telescope.nvim to use search.", vim.log.levels.ERROR)
    return
  end

  -- Check if a book is currently open
  if not ctx.data then
    vim.notify("No book currently open", vim.log.levels.WARN)
    return
  end

  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  -- Get toggle key from config
  local toggle_key = M.config.keymaps.search_mode_toggle or "<C-f>"
  local toggle_key_display = toggle_key:gsub("<", ""):gsub(">", "")

  builtin.live_grep({
    prompt_title = string.format("Search in Book Content (%s for TOC search)", toggle_key_display),
    search_dirs = {ctx.data.cache_dir},
    glob_pattern = "*.{xhtml,html}",
    default_text = initial_text or "",
    attach_mappings = function(prompt_bufnr, map)
      map('i', '<CR>', function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        -- Parse filename and find chapter
        local filename = vim.fn.fnamemodify(selection.filename, ":t")
        local line_num = selection.lnum

        -- Find chapter index that matches this file
        for idx, chapter in ipairs(ctx.data.spine) do
          if chapter.href:match(filename) then
            M.render_chapter(idx, line_num)
            -- Focus on content window
            if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
              vim.api.nvim_set_current_win(ctx.content_win)
            end
            return
          end
        end

        vim.notify("Could not find chapter for: " .. filename, vim.log.levels.WARN)
      end)

      -- Add configurable key to switch back to TOC search mode
      if toggle_key then
        map('i', toggle_key, function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local current_prompt = current_picker:_get_prompt()
          actions.close(prompt_bufnr)

          -- Switch to TOC search (with current prompt text preserved)
          M.search_toc(current_prompt)
        end)
      end

      return true
    end
  })
end

function M.next_chapter()
  M.render_chapter(ctx.current_chapter_idx + 1)
end

function M.prev_chapter()
  M.render_chapter(ctx.current_chapter_idx - 1)
end

function M.increase_width()
  local step = M.config.width_step or 10
  local current = M.config.max_width or 120
  M.config.max_width = current + step
  -- Get current line to restore position
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  M.render_chapter(ctx.current_chapter_idx, cursor[1])
  vim.notify("Width: " .. M.config.max_width, vim.log.levels.INFO)
end

function M.decrease_width()
  local step = M.config.width_step or 10
  local current = M.config.max_width or 120
  local new_width = math.max(40, current - step)  -- Minimum width of 40
  M.config.max_width = new_width
  -- Get current line to restore position
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  M.render_chapter(ctx.current_chapter_idx, cursor[1])
  vim.notify("Width: " .. M.config.max_width, vim.log.levels.INFO)
end

function M.reset_width()
  if ctx.default_max_width then
    M.config.max_width = ctx.default_max_width
    -- Get current line to restore position
    local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
    M.render_chapter(ctx.current_chapter_idx, cursor[1])
    vim.notify("Width reset: " .. M.config.max_width, vim.log.levels.INFO)
  end
end

function M.handle_enter()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]
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
    -- Check for image first
    for _, img in ipairs(ctx.images) do
      if img[1] == line then
        open_image(img[4])
        return
      end
    end

    -- Check for link at cursor
    local href = get_link_at_cursor(line, col)
    if href then
      -- Check if it's an internal anchor (footnote)
      local anchor = href:match("^#(.+)$")
      if anchor then
        -- Internal link - show footnote preview
        show_footnote_preview(anchor)
        return
      end

      -- External or cross-chapter link - could handle differently
      -- For now, try to navigate if it's to another chapter
      local target_href = href:match("^([^#]+)") or href
      local target_anchor = href:match("#(.+)$")

      -- Check if it's a link to another chapter in spine
      for i, spine_item in ipairs(ctx.data.spine) do
        -- Match by filename (hrefs might be relative)
        local spine_filename = spine_item.href:match("([^/]+)$")
        local target_filename = target_href:match("([^/]+)$")
        if spine_filename == target_filename then
          M.render_chapter(i)
          if target_anchor and ctx.anchors[target_anchor] then
            vim.api.nvim_win_set_cursor(ctx.content_win, {ctx.anchors[target_anchor], 0})
          end
          return
        end
      end

      -- Unknown link type
      vim.notify("Link: " .. href, vim.log.levels.INFO)
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

  -- Reverse-map columns if justify is enabled (store canonical/non-justified positions)
  local justify_text = M.config.justify_text or false
  local stored_start_col = start_col
  local stored_end_col = end_col

  if justify_text then
    local start_word_info = ctx.justify_map[start_line]
    local end_word_info = ctx.justify_map[end_line]
    stored_start_col = html.reverse_map_column(start_word_info, start_col)
    stored_end_col = html.reverse_map_column(end_word_info, end_col)
  end

  -- Store highlight (positions stored in canonical/non-justified form)
  local highlight = {
    chapter = ctx.current_chapter_idx,
    start_line = start_line,
    start_col = stored_start_col,
    end_line = end_line,
    end_col = stored_end_col,
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

  -- Reverse-map column if justify is enabled (stored positions are canonical/non-justified)
  local lookup_col = col
  local justify_text = M.config.justify_text or false
  if justify_text then
    local word_info = ctx.justify_map[line]
    lookup_col = html.reverse_map_column(word_info, col)
  end

  -- Remove highlight using canonical position
  user_highlights.remove_highlight(ctx.data.slug, ctx.current_chapter_idx, line, lookup_col)

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

  -- Jump to link target (g + Enter by default)
  local jump_key = keymaps.jump_to_link or "g<CR>"
  vim.api.nvim_buf_set_keymap(buf, "n", jump_key, ":lua require('ink.ui').jump_to_link()<CR>", opts)

  if keymaps.search_toc then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.search_toc, ":lua require('ink.ui').search_toc()<CR>", opts)
  end

  if keymaps.search_content then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.search_content, ":lua require('ink.ui').search_content()<CR>", opts)
  end

  if keymaps.width_increase then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.width_increase, ":lua require('ink.ui').increase_width()<CR>", opts)
  end

  if keymaps.width_decrease then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.width_decrease, ":lua require('ink.ui').decrease_width()<CR>", opts)
  end

  if keymaps.width_reset then
    vim.api.nvim_buf_set_keymap(buf, "n", keymaps.width_reset, ":lua require('ink.ui').reset_width()<CR>", opts)
  end
end

function M.open_book(epub_data)
  ctx.data = epub_data

  -- Register book in library
  library.add_book({
    slug = epub_data.slug,
    title = epub_data.title,
    author = epub_data.author,
    language = epub_data.language,
    date = epub_data.date,
    description = epub_data.description,
    path = epub_data.path,
    chapter = 1,
    total_chapters = #epub_data.spine
  })

  -- Store default width to restore on close
  ctx.default_max_width = M.config.max_width

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
    -- If we have saved state, user is returning - focus on content to continue reading
    if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
      vim.api.nvim_set_current_win(ctx.content_win)
    end
  else
    M.render_chapter(1)
    -- First time opening - leave cursor in TOC to browse chapters
  end

  -- Keymaps
  M.setup_keymaps(ctx.content_buf)
  M.setup_keymaps(ctx.toc_buf)

  -- Add toggle TOC keymap to both buffers
  local keymaps = M.config.keymaps or {}
  local keymap_opts = { noremap = true, silent = true }
  if keymaps.toggle_toc then
    vim.api.nvim_buf_set_keymap(ctx.content_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", keymap_opts)
    vim.api.nvim_buf_set_keymap(ctx.toc_buf, "n", keymaps.toggle_toc, ":lua require('ink.ui').toggle_toc()<CR>", keymap_opts)
  end

  -- Setup user highlight keymaps (visual mode only, content buffer only)
  local highlight_keymaps = M.config.highlight_keymaps or {}

  for color_name, keymap in pairs(highlight_keymaps) do
    if color_name == "remove" then
      -- Remove highlight (normal mode)
      vim.api.nvim_buf_set_keymap(ctx.content_buf, "n", keymap,
        ":lua require('ink.ui').remove_highlight()<CR>", keymap_opts)
    else
      -- Add highlight (visual mode)
      vim.api.nvim_buf_set_keymap(ctx.content_buf, "v", keymap,
        string.format(":lua require('ink.ui').add_highlight('%s')<CR>", color_name), keymap_opts)
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

  -- Reset width to default when buffer is closed
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup,
    buffer = ctx.content_buf,
    callback = function()
      if ctx.default_max_width then
        M.config.max_width = ctx.default_max_width
      end
    end,
  })
end

-- Open last book from library
function M.open_last_book()
  local last_path = library.get_last_book_path()
  if not last_path then
    vim.notify("No books in library yet", vim.log.levels.INFO)
    return
  end

  if not fs.exists(last_path) then
    vim.notify("Last book not found: " .. last_path, vim.log.levels.ERROR)
    return
  end

  -- Open the book using the main epub module
  local epub = require("ink.epub")
  local ok, epub_data = pcall(epub.open, last_path)
  if not ok then
    vim.notify("Failed to open book: " .. tostring(epub_data), vim.log.levels.ERROR)
    return
  end

  M.open_book(epub_data)
end

-- Show library with Telescope or fallback
function M.show_library()
  local books = library.get_books()

  if #books == 0 then
    vim.notify("Library is empty. Open a book with :InkOpen first.", vim.log.levels.INFO)
    return
  end

  -- Try to use Telescope
  local ok_telescope, _ = pcall(require, 'telescope')
  if ok_telescope then
    M.show_library_telescope(books)
  else
    M.show_library_floating(books)
  end
end

-- Telescope-based library picker
function M.show_library_telescope(books)
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')

  local entries = {}
  for _, book in ipairs(books) do
    local progress = math.floor((book.chapter / book.total_chapters) * 100)
    local last_opened = library.format_last_opened(book.last_opened)
    local author = book.author or "Unknown"

    table.insert(entries, {
      display = string.format("%-30s │ %-20s │ %3d%% │ %s", book.title:sub(1, 30), author:sub(1, 20), progress, last_opened),
      ordinal = book.title .. " " .. author,  -- Search by title AND author
      book = book,
      progress = progress,
      last_opened = last_opened,
      author = author
    })
  end

  pickers.new({}, {
    prompt_title = "Library (C-d: delete, C-e: edit file)",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.ordinal,
          book = entry.book
        }
      end
    }),
    previewer = previewers.new_buffer_previewer({
      title = "Book Info",
      define_preview = function(self, entry)
        local book = entry.book
        local lines = {
          "Title: " .. book.title,
          "Author: " .. (book.author or "Unknown"),
        }

        -- Add optional metadata
        if book.language then
          table.insert(lines, "Language: " .. book.language)
        end
        if book.date then
          table.insert(lines, "Date: " .. book.date)
        end

        table.insert(lines, "")
        table.insert(lines, "Progress: " .. entry.value.progress .. "% (Chapter " .. book.chapter .. "/" .. book.total_chapters .. ")")
        table.insert(lines, "Last opened: " .. entry.value.last_opened)

        -- Add description if available
        if book.description and book.description ~= "" then
          table.insert(lines, "")
          table.insert(lines, "Description:")
          -- Word wrap description at ~60 chars
          local desc = book.description
          local wrap_width = 60
          while #desc > 0 do
            if #desc <= wrap_width then
              table.insert(lines, "  " .. desc)
              break
            else
              local break_pos = desc:sub(1, wrap_width):match(".*()%s") or wrap_width
              table.insert(lines, "  " .. desc:sub(1, break_pos))
              desc = desc:sub(break_pos + 1):match("^%s*(.*)$") or ""
            end
          end
        end

        table.insert(lines, "")
        table.insert(lines, "Path: " .. book.path)

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        local book = selection.book
        if not fs.exists(book.path) then
          vim.notify("Book not found: " .. book.path, vim.log.levels.ERROR)
          return
        end

        local epub = require("ink.epub")
        local ok, epub_data = pcall(epub.open, book.path)
        if ok then
          M.open_book(epub_data)
        else
          vim.notify("Failed to open: " .. tostring(epub_data), vim.log.levels.ERROR)
        end
      end)

      -- Delete book from library with <C-d>
      map('i', '<C-d>', function()
        local selection = action_state.get_selected_entry()
        if selection then
          library.remove_book(selection.book.slug)
          vim.notify("Removed: " .. selection.book.title, vim.log.levels.INFO)
          -- Refresh picker
          actions.close(prompt_bufnr)
          vim.schedule(function()
            M.show_library()
          end)
        end
      end)

      -- Edit library.json with <C-e>
      map('i', '<C-e>', function()
        actions.close(prompt_bufnr)
        vim.cmd("InkEditLibrary")
      end)

      return true
    end
  }):find()
end

-- Floating window fallback for library
function M.show_library_floating(books)
  local lines = {}
  local book_map = {}  -- line number -> book

  table.insert(lines, "Library (press Enter to open, q to close)")
  table.insert(lines, string.rep("─", 75))

  for i, book in ipairs(books) do
    local progress = math.floor((book.chapter / book.total_chapters) * 100)
    local last_opened = library.format_last_opened(book.last_opened)
    local author = book.author or "Unknown"
    local line = string.format(" %d. %-25s │ %-15s │ %3d%% │ %s", i, book.title:sub(1, 25), author:sub(1, 15), progress, last_opened)
    table.insert(lines, line)
    book_map[#lines] = book
  end

  table.insert(lines, "")
  table.insert(lines, " Press Enter to open, d to delete, q to close")

  -- Calculate dimensions
  local width = 80
  local height = math.min(#lines, 20)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Create floating window centered
  local win_width = vim.o.columns
  local win_height = vim.o.lines
  local row = math.floor((win_height - height) / 2)
  local col = math.floor((win_width - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Library ",
    title_pos = "center",
  })

  -- Keymaps for the floating window
  local function close_window()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close_window, { buffer = buf })
  vim.keymap.set("n", "<Esc>", close_window, { buffer = buf })

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_num = cursor[1]
    local book = book_map[line_num]

    if book then
      close_window()
      if not fs.exists(book.path) then
        vim.notify("Book not found: " .. book.path, vim.log.levels.ERROR)
        return
      end

      local epub = require("ink.epub")
      local ok, epub_data = pcall(epub.open, book.path)
      if ok then
        M.open_book(epub_data)
      else
        vim.notify("Failed to open: " .. tostring(epub_data), vim.log.levels.ERROR)
      end
    end
  end, { buffer = buf })

  vim.keymap.set("n", "d", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_num = cursor[1]
    local book = book_map[line_num]

    if book then
      library.remove_book(book.slug)
      vim.notify("Removed: " .. book.title, vim.log.levels.INFO)
      close_window()
      -- Reopen to refresh
      vim.schedule(function()
        M.show_library()
      end)
    end
  end, { buffer = buf })

  -- Position cursor on first book
  vim.api.nvim_win_set_cursor(win, {3, 0})
end

return M
