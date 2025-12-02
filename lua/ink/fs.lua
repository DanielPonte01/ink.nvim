local M = {}

-- Check if a command exists
local function command_exists(cmd)
  local handle = io.popen("command -v " .. cmd)
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result ~= ""
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
  os.execute("mkdir -p " .. vim.fn.shellescape(path))
end

-- Unzip EPUB to destination
function M.unzip(epub_path, dest_dir)
  M.ensure_dir(dest_dir)
  -- -o: overwrite without prompting
  -- -q: quiet mode
  -- -d: destination directory
  local cmd = string.format("unzip -o -q %s -d %s", vim.fn.shellescape(epub_path), vim.fn.shellescape(dest_dir))
  local result = os.execute(cmd)
  return result == 0
end

-- List files in directory (simple wrapper)
function M.scandir(directory)
    local i, t, popen = 0, {}, io.popen
    local pfile = popen('ls -a "'..directory..'"')
    if not pfile then return {} end
    for filename in pfile:lines() do
        i = i + 1
        t[i] = filename
    end
    pfile:close()
    return t
end

-- Join paths
function M.join(...)
  return table.concat({...}, "/") -- Simple join, assuming Unix for now
end

return M
