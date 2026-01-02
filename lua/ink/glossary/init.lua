local data = require("ink.glossary.data")
local query = require("ink.glossary.query")
local actions = require("ink.glossary.actions")

local M = {}

-- Data layer
M.save = data.save
M.load = data.load
M.get_file_path = data.get_file_path

-- Query layer
M.get_all = query.get_all
M.get_by_id = query.get_by_id
M.get_by_term = query.get_by_term
M.get_by_type = query.get_by_type
M.search = query.search
M.get_related = query.get_related
M.get_types = query.get_types

-- Action layer
M.add = actions.add
M.update = actions.update
M.remove = actions.remove
M.add_alias = actions.add_alias
M.remove_alias = actions.remove_alias
M.add_related = actions.add_related
M.remove_related = actions.remove_related
M.add_custom_type = actions.add_custom_type

return M
