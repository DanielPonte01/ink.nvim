-- Module interface for notes management
local M = {}

-- Re-export query functions
M.get_all_notes = require("ink.notes.query").get_all_notes
M.get_book_notes = require("ink.notes.query").get_book_notes
M.get_all_notes_async = require("ink.notes.query").get_all_notes_async

-- Re-export UI functions
M.show_all_notes = require("ink.notes.ui").show_all_notes
M.show_book_notes = require("ink.notes.ui").show_book_notes

return M
