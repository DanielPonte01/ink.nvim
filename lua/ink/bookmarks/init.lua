local data = require("ink.bookmarks.data")
local query = require("ink.bookmarks.query")
local actions = require("ink.bookmarks.actions")

local M = {}

-- Data
M.save = data.save
M.load = data.load
M.get_file_path = data.get_file_path

-- Query
M.get_all = query.get_all
M.get_by_book = query.get_by_book
M.get_chapter_bookmarks = query.get_chapter_bookmarks
M.find_by_id = query.find_by_id
M.find_at_line = query.find_at_line
M.get_next = query.get_next
M.get_prev = query.get_prev

-- Actions
M.add = actions.add
M.update = actions.update
M.remove = actions.remove

return M
