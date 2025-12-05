local html = require("ink.html")
local fs = require("ink.fs")
local state = require("ink.state")
local user_highlights = require("ink.user_highlights")
local bookmarks_data = require("ink.bookmarks")
local library = require("ink.library")
local context = require("ink.ui.context")
local util = require("ink.ui.util")
local parse = require("ink.html.parser")

local M = {}

function M.update_statusline(ctx)
  ctx = ctx or context.current()
  if not ctx or not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then return end

  local total = #ctx.data.spine
  local current = ctx.current_chapter_idx
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  local current_line = cursor[1]
  local total_lines = vim.api.nvim_buf_line_count(ctx.content_buf)
  local percent = math.floor((current_line / total_lines) * 100)

  local bar_len = 10
  local filled = math.floor((percent / 100) * bar_len)
  local bar = string.rep("█", filled) .. string.rep("▒", bar_len - filled)

  local chapter_name = nil
  local current_href = ctx.data.spine[current].href
  for _, toc_item in ipairs(ctx.data.toc) do
    local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
    if toc_href == current_href then
      chapter_name = toc_item.label
      break
    end
  end
  if not chapter_name then chapter_name = "Chapter " .. current end

  local status = string.format(" %s %d%%%% | %s | %d/%d ", bar, percent, chapter_name, current, total)
  vim.api.nvim_set_option_value("statusline", status, { win = ctx.content_win })
end

function M.render_chapter(idx, restore_line, ctx)
  ctx = ctx or context.current()
  if not ctx or idx < 1 or idx > #ctx.data.spine then return end
  ctx.current_chapter_idx = idx
  ctx.last_statusline_percent = 0

  if not ctx.content_win or not vim.api.nvim_win_is_valid(ctx.content_win) then
    local found_win = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if buf == ctx.content_buf then found_win = win; break end
      end
    end
    if found_win then
      ctx.content_win = found_win
    else
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

  local max_width = context.config.max_width or 120
  local class_styles = ctx.data.class_styles or {}
  local justify_text = context.config.justify_text or false
  local parsed = html.parse(content, max_width, class_styles, justify_text)

  local win_width = vim.api.nvim_win_get_width(ctx.content_win)
  local padding = 0
  if win_width > max_width then
    padding = math.floor((win_width - max_width) / 2)
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.content_buf })
  vim.api.nvim_buf_set_lines(ctx.content_buf, 0, -1, false, parsed.lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = ctx.content_buf })

  vim.api.nvim_buf_clear_namespace(ctx.content_buf, context.ns_id, 0, -1)

  for i = 1, #parsed.lines do
    local line_idx = i - 1
    local line_padding = padding

    -- Add extra padding to center title lines within max_width
    if parsed.centered_lines and parsed.centered_lines[i] then
      local line_width = vim.fn.strdisplaywidth(parsed.lines[i])
      if line_width < max_width then
        line_padding = line_padding + math.floor((max_width - line_width) / 2)
      end
    end

    if line_padding > 0 then
      local pad_str = string.rep(" ", line_padding)
      vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, line_idx, 0, {
        virt_text = {{pad_str, "Normal"}}, virt_text_pos = "inline", priority = 100
      })
    end
  end

  for _, hl in ipairs(parsed.highlights) do
    local line_idx = hl[1] - 1
    local start_col = hl[2]
    local end_col = hl[3]
    if line_idx >= 0 and line_idx < #parsed.lines then
      local line_length = #parsed.lines[line_idx + 1]
      start_col = math.min(start_col, line_length)
      end_col = math.min(end_col, line_length)
      if start_col < end_col then
        vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, line_idx, start_col, {
          end_col = end_col, hl_group = hl[4], priority = 1000, hl_mode = "combine"
        })
      end
    end
  end

  ctx.images = parsed.images
  ctx.links = parsed.links
  ctx.anchors = parsed.anchors
  ctx.justify_map = parsed.justify_map or {}
  ctx.rendered_lines = parsed.lines

  local chapter_highlights = user_highlights.get_chapter_highlights(ctx.data.slug, idx)
  for _, hl in ipairs(chapter_highlights) do
    local start_line, start_col, end_line, end_col = util.find_text_position(
      parsed.lines, hl.text, hl.context_before, hl.context_after
    )
    if start_line then
      hl._start_line = start_line
      hl._start_col = start_col
      hl._end_line = end_line
      hl._end_col = end_col
      local hl_group = "InkUserHighlight_" .. hl.color
      vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, start_line - 1, start_col, {
        end_line = end_line - 1, end_col = end_col, hl_group = hl_group, priority = 2000
      })
    end
  end

  if ctx.note_display_mode ~= "off" then
    local notes_by_line = {}
    for _, hl in ipairs(chapter_highlights) do
      if hl.note and hl.note ~= "" and hl._end_line then
        local end_line = hl._end_line
        if not notes_by_line[end_line] then notes_by_line[end_line] = {} end
        table.insert(notes_by_line[end_line], { hl = hl, end_col = hl._end_col })
      end
    end
    for line, notes in pairs(notes_by_line) do
      table.sort(notes, function(a, b) return a.end_col < b.end_col end)
    end
    for line, notes in pairs(notes_by_line) do
      local line_idx = line - 1
      if line_idx >= 0 and line_idx < #parsed.lines then
        if ctx.note_display_mode == "indicator" then
          for _, note_info in ipairs(notes) do
            vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, line_idx, note_info.end_col, {
              virt_text = {{"●", "InkNoteIndicator"}}, virt_text_pos = "inline", priority = 3000
            })
          end
        elseif ctx.note_display_mode == "expanded" then
          for _, note_info in ipairs(notes) do
            vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, line_idx, note_info.end_col, {
              virt_text = {{"●", "InkNoteIndicator"}}, virt_text_pos = "inline", priority = 3000
            })
          end
          local virt_lines = {}
          for i, note_info in ipairs(notes) do
            local bars = string.rep("│", i)
            local note_text = note_info.hl.note:gsub("\n", " ")
            local max_note_len = max_width - #bars - 2
            if #note_text > max_note_len then note_text = note_text:sub(1, max_note_len - 3) .. "..." end
            local pad = string.rep(" ", padding)
            table.insert(virt_lines, {{pad .. bars .. " " .. note_text, "InkNoteText"}})
          end
          if #virt_lines > 0 then
            vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, line_idx, 0, {
              virt_lines = virt_lines, virt_lines_above = false, priority = 3000
            })
          end
        end
      end
    end
  end

  -- Render bookmarks
  local chapter_bookmarks = bookmarks_data.get_chapter_bookmarks(ctx.data.slug, idx)
  local bookmark_icon = context.config.bookmark_icon or "󰃀"
  for _, bm in ipairs(chapter_bookmarks) do
    local line_idx = bm.paragraph_line - 1
    if line_idx >= 0 and line_idx < #parsed.lines then
      local pad = string.rep(" ", padding)
      vim.api.nvim_buf_set_extmark(ctx.content_buf, context.ns_id, line_idx, 0, {
        virt_lines = {{{pad .. bookmark_icon .. " " .. bm.name, "InkBookmark"}}},
        virt_lines_above = true,
        priority = 4000,
      })
    end
  end

  if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
    if restore_line then
      vim.api.nvim_win_set_cursor(ctx.content_win, {restore_line, 0})
    else
      vim.api.nvim_win_set_cursor(ctx.content_win, {1, 0})
    end
  end

  M.update_statusline(ctx)
  state.save(ctx.data.slug, { chapter = idx, line = restore_line or 1 })
  library.update_progress(ctx.data.slug, idx, #ctx.data.spine)
end

function M.render_toc(ctx)
  ctx = ctx or context.current()
  if not ctx then return end
  vim.api.nvim_set_option_value("modifiable", true, { buf = ctx.toc_buf })
  local lines = {}
  for _, item in ipairs(ctx.data.toc) do
    local indent = string.rep("  ", (item.level or 1) - 1)
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

function M.toggle_note_display(ctx)
  ctx = ctx or context.current()
  if not ctx then return end
  if ctx.note_display_mode == "off" then
    ctx.note_display_mode = "indicator"
  elseif ctx.note_display_mode == "indicator" then
    ctx.note_display_mode = "expanded"
  else
    ctx.note_display_mode = "off"
  end
  local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
  M.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
  vim.notify("Note display: " .. ctx.note_display_mode, vim.log.levels.INFO)
end

function M.show_footnote_preview(anchor_id, ctx)
  ctx = ctx or context.current()
  if not ctx then return false end
  local anchor_line = ctx.anchors[anchor_id]
  if not anchor_line then
    vim.notify("Footnote not found: " .. anchor_id, vim.log.levels.WARN)
    return false
  end

  local total_lines = vim.api.nvim_buf_line_count(ctx.content_buf)
  local max_preview_lines = 15
  local end_line = math.min(anchor_line + max_preview_lines - 1, total_lines)
  local lines = vim.api.nvim_buf_get_lines(ctx.content_buf, anchor_line - 1, end_line, false)

  while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
  while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end

  local footnote_lines = {}
  local found_content = false
  for _, line in ipairs(lines) do
    if not found_content and line:match("^%s*$") then goto continue end
    found_content = true
    if found_content and line:match("^%s*$") then break end
    table.insert(footnote_lines, line:match("^%s*(.-)%s*$"))
    ::continue::
  end

  if #footnote_lines == 0 then
    vim.notify("Empty footnote", vim.log.levels.WARN)
    return false
  end

  local max_width = 60
  local width = 0
  for _, line in ipairs(footnote_lines) do width = math.max(width, #line) end
  width = math.min(width + 2, max_width)

  local wrapped_lines = {}
  for _, line in ipairs(footnote_lines) do
    if #line > width - 2 then
      local current = ""
      for word in line:gmatch("%S+") do
        if #current + #word + 1 > width - 2 then
          if #current > 0 then table.insert(wrapped_lines, current) end
          current = word
        else
          if current == "" then current = word else current = current .. " " .. word end
        end
      end
      if #current > 0 then table.insert(wrapped_lines, current) end
    else
      table.insert(wrapped_lines, line)
    end
  end

  local height = math.min(#wrapped_lines, 10)
  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, wrapped_lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })

  local float_win = vim.api.nvim_open_win(float_buf, false, {
    relative = "cursor", row = 1, col = 0, width = width, height = height,
    style = "minimal", border = "rounded", title = " Footnote ", title_pos = "center",
  })
  vim.api.nvim_set_option_value("winblend", 0, { win = float_win })
  vim.api.nvim_set_option_value("winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = float_win })

  local function close_float()
    if vim.api.nvim_win_is_valid(float_win) then vim.api.nvim_win_close(float_win, true) end
    pcall(vim.keymap.del, "n", "q", { buffer = ctx.content_buf })
    pcall(vim.keymap.del, "n", "<Esc>", { buffer = ctx.content_buf })
  end

  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" }, {
    callback = function() close_float(); return true end, buffer = ctx.content_buf,
  })
  vim.keymap.set("n", "q", close_float, { buffer = ctx.content_buf })
  vim.keymap.set("n", "<Esc>", close_float, { buffer = ctx.content_buf })
  return true
end

return M
