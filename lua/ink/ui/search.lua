local fs = require("ink.fs")
local html = require("ink.html")
local context = require("ink.ui.context")
local render = require("ink.ui.render")

local M = {}

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

function M.search_content(initial_text)
  local ok, builtin = pcall(require, 'telescope.builtin')
  if not ok then vim.notify("Telescope not found. Install telescope.nvim to use search.", vim.log.levels.ERROR); return end
  local ctx = context.current()
  if not ctx or not ctx.data then vim.notify("No book currently open", vim.log.levels.WARN); return end

  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local toggle_key = context.config.keymaps.search_mode_toggle or "<C-f>"
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
        local filename = vim.fn.fnamemodify(selection.filename, ":t")
        local line_num = selection.lnum
        for idx, chapter in ipairs(ctx.data.spine) do
          if chapter.href:match(filename) then
            render.render_chapter(idx, line_num, ctx)
            if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then vim.api.nvim_set_current_win(ctx.content_win) end
            return
          end
        end
        vim.notify("Could not find chapter for: " .. filename, vim.log.levels.WARN)
      end)
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
  })
end

return M
