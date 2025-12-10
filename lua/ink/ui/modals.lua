-- lua/ink/ui/modals.lua
-- Responsabilidade: Floating windows de input reutilizáveis

local M = {}

-- Generic text input modal
-- opts: { title, min_height, max_height, width, wrap, multiline }
function M.open_text_input(initial_text, callback, opts)
  opts = opts or {}
  local buf = vim.api.nvim_create_buf(false, true)
  local width = opts.width or 60
  local min_height = opts.min_height or (opts.multiline and 3 or 1)
  local max_height = opts.max_height or (opts.multiline and 15 or 5)
  local title = opts.title or " Input (Esc to save) "
  local wrap = opts.wrap ~= nil and opts.wrap or opts.multiline

  local function calc_height(lines)
    return math.max(min_height, math.min(#lines, max_height))
  end

  local initial_lines
  if opts.multiline then
    initial_lines = (initial_text and initial_text ~= "") and vim.split(initial_text, "\n") or {""}
  else
    initial_lines = (initial_text and initial_text ~= "") and {initial_text} or {""}
  end

  if initial_text and initial_text ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial_lines)
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = calc_height(initial_lines),
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  if wrap then
    vim.api.nvim_set_option_value("wrap", true, { win = win })
  end

  local function resize_win()
    if not vim.api.nvim_win_is_valid(win) then return end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local new_height = calc_height(lines)
    vim.api.nvim_win_set_config(win, { height = new_height })
  end

  local augroup = vim.api.nvim_create_augroup("InkModalResize", { clear = true })
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    group = augroup,
    buffer = buf,
    callback = resize_win,
  })

  if not initial_text or initial_text == "" then
    vim.cmd("startinsert")
  end

  vim.keymap.set("i", "<Esc>", function()
    vim.cmd("stopinsert")
  end, { buffer = buf })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_del_augroup_by_id(augroup)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text
    if opts.multiline then
      text = table.concat(lines, "\n"):match("^%s*(.-)%s*$")
    else
      text = table.concat(lines, " "):match("^%s*(.-)%s*$")
    end
    vim.api.nvim_win_close(win, true)
    if callback then callback(text) end
  end, { buffer = buf })
end

-- Convenience function for bookmarks (single line)
function M.open_bookmark_input(initial_name, callback)
  M.open_text_input(initial_name, callback, {
    title = " Bookmark name (Esc to save, empty to cancel) ",
    multiline = false,
    min_height = 1,
    max_height = 5,
    wrap = false
  })
end

-- Convenience function for notes (multiline)
function M.open_note_input(initial_note, callback)
  M.open_text_input(initial_note, callback, {
    title = " Note (Esc to save, empty to remove) ",
    multiline = true,
    min_height = 3,
    max_height = 15,
    wrap = true
  })
end

return M
