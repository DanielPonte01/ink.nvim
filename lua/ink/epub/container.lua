local M = {}

function M.parse_container_xml(container_xml)
  local rootfile_tag = container_xml:match("<rootfile%s+[^>]+>")
  local function get_attribute(tag_string, attr)
    local escaped_attr = attr:gsub("([%-%^%$%(%)%%%.%[%]%*%+%?])", "%%%1")
    return tag_string:match(escaped_attr .. '=["\']([^"\']+)["\']')
  end
  local opf_rel_path = get_attribute(rootfile_tag, "full-path")
  return opf_rel_path
end

return M