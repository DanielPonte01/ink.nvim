-- lua/ink/tracking.lua
-- Automatic reading session tracking via autocmds

local M = {}

local timer = nil
local augroup = nil

-- Setup tracking autocmds and timer
function M.setup(config)
  -- Check if tracking is enabled
  if not config.tracking or not config.tracking.enabled then
    return
  end

  -- Create augroup
  augroup = vim.api.nvim_create_augroup("InkReadingTracking", { clear = true })

  -- Autocmd: Start session on BufEnter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    pattern = "ink://*",
    callback = function()
      -- Get current book context
      local ok_context, context_module = pcall(require, "ink.ui.context")
      if not ok_context then
        return
      end

      local ctx = context_module.current()
      if not ctx or not ctx.data then
        return
      end

      -- Start reading session
      local ok_sessions, sessions = pcall(require, "ink.reading_sessions")
      if ok_sessions then
        sessions.start_session(ctx.data.slug, ctx.current_chapter_idx or 1)
      end
    end,
  })

  -- Autocmd: End session on BufLeave
  vim.api.nvim_create_autocmd("BufLeave", {
    group = augroup,
    pattern = "ink://*",
    callback = function()
      -- Get current book context
      local ok_context, context_module = pcall(require, "ink.ui.context")
      if not ok_context then
        return
      end

      local ctx = context_module.current()
      if not ctx or not ctx.data then
        return
      end

      -- End reading session
      local ok_sessions, sessions = pcall(require, "ink.reading_sessions")
      if ok_sessions then
        sessions.end_session(ctx.data.slug)
      end
    end,
  })

  -- Autocmd: End all sessions on VimLeavePre
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      -- End all active sessions
      local ok_sessions, sessions = pcall(require, "ink.reading_sessions")
      if ok_sessions then
        sessions.end_session(nil) -- nil = end all sessions
      end
    end,
  })

  -- Setup periodic timer for auto-save
  local interval = config.tracking.auto_save_interval or 300 -- 5 minutes default
  timer = vim.loop.new_timer()

  timer:start(
    interval * 1000, -- initial delay (milliseconds)
    interval * 1000, -- repeat interval (milliseconds)
    vim.schedule_wrap(function()
      -- Update all active sessions
      local ok_sessions, sessions = pcall(require, "ink.reading_sessions")
      if ok_sessions then
        sessions.update_active_session(nil) -- nil = update all
      end
    end)
  )
end

-- Stop tracking and cleanup resources
function M.stop()
  -- Stop and close timer
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end

  -- Clear autocmds
  if augroup then
    vim.api.nvim_clear_autocmds({ group = augroup })
    augroup = nil
  end
end

return M
