local M = {}

-- Check if a command exists
local function command_exists(cmd)
  -- Sanitize cmd to only allow safe characters (alphanumeric, dash, underscore)
  if not cmd:match("^[%w_-]+$") then
    return false
  end
  -- Use vim.fn.executable for safer command checking
  return vim.fn.executable(cmd) == 1
end

-- Ensure unzip is available
if not command_exists("unzip") then
  vim.notify("ink.nvim: 'unzip' command not found. Please install it.", vim.log.levels.ERROR)
end

-- Read file content
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
end

-- Check if file exists
function M.exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

-- Create directory if it doesn't exist
function M.ensure_dir(path)
  -- Use Neovim's built-in mkdir function (safer than os.execute)
  -- "p" flag creates parent directories as needed
  vim.fn.mkdir(path, "p")
end

-- Write content to file with error handling
function M.write_file(path, content)
  local file, err = io.open(path, "w")
  if not file then
    vim.notify("Failed to open file for writing: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return false, err
  end

  -- Wrap write in pcall to catch disk full, permission errors, etc.
  local ok, write_err = pcall(function()
    file:write(content or "")
  end)

  if not ok then
    file:close()
    vim.notify("Failed to write to file: " .. tostring(write_err), vim.log.levels.ERROR)
    return false, write_err
  end

  -- Wrap close in pcall as well (can fail on some systems)
  local close_ok, close_err = pcall(function()
    file:close()
  end)

  if not close_ok then
    vim.notify("Warning: Failed to close file: " .. tostring(close_err), vim.log.levels.WARN)
  end

  return true, nil
end

-- Get file modification time (returns timestamp or nil)
function M.get_mtime(path)
  local stat = vim.loop.fs_stat(path)
  if stat then
    return stat.mtime.sec
  end
  return nil
end

-- Check if directory exists
function M.dir_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "directory"
end

-- Remove directory recursively
function M.remove_dir(path)
  if not M.dir_exists(path) then
    return true
  end

  -- Use vim.fn.delete with 'rf' flag for recursive removal
  local result = vim.fn.delete(path, "rf")
  return result == 0
end

-- Unzip EPUB to destination
function M.unzip(epub_path, dest_dir)
  M.ensure_dir(dest_dir)

  -- Resolve and validate paths to prevent path traversal
  epub_path = vim.fn.resolve(vim.fn.fnamemodify(epub_path, ":p"))
  dest_dir = vim.fn.resolve(vim.fn.fnamemodify(dest_dir, ":p"))

  -- Use vim.fn.system with array for safer command execution
  -- -o: overwrite without prompting
  -- -q: quiet mode
  -- -d: destination directory
  vim.fn.system({"unzip", "-o", "-q", epub_path, "-d", dest_dir})
  return vim.v.shell_error == 0
end

return M
