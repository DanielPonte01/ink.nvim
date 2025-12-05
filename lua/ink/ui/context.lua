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
    note_display_mode = "indicator",
    rendered_lines = {},
    default_max_width = nil
  }
end

-- Get context for a buffer (content or toc)
function M.get(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  -- Direct match on content_buf
  if contexts[buf] then return contexts[buf] end
  -- Check if buf is a toc_buf
  for _, ctx in pairs(contexts) do
    if ctx.toc_buf == buf then return ctx end
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
