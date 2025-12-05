local fs = require("ink.fs")

local M = {}

-- Base data directory
function M.get_data_dir()
  return vim.fn.stdpath("data") .. "/ink.nvim"
end

-- Book-specific directory (creates if needed)
function M.get_book_dir(slug)
  local dir = M.get_data_dir() .. "/books/" .. slug
  fs.ensure_dir(dir)
  return dir
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
