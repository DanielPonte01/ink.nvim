local fs = require("ink.fs")

local M = {}

local function json_pretty_encode(data, indent)
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
        table.insert(items, spacing_inner .. json_pretty_encode(v, indent + 1))
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. spacing .. "]"
    else
      local items = {}
      for k, v in pairs(data) do
        local key = '"' .. tostring(k) .. '"'
        table.insert(items, spacing_inner .. key .. ": " .. json_pretty_encode(v, indent + 1))
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

function M.get_file_path()
  local data_dir = vim.fn.stdpath("data") .. "/ink.nvim"
  fs.ensure_dir(data_dir)
  return data_dir .. "/bookmarks.json"
end

function M.save(bookmarks)
  local path = M.get_file_path()
  local data = json_pretty_encode({ bookmarks = bookmarks })
  local file = io.open(path, "w")
  if file then
    file:write(data)
    file:close()
    return true
  end
  return false
end

function M.load()
  local path = M.get_file_path()
  if not fs.exists(path) then
    return { bookmarks = {} }
  end
  local content = fs.read_file(path)
  if not content then
    return { bookmarks = {} }
  end
  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data then
    return { bookmarks = {} }
  end
  return data
end

return M
