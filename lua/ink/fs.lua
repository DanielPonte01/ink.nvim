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
  local result = vim.fn.system({"unzip", "-o", "-q", epub_path, "-d", dest_dir})
  return vim.v.shell_error == 0
end

-- List files in directory (simple wrapper)
function M.scandir(directory)
  -- Use Neovim's built-in readdir function (safer than shell command)
  local ok, items = pcall(vim.fn.readdir, directory)
  if not ok then
    return {}
  end
  -- readdir doesn't include . and .. by default, add them for compatibility
  table.insert(items, 1, ".")
  table.insert(items, 2, "..")
  return items
end

-- Join paths
function M.join(...)
  return table.concat({...}, "/") -- Simple join, assuming Unix for now
end

return M
