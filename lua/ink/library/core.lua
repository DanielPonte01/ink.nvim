-- lua/ink/library/core.lua
-- Core operations for library management

local M = {}

local data = require("ink.library.data")
local migration = require("ink.library.migration")

-- Add or update a book in the library
function M.add_book(book_info)
	local library = data.load()

	-- Find existing book by slug or path
	local found_idx = nil
	local existing_book = nil
	for i, book in ipairs(library.books) do
		if book.slug == book_info.slug or book.path == book_info.path then
			found_idx = i
			existing_book = book
			break
		end
	end

	local now = os.time()

	if found_idx then
		-- Update existing book
		local updated = vim.tbl_deep_extend("force", existing_book, book_info)

		-- Preserve first_opened (never overwrite)
		updated.first_opened = existing_book.first_opened or now

		-- Update last_opened
		updated.last_opened = now

		-- Check if book just got completed
		local was_completed = existing_book.chapter >= existing_book.total_chapters
		local now_completed = updated.chapter >= updated.total_chapters

		if not was_completed and now_completed and not updated.completed_date then
			updated.completed_date = now
		end

		-- Recalculate status
		updated.status = migration.calculate_status(updated)

		library.books[found_idx] = updated
		library.last_book_path = book_info.path
		data.save(library)
		return updated
	else
		-- Add new book
		book_info.last_opened = now
		book_info.first_opened = now

		-- Set chapter defaults
		book_info.chapter = book_info.chapter or 1
		book_info.total_chapters = book_info.total_chapters or 1

		-- Set completed_date if already completed
		if book_info.chapter >= book_info.total_chapters then
			book_info.completed_date = now
		else
			book_info.completed_date = nil
		end

		-- Calculate status
		book_info.status = migration.calculate_status(book_info)

		-- Set defaults for other fields
		book_info.title = book_info.title or "Unknown"
		book_info.author = book_info.author or "Unknown"
		book_info.format = book_info.format or "epub"
		book_info.tag = book_info.tag or ""
		book_info.related_resources = book_info.related_resources or {}

		table.insert(library.books, book_info)
		library.last_book_path = book_info.path
		data.save(library)
		return book_info
	end
end

-- Update reading progress for a book
function M.update_progress(slug, chapter, total_chapters)
	local library = data.load()

	for i, book in ipairs(library.books) do
		if book.slug == slug then
			local was_completed = book.chapter >= book.total_chapters
			local now_completed = chapter >= total_chapters

			book.chapter = chapter
			book.total_chapters = total_chapters
			book.last_opened = os.time()

			-- Set completed_date when completing the book
			if not was_completed and now_completed then
				book.completed_date = os.time()
			end

			-- Recalculate status
			book.status = migration.calculate_status(book)

			library.last_book_path = book.path
			data.save(library)
			return true
		end
	end

	return false
end

-- Remove a book from library
function M.remove_book(slug)
	local library = data.load()
	local new_books = {}

	for _, book in ipairs(library.books) do
		if book.slug ~= slug then
			table.insert(new_books, book)
		end
	end

	library.books = new_books
	data.save(library)

	-- Remove book from all collections
	local ok, collections = pcall(require, "ink.collections")
	if ok then
		collections.remove_book_from_all(slug)
	end

	-- Remove all related resources for this book
	local ok_related, related = pcall(require, "ink.data.related")
	if ok_related then
		related.remove_all_for_book(slug)
	end

	return true
end

-- Set tag for a book
function M.set_book_tag(slug, tag)
	local library = data.load()

	for i, book in ipairs(library.books) do
		if book.slug == slug then
			library.books[i].tag = tag
			data.save(library)
			return true
		end
	end

	return false
end

-- Add a linked resource to a book
-- @param book_slug: slug of the book to add link to
-- @param link_info: table with {slug, title, url, type} where type is "local" or "web"
-- @return boolean success
function M.add_related_resource(book_slug, related_info)
	local library = data.load()

	for i, book in ipairs(library.books) do
		if book.slug == book_slug then
			book.related_resources = book.related_resources or {}
			-- Check if link already exists
			for _, existing in ipairs(book.related_resources) do
				if existing.slug == related_info.slug then
					return false, "Link already exists"
				end
			end
			table.insert(book.related_resources, related_info)
			data.save(library)
			return true
		end
	end

	return false, "Book not found"
end

-- Remove a linked resource from a book
-- @param book_slug: slug of the book
-- @param related_slug: slug of the related resource to remove
-- @return boolean success
function M.remove_related_resource(book_slug, related_slug)
	local library = data.load()

	for i, book in ipairs(library.books) do
		if book.slug == book_slug then
			local new_links = {}
			for _, link in ipairs(book.related_resources or {}) do
				if link.slug ~= link_slug then
					table.insert(new_links, link)
				end
			end
			book.related_resources = new_links
			data.save(library)
			return true
		end
	end

	return false, "Book or link not found"
end

-- Get linked resources for a book
-- @param book_slug: slug of the book
-- @return table of linked resources or empty table
function M.get_related_resources(book_slug)
	local library = data.load()

	for _, book in ipairs(library.books) do
		if book.slug == book_slug then
			return book.related_resources or {}
		end
	end

	return {}
end

-- Open a book with automatic format detection
function M.open_book(book_path, book_format)
	local epub = require("ink.epub")
	local markdown = require("ink.markdown")
	local web = require("ink.web")

	-- Detect format if not provided
	if not book_format then
		if book_path:match("^https?://") and web.is_planalto_url(book_path) then
			book_format = "web"
		elseif book_path:match("%.md$") or book_path:match("%.markdown$") then
			book_format = "markdown"
		else
			book_format = "epub"
		end
	end

	-- Open with appropriate parser
	if book_format == "web" then
		return pcall(web.open, book_path)
	elseif book_format == "markdown" then
		return pcall(markdown.open, book_path)
	else
		return pcall(epub.open, book_path)
	end
end

return M
