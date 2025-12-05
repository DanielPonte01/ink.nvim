local css_parser = require("ink.css_parser")

local M = {}

function M.parse_all_css_files(manifest, opf_dir, cache_dir)
  local validate_path = require("ink.epub.util").validate_path
  local class_styles = {}
  for id, item in pairs(manifest) do
    if item.media_type == "text/css" then
      local css_path = opf_dir .. "/" .. item.href
      local ok, validated_path = pcall(validate_path, css_path, cache_dir)
      if not ok then goto continue end
      local css_content = require("ink.fs").read_file(validated_path)
      if css_content then
        local styles = css_parser.parse_css(css_content)
        for class_name, style in pairs(styles) do
          class_styles[class_name] = style
        end
      end
    end
    ::continue::
  end
  return class_styles
end

return M