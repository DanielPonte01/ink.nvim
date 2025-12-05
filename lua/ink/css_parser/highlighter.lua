local M = {}

-- Convert parsed CSS styles to highlight group names
function M.get_highlight_groups(style)
  local groups = {}

  if style.bold then
    table.insert(groups, "InkBold")
  end

  if style.italic then
    table.insert(groups, "InkItalic")
  end

  if style.underline then
    table.insert(groups, "InkUnderlined")
  end

  if style.strikethrough then
    table.insert(groups, "InkStrikethrough")
  end

  return groups
end

return M