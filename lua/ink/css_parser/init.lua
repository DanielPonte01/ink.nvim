local parser = require("ink.css_parser.parser")
local highlighter = require("ink.css_parser.highlighter")

local M = {
    parse_css = parser.parse_css,
    get_highlight_groups = highlighter.get_highlight_groups
}

return M