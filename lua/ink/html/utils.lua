local M = {}

-- Returns display width (visual columns) of a UTF-8 string
function M.display_width(str)
  return vim.fn.strdisplaywidth(str)
end

function M.merge_highlights(hls)
  if #hls == 0 then return hls end

  table.sort(hls, function(a, b)
    if a[1] ~= b[1] then
      return a[1] < b[1]
    end
    return a[2] < b[2]
  end)

  local merged = {}
  local current = hls[1]

  for i = 2, #hls do
    local next_hl = hls[i]

    if current[1] == next_hl[1] and
       current[4] == next_hl[4] and
       current[3] >= next_hl[2] - 1 then
      current[3] = math.max(current[3], next_hl[3])
    else
      table.insert(merged, current)
      current = next_hl
    end
  end

  table.insert(merged, current)
  return merged
end

function M.forward_map_column(word_info, col)
  if not word_info then return col end

  for _, wi in ipairs(word_info) do
    if col >= wi.orig_start and col < wi.orig_end then
      local offset = col - wi.orig_start
      return wi.new_start + offset
    elseif col == wi.orig_end then
      return wi.new_end
    end
  end

  for idx, wi in ipairs(word_info) do
    if col < wi.orig_start then
      if idx == 1 then
        return col
      else
        return wi.new_start
      end
    end
  end

  local last = word_info[#word_info]
  return last and last.new_end or col
end

function M.reverse_map_column(word_info, col)
  if not word_info then return col end

  for _, wi in ipairs(word_info) do
    if col >= wi.new_start and col < wi.new_end then
      local offset = col - wi.new_start
      return wi.orig_start + offset
    elseif col == wi.new_end then
      return wi.orig_end
    end
  end

  for idx, wi in ipairs(word_info) do
    if col < wi.new_start then
      if idx == 1 then
        return col
      else
        local prev = word_info[idx - 1]
        return prev.orig_end
      end
    end
  end

  local last = word_info[#word_info]
  return last and last.orig_end or col
end

return M