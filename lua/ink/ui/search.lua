local fs = require("ink.fs")
local html = require("ink.html")
local context = require("ink.ui.context")
local render = require("ink.ui.render")

local M = {}

-- Helper to get chapter name from TOC
function M.get_chapter_name(chapter_idx, ctx)
  local chapter = ctx.data.spine[chapter_idx]
  if not chapter then return "Chapter " .. chapter_idx end

  local chapter_href = chapter.href
  for _, toc_item in ipairs(ctx.data.toc) do
    local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
    if toc_href == chapter_href then
      -- Truncate name if too long
      local name = toc_item.label
      if #name > 20 then
        name = name:sub(1, 17) .. "..."
      end
      return name
    end
  end

  return "Ch. " .. chapter_idx
end

-- Build search index asynchronously for large books
function M.build_search_index_async(ctx, callback)
  local entries = {}
  local chapter_idx = 1
  local total = #ctx.data.spine

  vim.notify("Indexing book asynchronously...", vim.log.levels.INFO)

  local function process_next()
    if chapter_idx > total then
      vim.notify(string.format("Indexed %d lines from %d chapters", #entries, total), vim.log.levels.INFO)
      callback(entries)
      return
    end

    local parsed = render.get_parsed_chapter(chapter_idx, ctx)
    if parsed and parsed.lines then
      local chapter_name = M.get_chapter_name(chapter_idx, ctx)

      for line_num, line_text in ipairs(parsed.lines) do
        local trimmed = line_text:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
          local display_text = trimmed
          if #display_text > 60 then
            display_text = display_text:sub(1, 57) .. "..."
          end

          table.insert(entries, {
            display = string.format("[%d] %s: %s", chapter_idx, chapter_name, display_text),
            text = trimmed,
            chapter_idx = chapter_idx,
            chapter_name = chapter_name,
            line_num = line_num,
          })
        end
      end
    end

    chapter_idx = chapter_idx + 1
    vim.schedule(process_next)  -- Yield to not block UI
  end

  process_next()
end

-- Get or build search index with caching
function M.get_or_build_index(ctx, callback)
  -- Return cached index if exists
  if ctx.search_index then
    if callback then
      callback(ctx.search_index)
    else
      return ctx.search_index
    end
    return
  end

  local total_chapters = #ctx.data.spine
  local use_async = total_chapters > 50  -- Use async for books with more than 50 chapters

  if use_async and callback then
    -- Build asynchronously
    M.build_search_index_async(ctx, function(entries)
      ctx.search_index = entries
      callback(entries)
    end)
  else
    -- Build synchronously
    ctx.search_index = M.build_search_index(ctx)
    if callback then
      callback(ctx.search_index)
    else
      return ctx.search_index
    end
  end
end

-- Build search index from all chapters
function M.build_search_index(ctx)
  local entries = {}
  local total_chapters = #ctx.data.spine

  -- Show progress for large books
  local large_book = total_chapters > 20
  if large_book then
    vim.notify("Indexing book for search...", vim.log.levels.INFO)
  end

  for chapter_idx = 1, total_chapters do
    local parsed = render.get_parsed_chapter(chapter_idx, ctx)
    if parsed and parsed.lines then

      -- Get chapter name from TOC
      local chapter_name = M.get_chapter_name(chapter_idx, ctx)

      for line_num, line_text in ipairs(parsed.lines) do
        -- Ignore empty lines or only spaces
        local trimmed = line_text:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
          -- Create context for display (truncate if too long)
          local display_text = trimmed
          if #display_text > 60 then
            display_text = display_text:sub(1, 57) .. "..."
          end

          table.insert(entries, {
            display = string.format("[%d] %s: %s", chapter_idx, chapter_name, display_text),
            text = trimmed,  -- Full text for search
            chapter_idx = chapter_idx,
            chapter_name = chapter_name,
            line_num = line_num,
          })
        end
      end
    end
  end

  if large_book then
    vim.notify(string.format("Indexed %d lines from %d chapters", #entries, total_chapters), vim.log.levels.INFO)
  end

  return entries
end

function M.search_toc(initial_text)
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

  local ctx = context.current()
  if not ctx or not ctx.data then vim.notify("No book currently open", vim.log.levels.WARN); return end

  local entries = {}
  for idx, chapter in ipairs(ctx.data.spine) do
    local chapter_path = ctx.data.base_dir .. "/" .. chapter.href
    local chapter_name = nil
    local chapter_href = chapter.href
    for _, toc_item in ipairs(ctx.data.toc) do
      local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
      if toc_href == chapter_href then chapter_name = toc_item.label; break end
    end
    if not chapter_name then chapter_name = "Chapter " .. idx end
    table.insert(entries, {
      display = string.format("[%d/%d] %s", idx, #ctx.data.spine, chapter_name),
      ordinal = chapter_name,
      chapter_idx = idx,
      chapter_path = chapter_path,
      chapter_name = chapter_name
    })
  end

  local toggle_key = context.config.keymaps.search_mode_toggle or "<C-f>"
  local toggle_key_display = toggle_key:gsub("<", ""):gsub(">", "")

  pickers.new({}, {
    prompt_title = string.format("Search Book Chapters (%s for content search)", toggle_key_display),
    default_text = initial_text or "",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return { value = entry, display = entry.display, ordinal = entry.ordinal, path = entry.chapter_path, chapter_idx = entry.chapter_idx }
      end
    }),
    previewer = previewers.new_buffer_previewer({
      title = "Chapter Preview",
      define_preview = function(self, entry)
        local content = fs.read_file(entry.path)
        if not content then vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"Error reading chapter"}); return end
        local max_width = context.config.max_width or 120
        local class_styles = ctx.data.class_styles or {}
        local justify_text = context.config.justify_text or false
        local parsed = html.parse(content, max_width, class_styles, justify_text)
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, parsed.lines)
        vim.api.nvim_set_option_value("filetype", "ink_content", { buf = self.state.bufnr })
      end
    }),
    sorter = conf.values.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        render.render_chapter(selection.chapter_idx, nil, ctx)
        if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then vim.api.nvim_set_current_win(ctx.content_win) end
      end)
      if toggle_key then
        map('i', toggle_key, function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local current_prompt = current_picker:_get_prompt()
          actions.close(prompt_bufnr)
          M.search_content(current_prompt)
        end)
      end
      return true
    end
  }):find()
end

-- Search in index with fuzzy matching
local function search_in_index(search_entries, prompt)
  if #prompt < 2 then
    return search_entries  -- Return all if prompt too short
  end

  local results = {}
  local pattern = prompt:lower()

  for _, entry in ipairs(search_entries) do
    local text_lower = entry.text:lower()
    if text_lower:find(pattern, 1, true) then
      table.insert(results, entry)
    end
  end

  return results
end

-- Helper function to open telescope picker with search entries
local function open_search_picker(search_entries, initial_text, ctx, use_live_search)
  local ok_pickers, pickers = pcall(require, 'telescope.pickers')
  local ok_finders, finders = pcall(require, 'telescope.finders')
  local ok_conf, conf = pcall(require, 'telescope.config')
  local ok_previewers, previewers = pcall(require, 'telescope.previewers')
  local ok_actions, actions = pcall(require, 'telescope.actions')
  local ok_action_state, action_state = pcall(require, 'telescope.actions.state')
  local ok_sorters, sorters = pcall(require, 'telescope.sorters')

  if not (ok_pickers and ok_finders and ok_conf and ok_previewers and ok_actions and ok_action_state and ok_sorters) then
    vim.notify("Telescope not found. Install telescope.nvim to use search.", vim.log.levels.ERROR)
    return
  end

  local toggle_key = context.config.keymaps.search_mode_toggle or "<C-f>"
  local toggle_key_display = toggle_key:gsub("<", ""):gsub(">", "")

  local finder
  if use_live_search then
    -- Use dynamic finder for incremental search
    finder = finders.new_dynamic({
      fn = function(prompt)
        return search_in_index(search_entries, prompt)
      end,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.text,
          chapter_idx = entry.chapter_idx,
          line_num = entry.line_num,
        }
      end
    })
  else
    -- Use static finder
    finder = finders.new_table({
      results = search_entries,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.text,  -- Search in clean text
          chapter_idx = entry.chapter_idx,
          line_num = entry.line_num,
        }
      end
    })
  end

  pickers.new({}, {
    prompt_title = string.format("Search in Book (%s for TOC)", toggle_key_display),
    default_text = initial_text or "",
    finder = finder,
    sorter = sorters.get_fzy_sorter(),  -- Fuzzy matching
    previewer = previewers.new_buffer_previewer({
      title = "Chapter Preview",
      define_preview = function(self, entry)
        local parsed = render.get_parsed_chapter(entry.chapter_idx, ctx)
        if not parsed then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"Error loading chapter"})
          return
        end

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, parsed.lines)
        vim.api.nvim_set_option_value("filetype", "ink_content", { buf = self.state.bufnr })

        -- Highlight found line and scroll to it
        if entry.line_num and entry.line_num > 0 then
          local total_lines = vim.api.nvim_buf_line_count(self.state.bufnr)
          -- Validate line number is within buffer bounds
          if entry.line_num <= total_lines then
            local ns = vim.api.nvim_create_namespace("ink_search_preview")
            vim.api.nvim_buf_add_highlight(self.state.bufnr, ns, "Search", entry.line_num - 1, 0, -1)

            -- Defer scroll to ensure buffer is ready
            local winid = self.state.winid
            local line_num = entry.line_num
            vim.defer_fn(function()
              if vim.api.nvim_win_is_valid(winid) then
                pcall(vim.api.nvim_win_set_cursor, winid, {line_num, 0})
                pcall(vim.api.nvim_win_call, winid, function()
                  vim.cmd("normal! zz")
                end)
              end
            end, 10)
          end
        end
      end
    }),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        render.render_chapter(selection.chapter_idx, selection.line_num, ctx)

        if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
          vim.api.nvim_set_current_win(ctx.content_win)
        end
      end)

      -- Toggle to TOC search
      if toggle_key then
        map('i', toggle_key, function()
          local current_picker = action_state.get_current_picker(prompt_bufnr)
          local current_prompt = current_picker:_get_prompt()
          actions.close(prompt_bufnr)
          M.search_toc(current_prompt)
        end)
      end

      return true
    end
  }):find()
end

function M.search_content(initial_text)
  local ctx = context.current()
  if not ctx or not ctx.data then
    vim.notify("No book currently open", vim.log.levels.WARN)
    return
  end

  local total_chapters = #ctx.data.spine
  local use_async = total_chapters > 50
  -- Enable live search for large indexes (more than 1000 entries expected)
  local use_live_search = total_chapters > 100

  if use_async and not ctx.search_index then
    -- Use async indexing for large books
    M.get_or_build_index(ctx, function(search_entries)
      open_search_picker(search_entries, initial_text, ctx, use_live_search)
    end)
  else
    -- Use sync indexing or return cached
    local search_entries = M.get_or_build_index(ctx)
    open_search_picker(search_entries, initial_text, ctx, use_live_search)
  end
end

return M
