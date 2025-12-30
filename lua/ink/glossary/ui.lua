local glossary = require("ink.glossary")
local context = require("ink.ui.context")
local modals = require("ink.ui.modals")
local util = require("ink.ui.util")

local M = {}

-- Get glossary match at cursor position
function M.get_match_at_cursor(line, col)
  local ctx = context.current()
  if not ctx or not ctx.glossary_matches then
    return nil
  end

  for _, match in ipairs(ctx.glossary_matches) do
    if match.line == line then
      if col >= match.start_col and col < match.end_col then
        return match
      end
    end
  end

  return nil
end

-- Add glossary entry from visual selection
function M.add_from_selection(slug, callback)
  -- Get visual selection
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local start_line = start_pos[2]
  local end_line = end_pos[2]
  local start_col = start_pos[3]
  local end_col = end_pos[3]

  if start_line ~= end_line then
    vim.notify("Glossary entries must be on a single line", vim.log.levels.WARN)
    if callback then callback(nil) end
    return
  end

  -- Get the selected text
  local line = vim.api.nvim_buf_get_lines(0, start_line - 1, start_line, false)[1]
  if not line then
    if callback then callback(nil) end
    return
  end

  local selected_text = line:sub(start_col, end_col)
  if not selected_text or selected_text == "" then
    vim.notify("No text selected", vim.log.levels.WARN)
    if callback then callback(nil) end
    return
  end

  -- Trim whitespace
  selected_text = selected_text:match("^%s*(.-)%s*$")

  -- Check if entry already exists for this term
  local existing_entry = glossary.get_by_term(slug, selected_text)

  if existing_entry then
    -- Entry exists, open edit modal (full edit: type + definition)
    M.show_edit_entry_modal(slug, existing_entry, callback, true)
  else
    -- New entry, open add modal with pre-filled term
    M.show_add_entry_modal(slug, selected_text, callback)
  end
end

-- Parse definition content with aliases and relationships
-- Returns: { aliases = {...}, relationships = {...}, definition = "..." }
local function parse_definition_content(content)
  if not content or content == "" then
    return { aliases = {}, relationships = {}, definition = "" }
  end

  local lines = vim.split(content, "\n")

  local aliases = {}
  local relationships = {}
  local definition_lines = {}

  local mode = "metadata"  -- metadata → definition
  local line_idx = 1

  while line_idx <= #lines do
    local line = lines[line_idx]

    if mode == "metadata" then
      -- Check if it's an alias line
      if line:match("^Alias:%s*") then
        local alias_line = line:gsub("^Alias:%s*", "")
        if alias_line and alias_line ~= "" then
          for alias in alias_line:gmatch("[^,]+") do
            local trimmed = alias:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
              table.insert(aliases, trimmed)
            end
          end
        end
        line_idx = line_idx + 1
      -- Check if it's a relationship line (Label: terms)
      elseif line:match("^[A-Za-z][^:]*:%s*.+") then
        local label, terms_str = line:match("^([^:]+):%s*(.+)")
        if label and terms_str then
          -- Normalize label (lowercase, replace spaces with underscores)
          local normalized_label = label:match("^%s*(.-)%s*$"):lower():gsub("%s+", "_")

          -- Parse comma-separated terms
          local terms = {}
          for term in terms_str:gmatch("[^,]+") do
            local trimmed = term:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
              table.insert(terms, trimmed)
            end
          end

          if #terms > 0 then
            relationships[normalized_label] = terms
          end
        end
        line_idx = line_idx + 1
      -- Empty line, skip
      elseif line:match("^%s*$") then
        line_idx = line_idx + 1
      -- First non-metadata line: transition to definition
      else
        mode = "definition"
        table.insert(definition_lines, line)
        line_idx = line_idx + 1
      end
    elseif mode == "definition" then
      table.insert(definition_lines, line)
      line_idx = line_idx + 1
    end
  end

  local definition = table.concat(definition_lines, "\n"):match("^%s*(.-)%s*$") or ""

  return {
    aliases = aliases,
    relationships = relationships,
    definition = definition
  }
end

-- Format definition content with aliases and relationships
-- Returns formatted string ready for editing
local function format_definition_content(aliases, relationships, definition)
  local content = ""

  -- Always include Alias line (even if empty)
  local alias_str = ""
  if aliases and #aliases > 0 then
    alias_str = table.concat(aliases, ", ")
  end
  content = "Alias: " .. alias_str .. "\n\n"

  -- Add relationships if any
  if relationships and next(relationships) ~= nil then
    -- Sort relationship labels for consistent ordering
    local labels = {}
    for label, _ in pairs(relationships) do
      table.insert(labels, label)
    end
    table.sort(labels)

    for _, label in ipairs(labels) do
      local terms = relationships[label]
      -- Display label with proper capitalization
      local display_label = label:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
      end)

      content = content .. display_label .. ": " .. table.concat(terms, ", ") .. "\n"
    end

    content = content .. "\n"
  end

  -- Add definition
  if definition and definition ~= "" then
    content = content .. definition
  end

  return content
end

-- Custom definition editor for glossary
local function open_definition_editor(term_name, initial_aliases, initial_relationships, initial_definition, callback)
  -- Create buffer for editing
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  -- Format content with aliases and relationships
  local formatted_content = format_definition_content(initial_aliases, initial_relationships, initial_definition)
  local lines = vim.split(formatted_content, "\n")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Calculate window size (large and centered)
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.5)  -- 70% of screen width
  local height = math.floor(ui.height * 0.6)  -- 60% of screen height
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Create title with term name
  local title = string.format(" %s (Esc to save) ", term_name)

  -- Open floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center"
  })

  -- Configure window options
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })
  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

  -- Always start in normal mode

  -- Esc in insert mode: exit to normal mode
  vim.keymap.set("i", "<Esc>", function()
    vim.cmd("stopinsert")
  end, { buffer = buf })

  -- Esc in normal mode: save and close
  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      local content_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = table.concat(content_lines, "\n"):match("^%s*(.-)%s*$")

      -- Parse content to extract aliases and definition
      local parsed = parse_definition_content(content)

      vim.api.nvim_win_close(win, true)
      if callback then
        callback(parsed)
      end
    end
  end, { buffer = buf })
end

-- Edit existing glossary entry
-- allow_type_edit: if true, allows changing the type; if false, only edits definition
function M.show_edit_entry_modal(slug, entry, callback, allow_type_edit)
  if allow_type_edit == nil then
    allow_type_edit = true  -- Default to full edit
  end

  local function edit_definition(updated_type)
    open_definition_editor(entry.term, entry.aliases or {}, entry.relationships or {}, entry.definition or "", function(parsed)
      if not parsed then
        if callback then callback(nil) end
        return
      end

      -- Update entry with aliases, relationships, and definition
      glossary.update(slug, entry.id, {
        type = updated_type,
        definition = parsed.definition or "",
        aliases = parsed.aliases or {},
        relationships = parsed.relationships or {}
      })

      -- Reload entry for callback
      local updated_entry = glossary.get_by_id(slug, entry.id)
      if callback then callback(updated_entry) end
    end)
  end

  if allow_type_edit then
    -- Step 1: Edit type
    local types = {
      "character", "place", "concept", "organization",
      "object", "event", "foreign_word", "other"
    }

    vim.ui.select(types, {
      prompt = "Edit type (current: " .. entry.type .. "):",
      format_item = function(item)
        local icons = {
          character = "👤 Character",
          place = "📍 Place",
          concept = "💡 Concept",
          organization = "🏛️  Organization",
          object = "⚔️  Object",
          event = "⚡ Event",
          foreign_word = "🌐 Foreign Word",
          other = "📝 Other"
        }
        local label = icons[item] or item
        if item == entry.type then
          label = label .. " (current)"
        end
        return label
      end
    }, function(choice)
      if not choice then
        if callback then callback(nil) end
        return
      end

      -- Step 2: Edit definition with selected type
      edit_definition(choice)
    end)
  else
    -- Skip type selection, go directly to definition edit
    -- Keep current type
    edit_definition(entry.type)
  end
end

-- Simple add entry modal (basic version for Phase 3)
function M.show_add_entry_modal(slug, initial_term, callback)
  initial_term = initial_term or ""

  -- For now, create a simple 2-step process:
  -- Step 1: Get term
  -- Step 2: Get type
  -- Step 3: Get definition

  local entry = {
    term = initial_term,
    type = "other",
    definition = "",
    aliases = {}
  }

  -- Step 1: Get term
  modals.open_text_input(initial_term, function(term)
    if not term or term == "" then
      if callback then callback(nil) end
      return
    end
    entry.term = term

    -- Step 2: Type selection (simplified for now)
    local types = {
      "character", "place", "concept", "organization",
      "object", "event", "foreign_word", "other"
    }

    vim.ui.select(types, {
      prompt = "Select type:",
      format_item = function(item)
        local icons = {
          character = "👤 Character",
          place = "📍 Place",
          concept = "💡 Concept",
          organization = "🏛️  Organization",
          object = "⚔️  Object",
          event = "⚡ Event",
          foreign_word = "🌐 Foreign Word",
          other = "📝 Other"
        }
        return icons[item] or item
      end
    }, function(choice)
      if not choice then
        if callback then callback(nil) end
        return
      end
      entry.type = choice

      -- Step 3: Get definition using custom editor
      open_definition_editor(entry.term, {}, {}, "", function(parsed)
        if not parsed then
          if callback then callback(nil) end
          return
        end
        entry.definition = parsed.definition or ""
        entry.aliases = parsed.aliases or {}
        entry.relationships = parsed.relationships or {}

        -- Save entry
        local saved_entry = glossary.add(slug, entry)
        if callback then callback(saved_entry) end
      end)
    end)
  end, {
    title = " Glossary Term (Esc to continue) ",
    multiline = false,
    width = 50
  })
end

-- Preview entry in floating window
function M.show_entry_preview(match)
  local ctx = context.current()
  if not ctx then return end

  local entry = ctx.glossary_detection_index.entries[match.entry_id]
  if not entry then return end

  -- Create buffer for preview
  local buf = vim.api.nvim_create_buf(false, true)

  -- Format preview content
  local lines = {}

  -- Get type icon and name
  local types_config = vim.tbl_extend("force",
    context.config.glossary_types or {},
    ctx.glossary_custom_types or {}
  )
  local type_info = types_config[entry.type] or { icon = "📝", color = "InkGlossary" }
  local type_name = entry.type:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b)
    return a:upper() .. b
  end)

  -- Title line: icon + term (type)
  table.insert(lines, string.format("%s %s (%s)", type_info.icon, entry.term, type_name))

  -- Separator
  table.insert(lines, string.rep("─", 50))

  -- Aliases
  if entry.aliases and #entry.aliases > 0 then
    table.insert(lines, "Aliases: " .. table.concat(entry.aliases, ", "))
    table.insert(lines, "")
  end

  -- Relationships (with dynamic term resolution)
  if entry.relationships and next(entry.relationships) ~= nil then
    -- Sort labels for consistent display
    local labels = {}
    for label, _ in pairs(entry.relationships) do
      table.insert(labels, label)
    end
    table.sort(labels)

    for _, label in ipairs(labels) do
      local terms = entry.relationships[label]
      -- Display label with proper capitalization
      local display_label = label:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
      end)

      -- Resolve terms (try to find entries)
      local resolved_terms = {}
      for _, term_name in ipairs(terms) do
        -- Try to find entry by term name
        local found = false
        if ctx.glossary_detection_index and ctx.glossary_detection_index.entries then
          for _, existing_entry in pairs(ctx.glossary_detection_index.entries) do
            if existing_entry.term:lower() == term_name:lower() then
              table.insert(resolved_terms, term_name)  -- Found: normal display
              found = true
              break
            end
          end
        end
        if not found then
          table.insert(resolved_terms, term_name .. " (not found)")  -- Not found: indicate missing
        end
      end

      table.insert(lines, display_label .. ": " .. table.concat(resolved_terms, ", "))
    end

    table.insert(lines, "")
  end

  -- Separator before definition
  table.insert(lines, "---")
  table.insert(lines, "")

  -- Definition
  if entry.definition and entry.definition ~= "" then
    for _, line in ipairs(vim.split(entry.definition, "\n")) do
      table.insert(lines, line)
    end
  else
    table.insert(lines, "(No definition)")
  end

  table.insert(lines, "")

  -- Help line
  table.insert(lines, "q Close")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Calculate window size (large and centered, same as editor)
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.5)  -- 70% of screen width
  local height = math.floor(ui.height * 0.6)  -- 60% of screen height
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Create title with term name
  local title = string.format(" %s ", entry.term)

  -- Open floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center"
  })

  -- Configure window options
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })

  -- Close on q or Esc
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })
end

-- Show glossary browser for current book
-- Remove a glossary entry with confirmation and re-rendering
-- @param slug: book slug
-- @param entry: the entry to remove
-- @param reopen_browser: whether to reopen the glossary browser after deletion (default: false)
function M.remove_glossary_entry(slug, entry, reopen_browser)
  if not entry then return end

  -- Confirm deletion
  local response = vim.fn.input("Delete glossary entry '" .. entry.term .. "'? (y/N): ")
  vim.cmd('redraw')  -- Clear the input prompt

  if response:lower() == "y" then
    -- Remove from glossary
    glossary.remove(slug, entry.id)
    vim.notify("Glossary entry '" .. entry.term .. "' deleted", vim.log.levels.INFO)

    -- Re-render if book is open
    local ctx = context.current()
    if ctx and ctx.data and ctx.data.slug == slug then
      -- Clear all glossary-related caches and re-render
      local render = require("ink.ui.render")
      render.invalidate_glossary_cache(ctx)
      if ctx.content_win and vim.api.nvim_win_is_valid(ctx.content_win) then
        local cursor_pos = vim.api.nvim_win_get_cursor(ctx.content_win)
        render.render_chapter(ctx.current_chapter_idx, cursor_pos[1], ctx)
      else
        -- If no valid window, just render without cursor preservation
        render.render_chapter(ctx.current_chapter_idx, nil, ctx)
      end
    end

    -- Refresh browser if requested
    if reopen_browser then
      vim.schedule(function()
        M.show_glossary_browser(slug)
      end)
    end
  elseif reopen_browser then
    -- User cancelled, reopen browser only if it was open
    M.show_glossary_browser(slug)
  end
end

function M.show_glossary_browser(slug, force_floating)
  local glossary = require("ink.glossary")
  local entries = glossary.get_all(slug)

  if not entries or #entries == 0 then
    vim.notify("No glossary entries in this book", vim.log.levels.INFO)
    return
  end

  -- Force floating window if requested, otherwise try Telescope first
  if force_floating then
    M.show_glossary_floating(slug, entries)
  else
    local has_telescope, telescope = pcall(require, "telescope")

    if has_telescope then
      M.show_glossary_telescope(slug, entries)
    else
      M.show_glossary_floating(slug, entries)
    end
  end
end

-- Telescope picker for glossary
function M.show_glossary_telescope(slug, entries)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local previewers = require("telescope.previewers")

  -- Get type configuration
  local context = require("ink.ui.context")
  local types_config = context.config.glossary_types or {}

  -- Format entries for display
  local formatted_entries = {}
  for _, entry in ipairs(entries) do
    local type_info = types_config[entry.type] or { icon = "📝", color = "InkGlossary" }
    local type_name = entry.type:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b)
      return a:upper() .. b
    end)

    local display = string.format("%s %s (%s)", type_info.icon, entry.term, type_name)

    table.insert(formatted_entries, {
      display = display,
      entry = entry,
      ordinal = entry.term .. " " .. type_name .. " " .. (entry.definition or "")
    })
  end

  pickers.new({}, {
    prompt_title = "Glossary (<C-e> edit, <C-d> delete)",
    finder = finders.new_table({
      results = formatted_entries,
      entry_maker = function(item)
        return {
          value = item.entry,
          display = item.display,
          ordinal = item.ordinal
        }
      end
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer({
      title = "Definition",
      define_preview = function(self, entry)
        local e = entry.value
        local lines = {}

        -- Aliases
        if e.aliases and #e.aliases > 0 then
          table.insert(lines, "Aliases: " .. table.concat(e.aliases, ", "))
          table.insert(lines, "")
        end

        -- Relationships (with term resolution)
        if e.relationships and next(e.relationships) ~= nil then
          -- Sort labels for consistent display
          local labels = {}
          for label, _ in pairs(e.relationships) do
            table.insert(labels, label)
          end
          table.sort(labels)

          for _, label in ipairs(labels) do
            local terms = e.relationships[label]
            -- Display label with proper capitalization
            local display_label = label:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest)
              return first:upper() .. rest
            end)

            -- Resolve terms (try to find entries)
            local resolved_terms = {}
            for _, term_name in ipairs(terms) do
              -- Try to find entry by term name in all entries
              local found = false
              for _, existing_entry in ipairs(entries) do
                if existing_entry.term:lower() == term_name:lower() then
                  table.insert(resolved_terms, term_name)  -- Found
                  found = true
                  break
                end
              end
              if not found then
                table.insert(resolved_terms, term_name .. " (not found)")
              end
            end

            table.insert(lines, display_label .. ": " .. table.concat(resolved_terms, ", "))
          end

          table.insert(lines, "")
        end

        -- Separator before definition
        table.insert(lines, "---")
        table.insert(lines, "")

        -- Definition
        if e.definition and e.definition ~= "" then
          for _, line in ipairs(vim.split(e.definition, "\n")) do
            table.insert(lines, line)
          end
        else
          table.insert(lines, "(No definition)")
        end

        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end
    }),
    attach_mappings = function(prompt_bufnr, map)
      -- Enter: preview entry
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if selection then
          -- Create a mock match object for preview
          local mock_match = {
            entry_id = selection.value.id
          }

          -- Temporarily set the entry in a detection index for preview
          local ctx = context.current()
          local temp_index = {
            entries = {
              [selection.value.id] = selection.value
            }
          }

          -- Save current index and replace temporarily
          local saved_index = ctx and ctx.glossary_detection_index
          if ctx then
            ctx.glossary_detection_index = temp_index
          end

          M.show_entry_preview(mock_match)

          -- Restore index
          if ctx then
            ctx.glossary_detection_index = saved_index
          end
        end
      end)

      -- Ctrl-E: edit entry
      map("i", "<C-e>", function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if selection then
          M.show_edit_entry_modal(slug, selection.value, function(updated_entry)
            if updated_entry then
              vim.notify("Glossary entry '" .. updated_entry.term .. "' updated", vim.log.levels.INFO)
              -- Re-render if book is open
              local ctx = context.current()
              if ctx and ctx.data and ctx.data.slug == slug then
                local render = require("ink.ui.render")
                render.invalidate_glossary_cache(ctx)
                local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
                render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
              end
            end
          end, true)
        end
      end)

      map("n", "<C-e>", function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)

        if selection then
          M.show_edit_entry_modal(slug, selection.value, function(updated_entry)
            if updated_entry then
              vim.notify("Glossary entry '" .. updated_entry.term .. "' updated", vim.log.levels.INFO)
              -- Re-render if book is open
              local ctx = context.current()
              if ctx and ctx.data and ctx.data.slug == slug then
                local render = require("ink.ui.render")
                render.invalidate_glossary_cache(ctx)
                local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
                render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
              end
            end
          end, true)
        end
      end)

      -- Ctrl-D: delete entry (insert mode)
      map("i", "<C-d>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)
          M.remove_glossary_entry(slug, selection.value, true)  -- Reopen browser after deletion
        end
      end)

      -- Ctrl-D: delete entry (normal mode)
      map("n", "<C-d>", function()
        local selection = action_state.get_selected_entry()
        if selection then
          actions.close(prompt_bufnr)
          M.remove_glossary_entry(slug, selection.value, true)  -- Reopen browser after deletion
        end
      end)

      return true
    end
  }):find()
end

-- Floating window fallback for glossary browser
function M.show_glossary_floating(slug, entries)
  local context = require("ink.ui.context")
  local types_config = context.config.glossary_types or {}

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  -- Format lines
  local lines = {}
  local entry_map = {}  -- Map line number to entry

  table.insert(lines, "Glossary - " .. (#entries) .. " entries")
  table.insert(lines, "")
  table.insert(lines, "Enter: edit  d: delete  q: close")
  table.insert(lines, string.rep("─", 60))
  table.insert(lines, "")

  for _, entry in ipairs(entries) do
    local type_info = types_config[entry.type] or { icon = "📝", color = "InkGlossary" }
    local type_name = entry.type:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b)
      return a:upper() .. b
    end)

    local line = string.format("%s %s (%s)", type_info.icon, entry.term, type_name)
    table.insert(lines, line)
    entry_map[#lines] = entry
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  -- Calculate window size
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.min(80, math.floor(ui.width * 0.8))
  local height = math.min(#lines + 2, math.floor(ui.height * 0.8))
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Open window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Glossary Browser ",
    title_pos = "center"
  })

  -- Close on q or Esc
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })

  -- Enter: edit entry
  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_num = cursor[1]
    local entry = entry_map[line_num]

    if entry then
      vim.api.nvim_win_close(win, true)

      M.show_edit_entry_modal(slug, entry, function(updated_entry)
        if updated_entry then
          vim.notify("Glossary entry '" .. updated_entry.term .. "' updated", vim.log.levels.INFO)
          -- Re-render if book is open
          local ctx = context.current()
          if ctx and ctx.data and ctx.data.slug == slug then
            local render = require("ink.ui.render")
            render.invalidate_glossary_cache(ctx)
            local cursor_pos = vim.api.nvim_win_get_cursor(ctx.content_win)
            render.render_chapter(ctx.current_chapter_idx, cursor_pos[1], ctx)
          end
        end
      end, true)
    end
  end, { buffer = buf })

  -- d: delete entry
  vim.keymap.set("n", "d", function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    local line_num = cursor[1]
    local entry = entry_map[line_num]

    if entry then
      local response = vim.fn.input("Delete glossary entry '" .. entry.term .. "'? (y/N): ")
      if response:lower() == "y" then
        glossary.remove(slug, entry.id)
        vim.notify("Glossary entry '" .. entry.term .. "' deleted", vim.log.levels.INFO)

        -- Refresh browser
        vim.api.nvim_win_close(win, true)
        M.show_glossary_browser(slug)

        -- Re-render if book is open
        local ctx = context.current()
        if ctx and ctx.data and ctx.data.slug == slug then
          local render = require("ink.ui.render")
          render.invalidate_glossary_cache(ctx)
          local cursor_pos = vim.api.nvim_win_get_cursor(ctx.content_win)
          render.render_chapter(ctx.current_chapter_idx, cursor_pos[1], ctx)
        end
      end
    end
  end, { buffer = buf })
end

-- Show graph visualization for a specific term
function M.show_term_graph(slug, term_or_entry)
  local glossary = require("ink.glossary")
  local graph = require("ink.glossary.graph")

  -- Get entry if term string was passed
  local entry
  if type(term_or_entry) == "string" then
    entry = glossary.get_by_term(slug, term_or_entry)
    if not entry then
      vim.notify("Term '" .. term_or_entry .. "' not found in glossary", vim.log.levels.WARN)
      return
    end
  else
    entry = term_or_entry
  end

  -- Get all entries for resolution
  local all_entries = glossary.get_all(slug)

  -- Generate graph
  local lines = graph.generate_term_graph(entry, all_entries)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  -- Calculate window size
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.6)
  local height = math.floor(ui.height * 0.6)
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Open floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = string.format(" %s - Relationships ", entry.term),
    title_pos = "center"
  })

  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("linebreak", true, { win = win })

  -- Close on q or Esc
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })
end

-- Show full glossary graph
function M.show_full_graph(slug)
  local glossary = require("ink.glossary")
  local graph = require("ink.glossary.graph")

  local entries = glossary.get_all(slug)

  if not entries or #entries == 0 then
    vim.notify("No glossary entries in this book", vim.log.levels.INFO)
    return
  end

  -- Generate full graph
  local lines = graph.generate_full_graph(entries)

  -- Add help text at bottom
  table.insert(lines, "")
  table.insert(lines, "q/Esc - Close")

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })

  -- Calculate window size
  local ui = vim.api.nvim_list_uis()[1]
  local width = math.floor(ui.width * 0.7)
  local height = math.floor(ui.height * 0.7)
  local row = math.floor((ui.height - height) / 2)
  local col = math.floor((ui.width - width) / 2)

  -- Open floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Glossary Graph ",
    title_pos = "center"
  })

  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", true, { win = win })

  -- Close on q or Esc
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf })
end

return M
