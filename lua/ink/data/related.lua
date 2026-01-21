local M = {}

local fs = require("ink.fs")
local data_module = require("ink.data")

-- Get path to related.json
local function get_related_path()
	fs.ensure_dir(data_module.get_data_dir())
	return data_module.get_data_dir() .. "/related.json"
end

-- Load related data from disk
function M.load()
	local path = get_related_path()

	if not fs.exists(path) then
		return {}
	end

	local content = fs.read_file(path)
	if not content then
		return {}
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data then
		return {}
	end

	return data
end

-- Save related data to disk
function M.save(data)
	local path = get_related_path()
	local json = data_module.json_encode(data)

	local file = io.open(path, "w")
	if not file then
		return false
	end

	local ok = pcall(file.write, file, json)
	file:close()
	return ok
end

-- Add a related resource (reciprocal)
function M.add_related(book_slug, related_slug)
	local data = M.load()

	-- Initialize if not exists
	if not data[book_slug] then data[book_slug] = {} end
	if not data[related_slug] then data[related_slug] = {} end

	-- Add reciprocal relations
	data[book_slug][related_slug] = true
	data[related_slug][book_slug] = true

	return M.save(data)
end

-- Remove a related resource (reciprocal)
function M.remove_related(book_slug, related_slug)
	local data = M.load()

	local removed = false

	-- Remove related_slug from book_slug's relations
	if data[book_slug] and data[book_slug][related_slug] then
		data[book_slug][related_slug] = nil
		removed = true
	end

	-- Remove book_slug from related_slug's relations (reciprocal)
	if data[related_slug] and data[related_slug][book_slug] then
		data[related_slug][book_slug] = nil
		removed = true
	end

	if removed then
		return M.save(data)
	end

	return false
end

-- Get related resources for a book
function M.get_related(book_slug)
	local data = M.load()
	return data[book_slug] or {}
end

-- Get all related resources as a set
function M.get_related_slugs(book_slug)
	local related = M.get_related(book_slug)
	local slugs = {}
	for slug, _ in pairs(related) do
		table.insert(slugs, slug)
	end
	return slugs
end

-- Remove all relations for a specific book
-- This should be called when a book is deleted from the library
function M.remove_all_for_book(book_slug)
	local data = M.load()

	-- Remove the book's entry entirely
	if data[book_slug] then
		-- First, remove reciprocal references from all related books
		for related_slug, _ in pairs(data[book_slug]) do
			if data[related_slug] then
				data[related_slug][book_slug] = nil
			end
		end

		-- Then remove the book's own entry
		data[book_slug] = nil
	end

	-- Also remove this book from any other book's relations
	-- (in case of inconsistent data)
	for slug, relations in pairs(data) do
		if relations[book_slug] then
			relations[book_slug] = nil
		end
	end

	return M.save(data)
end

-- Get list of orphan references (slugs that don't exist in library)
-- Returns table with orphan slugs and the books that reference them
function M.get_orphan_references()
	local library = require("ink.library").load()
	local valid_slugs = {}

	-- Build set of valid slugs
	for _, book in ipairs(library.books or {}) do
		valid_slugs[book.slug] = true
	end

	local data = M.load()
	local orphans = {}

	-- Check all slugs in related.json
	for slug, relations in pairs(data) do
		if not valid_slugs[slug] then
			-- This slug doesn't exist in library
			table.insert(orphans, {
				slug = slug,
				referenced_by = vim.tbl_keys(relations)
			})
		end

		-- Also check if this book references non-existent books
		for related_slug, _ in pairs(relations) do
			if not valid_slugs[related_slug] then
				-- Find if we already have this orphan
				local found = false
				for _, orphan in ipairs(orphans) do
					if orphan.slug == related_slug then
						table.insert(orphan.referenced_by, slug)
						found = true
						break
					end
				end

				if not found then
					table.insert(orphans, {
						slug = related_slug,
						referenced_by = {slug}
					})
				end
			end
		end
	end

	return orphans
end

-- Clean up orphan references
-- Removes all references to books that no longer exist in library
-- Returns number of orphan slugs cleaned and list of cleaned slugs
function M.cleanup_orphans()
	local library = require("ink.library").load()
	local valid_slugs = {}

	-- Build set of valid slugs
	for _, book in ipairs(library.books or {}) do
		valid_slugs[book.slug] = true
	end

	local data = M.load()
	local cleaned_slugs = {}
	local cleaned_count = 0

	-- Remove invalid slugs and their references
	for slug, relations in pairs(data) do
		if not valid_slugs[slug] then
			-- This entire entry is orphaned
			table.insert(cleaned_slugs, slug)
			data[slug] = nil
			cleaned_count = cleaned_count + 1
		else
			-- Check if this valid book references invalid books
			for related_slug, _ in pairs(relations) do
				if not valid_slugs[related_slug] then
					relations[related_slug] = nil
					if not vim.tbl_contains(cleaned_slugs, related_slug) then
						table.insert(cleaned_slugs, related_slug)
					end
				end
			end

			-- Remove entry if it has no more relations
			if vim.tbl_count(relations) == 0 then
				data[slug] = nil
			end
		end
	end

	if cleaned_count > 0 or #cleaned_slugs > 0 then
		M.save(data)
	end

	return cleaned_count, cleaned_slugs
end

return M