local lru_cache = require("ink.cache.lru")

local M = {}

M.config = { max_width = 120 }
M.ns_id = vim.api.nvim_create_namespace("ink_nvim")

-- Store contexts by content_buf
local contexts = {}

local function new_context()
  return {
    data = nil,
    current_chapter_idx = 1,
    toc_buf = nil,
    content_buf = nil,
    toc_win = nil,
    content_win = nil,
    images = {},
    links = {},
    anchors = {},
    justify_map = {},
    last_statusline_percent = 0,
    note_display_mode = M.config.note_display_mode or "indicator",
    rendered_lines = {},
    default_max_width = nil,
    current_max_width = nil,  -- Current max_width for this book (adaptive width), nil = use config default
    manual_width_override = false,  -- If true, user manually adjusted width, disable adaptive until reset
    parsed_chapters = lru_cache.new(15),  -- LRU cache with max 15 chapters
    search_index = nil,
    -- Glossary fields
    glossary_detection_index = nil,  -- Cache of detection index for performance
    glossary_matches = {},           -- Detected glossary terms in current chapter
    glossary_custom_types = {},      -- Custom types defined for this book
    glossary_visible = M.config.glossary_visible or true,  -- Whether to show glossary terms
    glossary_matches_cache = {       -- Versioned cache: { version = "hash", chapters = { [idx] = matches } }
      version = nil,
      chapters = {}
    },
    -- Padnotes fields
    padnote_buf = nil,               -- Buffer of current padnote (if open)
    padnote_win = nil,               -- Window of current padnote
    padnote_chapter = nil,           -- Chapter index of open padnote
    padnote_auto_save_timer = nil,   -- Auto-save timer
  }
end

-- Get context for a buffer (content, toc, or padnote)
function M.get(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  -- Direct match on content_buf
  if contexts[buf] then return contexts[buf] end
  -- Check if buf is a toc_buf or padnote_buf
  for _, ctx in pairs(contexts) do
    if ctx.toc_buf == buf then return ctx end
    if ctx.padnote_buf == buf then return ctx end
  end
  return nil
end

-- Get current context based on current buffer
function M.current()
  return M.get(vim.api.nvim_get_current_buf())
end

-- Create new context for a book
function M.create(content_buf)
  local ctx = new_context()
  ctx.content_buf = content_buf
  contexts[content_buf] = ctx
  return ctx
end

-- Remove context when book is closed
function M.remove(content_buf)
  contexts[content_buf] = nil
end

-- Legacy: M.ctx points to current context (for gradual migration)
M.ctx = setmetatable({}, {
  __index = function(_, k)
    local ctx = M.current()
    return ctx and ctx[k]
  end,
  __newindex = function(_, k, v)
    local ctx = M.current()
    if ctx then ctx[k] = v end
  end
})

function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config or {})
end

return M
