-- lua/ink/library/data.lua
-- Persistence layer for library

local M = {}

local fs = require("ink.fs")
local data_module = require("ink.data")
local entities = require("ink.html.entities")

-- Get path to library.json
local function get_library_path()
	fs.ensure_dir(data_module.get_data_dir())
	return data_module.get_data_dir() .. "/library.json"
end

-- Migrate library data to decode HTML entities
local function migrate_decode_entities(library)
	-- Check if migration is needed (v2 includes proper tag removal)
	if library.entities_decoded_v2 then
		return library
	end

	-- Decode entities and clean HTML in all books
	for _, book in ipairs(library.books or {}) do
		if book.title then
			book.title = entities.decode_entities(book.title)
		end
		if book.author then
			book.author = entities.decode_entities(book.author)
		end
		if book.description then
			-- Decode entities FIRST, then remove HTML tags
			book.description = entities.decode_entities(book.description)
			book.description = book.description:gsub("<[^>]+>", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")
		end
	end

	-- Mark as migrated (v2)
	library.entities_decoded_v2 = true
	library.entities_decoded = nil  -- Remove old flag

	return library
end

-- Load library from disk
function M.load()
	local path = get_library_path()

	if not fs.exists(path) then
		return { books = {}, last_book_path = nil }
	end

	local content = fs.read_file(path)
	if not content then
		return { books = {}, last_book_path = nil }
	end

	local ok, lib = pcall(vim.json.decode, content)
	if not ok or not lib then
		return { books = {}, last_book_path = nil }
	end

	-- Ensure books array exists
	lib.books = lib.books or {}

	-- Run migrations
	lib = migrate_decode_entities(lib)

	-- Save migrated data
	if lib.entities_decoded_v2 then
		M.save(lib)
	end

	return lib
end

-- Save library to disk
function M.save(library)
	local path = get_library_path()
	local json = data_module.json_encode(library)

	local file = io.open(path, "w")
	if file then
		file:write(json)
		file:close()
		return true
	end
	return false
end

return M
