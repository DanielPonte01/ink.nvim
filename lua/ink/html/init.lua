local M = {}

M.entities = require("ink.html.entities")
M.tokens = require("ink.html.tokens")
M.parser = require("ink.html.parser")
M.formatter = require("ink.html.formatter")
M.utils = require("ink.html.utils")

function M.parse(content, max_width, class_styles, justify_text, typography)
  return M.parser.parse(content, max_width, class_styles, justify_text, typography)
end

M.forward_map_column = M.utils.forward_map_column
M.reverse_map_column = M.utils.reverse_map_column

return M