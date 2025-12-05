local M = {}

function M.get_slug(path)
  local filename = vim.fn.fnamemodify(path, ":t:r")
  return filename:gsub("[^%w]", "_")
end

function M.validate_path(path, base_dir)
  local resolved = vim.fn.resolve(path)
  local base = vim.fn.resolve(base_dir)

  if resolved:sub(1, #base) ~= base then
    error("Path traversal attempt detected: " .. path)
  end

  return resolved
end

function M.normalize_path(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 and parts[#parts] ~= ".." then
        table.remove(parts)
      else
        table.insert(parts, part)
      end
    elseif part ~= "." then
      table.insert(parts, part)
    end
  end
  return table.concat(parts, "/")
end

return M