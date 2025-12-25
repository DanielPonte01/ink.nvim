local fs = require("ink.fs")

local M = {}

-- Base data directory
function M.get_data_dir()
  return vim.fn.stdpath("data") .. "/ink.nvim"
end

-- Validate slug for safe file operations
-- Slug should only contain alphanumeric, underscore, and dash
function M.validate_slug(slug)
  if not slug or type(slug) ~= "string" or slug == "" then
    return false, "Invalid slug: empty or not a string"
  end

  -- Slug should only contain safe characters: alphanumeric, underscore, dash
  if not slug:match("^[%w_-]+$") then
    return false, "Invalid slug: contains unsafe characters"
  end

  -- Prevent directory traversal
  if slug:match("%.%.") or slug:match("^%.") then
    return false, "Invalid slug: contains path traversal"
  end

  return true, nil
end

-- Book-specific directory (creates if needed)
function M.get_book_dir(slug)
  -- Validate slug before using it
  local valid, err = M.validate_slug(slug)
  if not valid then
    error("get_book_dir: " .. err)
  end

  local dir = M.get_data_dir() .. "/books/" .. slug
  fs.ensure_dir(dir)
  return dir
end

-- Safe JSON decode with error handling and backup
-- @param content: JSON string to decode
-- @param file_path: optional file path for logging/backup
-- @return decoded data or nil, error message
function M.json_decode_safe(content, file_path)
  if not content or content == "" then
    return nil, "Empty content"
  end

  local ok, result = pcall(vim.json.decode, content)
  if ok then
    return result, nil
  end

  -- Decode failed - log error
  local error_msg = tostring(result)
  if file_path then
    vim.notify(
      string.format("JSON decode error in %s: %s", vim.fn.fnamemodify(file_path, ":t"), error_msg),
      vim.log.levels.WARN
    )

    -- Create backup before any potential deletion
    local backup_path = file_path .. ".backup." .. os.time()
    local backup_ok = fs.write_file(backup_path, content)
    if backup_ok then
      vim.notify(
        string.format("Corrupted file backed up to: %s", vim.fn.fnamemodify(backup_path, ":t")),
        vim.log.levels.INFO
      )
    end
  end

  return nil, error_msg
end

-- Pretty-print JSON encoder
function M.json_encode(data, indent)
  indent = indent or 0
  local spacing = string.rep("  ", indent)
  local spacing_inner = string.rep("  ", indent + 1)

  if type(data) == "table" then
    local is_array = #data > 0 or next(data) == nil
    if is_array and #data > 0 then
      for k, _ in pairs(data) do
        if type(k) ~= "number" then
          is_array = false
          break
        end
      end
    end

    if is_array then
      if #data == 0 then return "[]" end
      local items = {}
      for _, v in ipairs(data) do
        table.insert(items, spacing_inner .. M.json_encode(v, indent + 1))
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. spacing .. "]"
    else
      local items = {}
      for k, v in pairs(data) do
        local key = '"' .. tostring(k) .. '"'
        table.insert(items, spacing_inner .. key .. ": " .. M.json_encode(v, indent + 1))
      end
      if #items == 0 then return "{}" end
      table.sort(items)
      return "{\n" .. table.concat(items, ",\n") .. "\n" .. spacing .. "}"
    end
  elseif type(data) == "string" then
    local escaped = data:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. escaped .. '"'
  elseif type(data) == "number" then
    return tostring(data)
  elseif type(data) == "boolean" then
    return data and "true" or "false"
  elseif data == nil then
    return "null"
  else
    return '"' .. tostring(data) .. '"'
  end
end

return M
