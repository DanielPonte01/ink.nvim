local M = {}

M.config = { max_width = 120 }

-- Current book context
M.ctx = {
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
  last_statusline_percent = 0,  -- Track last percentage to reduce updates
  note_display_mode = "indicator",  -- "off", "indicator", "expanded"
  rendered_lines = {}, -- Store current rendered lines for highlight matching
  default_max_width = nil -- Store default width to restore on close
}

function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config or {})
end

return M
