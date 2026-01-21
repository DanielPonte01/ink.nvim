-- lua/ink/library/init.lua
-- Public interface for library module

local M = {}

-- Import submodules
local data = require("ink.library.data")
local core = require("ink.library.core")
local queries = require("ink.library.queries")
local statistics = require("ink.library.statistics")
local scanning = require("ink.library.scanning")

-- === CORE OPERATIONS ===

-- Add or update a book
M.add_book = core.add_book

-- Update reading progress
M.update_progress = core.update_progress

-- Remove a book
M.remove_book = core.remove_book

-- Set book tag
M.set_book_tag = core.set_book_tag

-- Open a book with format detection
M.open_book = core.open_book

-- Add linked resource to a book
M.add_linked_resource = core.add_linked_resource

-- Remove linked resource from a book
M.remove_linked_resource = core.remove_linked_resource

-- Get linked resources for a book
M.get_linked_resources = core.get_linked_resources

-- === QUERIES ===

-- Get all books
M.get_books = queries.get_books

-- Get completed books
M.get_completed_books = queries.get_completed_books

-- Get books currently reading
M.get_reading_books = queries.get_reading_books

-- Get books to read
M.get_to_read_books = queries.get_to_read_books

-- Get last opened book path
M.get_last_book_path = queries.get_last_book_path

-- Get books by format
M.get_books_by_format = queries.get_books_by_format

-- Get books grouped by format
M.get_books_grouped_by_format = queries.get_books_grouped_by_format

-- === STATISTICS ===

-- Get aggregated statistics
function M.get_statistics()
	local books = queries.get_books()
	return statistics.get_statistics(books)
end

-- Format timestamp as relative string
M.format_last_opened = statistics.format_last_opened

-- === SCANNING ===

-- Scan directory for books
M.scan_directory = scanning.scan_directory

-- Process files (internal, but exposed for compatibility)
M.process_files = scanning.process_files

-- Legacy function name for backward compatibility
M.process_epub_files = scanning.process_files

-- === DATA ACCESS ===

-- Load library (direct access)
M.load = data.load

-- Save library (direct access)
M.save = data.save

return M
