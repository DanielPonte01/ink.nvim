-- lua/ink/dashboard/library_dashboard.lua
-- Main library-focused dashboard

local M = {}

local state = {
	buffer = nil,
	current_page = 1,
	items_per_page = 15,
	current_collection = nil, -- nil = All Books
	collection_index = 0, -- 0 = All Books, 1+ = collection index
	books = {},
	collections = {},
	-- Advanced filters
	sort_by = "last_opened", -- "last_opened", "title", "progress", "date_added"
	search_query = nil, -- nil or string for title search
	-- Extmarks namespace for centering
	ns_id = vim.api.nvim_create_namespace("ink_dashboard"),
}

-- Cache system to avoid reloading data too frequently
local cache = {
	books = nil,
	collections = nil,
	last_update = 0,
	ttl = 30, -- seconds
}

-- Show library dashboard
function M.show()
	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "ink://dashboard/library")

	-- Buffer options
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "ink-dashboard")

	-- Show in current window
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Store state
	state.buffer = buf
	state.current_page = 1

	-- Load data and render
	M.load_data()
	M.render()

	-- Setup keymaps
	M.setup_keymaps(buf)

	-- Setup autocmds
	M.setup_autocmds(buf)
end

-- Invalidate cache (call after operations that modify data)
function M.invalidate_cache()
	cache.books = nil
	cache.collections = nil
	cache.last_update = 0
end

-- Load book and collection data (with caching)
function M.load_data(force_reload)
	local library = require("ink.library")
	local collections = require("ink.collections")
	local now = os.time()

	-- Check cache validity
	local use_cache = not force_reload
		and cache.books
		and cache.collections
		and (now - cache.last_update) < cache.ttl

	if use_cache then
		-- Use cached data
		local all_books
		if state.current_collection then
			-- Filter by collection from cached books
			all_books = {}
			for _, book in ipairs(cache.books) do
				local book_collections = collections.get_book_collections(book.slug) or {}
				for _, coll_id in ipairs(book_collections) do
					if coll_id == state.current_collection then
						table.insert(all_books, book)
						break
					end
				end
			end
		else
			all_books = cache.books
		end

		state.books = M.filter_and_sort_books(all_books)
		state.collections = cache.collections
	else
		-- Fetch fresh data
		local all_books
		if state.current_collection then
			-- Filter by collection
			all_books = collections.get_collection_books(state.current_collection)
		else
			-- All books
			all_books = library.get_books()
		end

		-- Apply filters and sorting
		state.books = M.filter_and_sort_books(all_books)

		-- Get all collections
		state.collections = collections.get_all() or {}

		-- Update cache (only cache full library data, not filtered by collection)
		if not state.current_collection then
			cache.books = all_books
			cache.collections = state.collections
			cache.last_update = now
		end
	end
end

-- Filter and sort books based on current state
-- @param books: table[] - List of books
-- @return filtered_books: table[] - Filtered and sorted books
function M.filter_and_sort_books(books)
	local filtered = {}

	-- Apply filters
	for _, book in ipairs(books) do
		local include = true

		-- Search query filter (case insensitive title search)
		if state.search_query and state.search_query ~= "" then
			local title = (book.title or ""):lower()
			local query = state.search_query:lower()
			if not title:find(query, 1, true) then
				include = false
			end
		end

		if include then
			table.insert(filtered, book)
		end
	end

	-- Sort books
	if state.sort_by == "title" then
		table.sort(filtered, function(a, b)
			return (a.title or ""):lower() < (b.title or ""):lower()
		end)
	elseif state.sort_by == "progress" then
		table.sort(filtered, function(a, b)
			local a_progress = 0
			if a.total_chapters and a.total_chapters > 0 then
				a_progress = (a.chapter or 1) / a.total_chapters
			end
			local b_progress = 0
			if b.total_chapters and b.total_chapters > 0 then
				b_progress = (b.chapter or 1) / b.total_chapters
			end
			return a_progress > b_progress
		end)
	elseif state.sort_by == "date_added" then
		table.sort(filtered, function(a, b)
			return (a.first_opened or 0) > (b.first_opened or 0)
		end)
	else -- "last_opened" (default)
		table.sort(filtered, function(a, b)
			return (a.last_opened or 0) > (b.last_opened or 0)
		end)
	end

	return filtered
end

-- Render dashboard
function M.render()
	if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
		return
	end

	-- Clear all extmarks
	vim.api.nvim_buf_clear_namespace(state.buffer, state.ns_id, 0, -1)

	local lines = {}
	local line_paddings = {} -- Track padding for each line
	local win_width = vim.api.nvim_win_get_width(0)

	-- Title
	local title = "Ink.Nvim"
	local title_padding = math.floor((win_width - #title) / 2)
	table.insert(lines, title)
	table.insert(line_paddings, title_padding)

	-- Collection name and filters (subtitle)
	local subtitle_parts = {}

	-- Collection
	if state.current_collection then
		local collection_name = "Unknown Collection"
		for _, coll in ipairs(state.collections) do
			if coll.id == state.current_collection then
				collection_name = coll.name
				break
			end
		end
		table.insert(subtitle_parts, collection_name)
	else
		table.insert(subtitle_parts, "All Books")
	end

	-- Sort
	local sort_names = {
		last_opened = "Recent",
		title = "A-Z",
		progress = "Progress",
		date_added = "Added"
	}
	table.insert(subtitle_parts, "Sort: " .. (sort_names[state.sort_by] or state.sort_by))

	-- Search query
	if state.search_query and state.search_query ~= "" then
		table.insert(subtitle_parts, "Search: \"" .. state.search_query .. "\"")
	end

	local subtitle = table.concat(subtitle_parts, " • ")
	local subtitle_padding = math.floor((win_width - vim.fn.strwidth(subtitle)) / 2)
	table.insert(lines, subtitle)
	table.insert(line_paddings, subtitle_padding)

	-- Empty line
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	-- Calculate pagination
	local total_books = #state.books
	local total_pages = math.ceil(total_books / state.items_per_page)
	local start_idx = (state.current_page - 1) * state.items_per_page + 1
	local end_idx = math.min(start_idx + state.items_per_page - 1, total_books)

	-- Box width (slightly narrower than window for margins)
	local box_width = math.min(win_width - 4, 120)
	local box_padding = math.floor((win_width - box_width) / 2)

	-- Top border
	table.insert(lines, "┌" .. string.rep("─", box_width - 2) .. "┐")
	table.insert(line_paddings, box_padding)

	-- Header line: LIBRARY on left, Page info on right
	local page_info = string.format("Page %d/%d • %d books", state.current_page, total_pages, total_books)
	local header_text = "LIBRARY"
	local header_text_width = vim.fn.strwidth(header_text)
	local page_info_width = vim.fn.strwidth(page_info)
	local header_spacing = box_width - 2 - header_text_width - page_info_width
	local header_line = "│" .. header_text .. string.rep(" ", header_spacing) .. page_info .. "│"
	table.insert(lines, header_line)
	table.insert(line_paddings, box_padding)

	-- Render books
	for i = start_idx, end_idx do
		local book = state.books[i]
		if book then
			local line = M.format_book_line(book, box_width - 2)
			table.insert(lines, "│" .. line .. "│")
			table.insert(line_paddings, box_padding)
		end
	end

	-- Fill empty lines if less than items_per_page
	local rendered_count = end_idx - start_idx + 1
	for i = rendered_count + 1, state.items_per_page do
		table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
		table.insert(line_paddings, box_padding)
	end

	-- Bottom border
	table.insert(lines, "└" .. string.rep("─", box_width - 2) .. "┘")
	table.insert(line_paddings, box_padding)

	-- Shortcuts help (4 lines with better spacing)
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	local help1 = "Enter=open | j/k=navigate | n/p=page | c=cycle | s=stats | R=refresh | q=quit"
	local help3 = "<leader>f: o=sort f=find c=clear  |  <leader>b: p=preview d=delete  |  <leader>c: n=new d=delete a=add r=remove"

	-- Calculate positions for titles based on help3 content
	local help3_padding = math.floor((win_width - vim.fn.strwidth(help3)) / 2)
	local filters_pos = string.find(help3, "<leader>f:")
	local book_pos = string.find(help3, "<leader>b:")
	local collections_pos = string.find(help3, "<leader>c:")

	-- Build help2 with titles aligned to their sections
	local help2_width = vim.fn.strwidth(help3)
	local help2_chars = {}
	for i = 1, help2_width do
		help2_chars[i] = " "
	end

	-- Place titles at calculated positions
	local title_filters = "Filters"
	local title_book = "Book"
	local title_collections = "Collections"

	-- Insert "Filters" at filters_pos
	for i = 1, #title_filters do
		help2_chars[filters_pos + i - 1] = title_filters:sub(i, i)
	end

	-- Insert "Book" at book_pos
	for i = 1, #title_book do
		help2_chars[book_pos + i - 1] = title_book:sub(i, i)
	end

	-- Insert "Collections" at collections_pos
	for i = 1, #title_collections do
		help2_chars[collections_pos + i - 1] = title_collections:sub(i, i)
	end

	local help2 = table.concat(help2_chars)

	local help1_padding = math.floor((win_width - vim.fn.strwidth(help1)) / 2)
	local help2_padding = help3_padding -- Same padding as help3

	table.insert(lines, help1)
	table.insert(line_paddings, help1_padding)
	table.insert(lines, help2)
	table.insert(line_paddings, help2_padding)
	table.insert(lines, help3)
	table.insert(line_paddings, help3_padding)

	-- Set buffer content
	vim.api.nvim_buf_set_option(state.buffer, "modifiable", true)
	vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(state.buffer, "modifiable", false)

	-- Apply extmarks for centering
	for i, padding in ipairs(line_paddings) do
		if padding > 0 then
			local pad_str = string.rep(" ", padding)
			vim.api.nvim_buf_set_extmark(state.buffer, state.ns_id, i - 1, 0, {
				virt_text = { { pad_str, "Normal" } },
				virt_text_pos = "inline",
				priority = 100,
			})
		end
	end
end

-- Format a single book line
-- @param book: table - Book data
-- @param width: number - Available width
-- @return line: string
function M.format_book_line(book, width)
	local text_utils = require("ink.dashboard.utils.text")

	-- Extract data
	local title = book.title or "Unknown"
	local author = book.author or "Unknown"

	-- Get first collection name with indicator for multiple collections
	local collections = require("ink.collections")
	local collection_ids = collections.get_book_collections(book.slug) or {}
	local collection_text = "—"
	if #collection_ids > 0 then
		local first_collection = collections.get(collection_ids[1])
		if first_collection then
			collection_text = first_collection.name
			-- Add indicator if book is in multiple collections
			if #collection_ids == 2 then
				collection_text = collection_text .. "[+]"
			elseif #collection_ids > 2 then
				collection_text = collection_text .. "[+" .. (#collection_ids - 1) .. "]"
			end
		end
	end

	-- Last opened
	local last_opened = text_utils.format_date(book.last_opened)

	-- Completion (just percentage)
	local completion = "0%"
	if book.total_chapters and book.total_chapters > 0 then
		local current = book.chapter or 1
		local percent = math.floor((current / book.total_chapters) * 100)
		completion = string.format("%d%%", percent)
	end

	-- Fixed column widths for right side (visual width)
	local author_width = 20
	local collection_width = 15
	local time_width = 10
	local completion_width = 4

	-- Truncate and pad using visual width
	local function fit_string(str, target_width)
		local visual_width = vim.fn.strwidth(str)
		if visual_width > target_width then
			-- Truncate
			local result = ""
			local current_width = 0
			for i = 1, vim.fn.strchars(str) do
				local char = vim.fn.strcharpart(str, i - 1, 1)
				local char_width = vim.fn.strwidth(char)
				if current_width + char_width > target_width - 3 then
					return result .. "..."
				end
				result = result .. char
				current_width = current_width + char_width
			end
			return result
		else
			-- Pad
			return str .. string.rep(" ", target_width - visual_width)
		end
	end

	-- Format right side columns
	local author_padded = fit_string(author, author_width)
	local collection_padded = fit_string(collection_text, collection_width)
	local time_padded = fit_string(last_opened, time_width)
	local completion_padded = fit_string(completion, completion_width)

	local right_side = author_padded .. "  " .. collection_padded .. "  " .. time_padded .. "  " .. completion_padded

	-- Calculate title space
	local prefix = ">>>  "
	local prefix_width = vim.fn.strwidth(prefix)
	local right_side_width = vim.fn.strwidth(right_side)
	-- Total width calculation: prefix + title + spacing(2) + right_side
	local available_for_title = width - prefix_width - right_side_width - 2

	if available_for_title < 10 then
		available_for_title = 10
	end

	-- Format title
	local title_padded = fit_string(title, available_for_title)

	return prefix .. title_padded .. "  " .. right_side
end

-- Setup keymaps
function M.setup_keymaps(buf)
	local opts = { noremap = true, silent = true, buffer = buf }

	-- Open book
	vim.keymap.set("n", "<CR>", function()
		M.open_book_at_cursor()
	end, opts)

	-- Navigate
	vim.keymap.set("n", "j", "j", opts)
	vim.keymap.set("n", "k", "k", opts)

	-- Next page
	vim.keymap.set("n", "n", function()
		M.next_page()
	end, opts)

	-- Previous page
	vim.keymap.set("n", "p", function()
		M.prev_page()
	end, opts)

	-- Cycle collection (no leader)
	vim.keymap.set("n", "c", function()
		M.toggle_collection()
	end, opts)

	-- Toggle stats dashboard
	vim.keymap.set("n", "s", function()
		M.show_stats_dashboard()
	end, opts)

	-- Quit
	vim.keymap.set("n", "q", function()
		vim.api.nvim_buf_delete(buf, { force = true })
	end, opts)

	-- Refresh (force reload)
	vim.keymap.set("n", "R", function()
		M.invalidate_cache()
		M.load_data(true)
		M.render()
		vim.notify("Dashboard Reloaded", vim.log.levels.INFO)
	end, opts)

	-- FILTERS GROUP (<leader>f)
	vim.keymap.set("n", "<leader>fo", function()
		M.cycle_sort()
	end, opts)

	vim.keymap.set("n", "<leader>ff", function()
		M.search_books()
	end, opts)

	vim.keymap.set("n", "<leader>fc", function()
		M.clear_all_filters()
	end, opts)

	-- BOOK GROUP (<leader>b)
	vim.keymap.set("n", "<leader>bp", function()
		M.show_book_preview()
	end, opts)

	vim.keymap.set("n", "<leader>bd", function()
		M.delete_book()
	end, opts)

	-- COLLECTIONS GROUP (<leader>c)
	vim.keymap.set("n", "<leader>cn", function()
		M.create_collection()
	end, opts)

	vim.keymap.set("n", "<leader>cd", function()
		M.delete_collection()
	end, opts)

	vim.keymap.set("n", "<leader>ca", function()
		M.add_book_to_collection()
	end, opts)

	vim.keymap.set("n", "<leader>cr", function()
		M.remove_book_from_collection()
	end, opts)
end

-- Setup autocmds
function M.setup_autocmds(buf)
	local group = vim.api.nvim_create_augroup("InkLibraryDashboard", { clear = false })

	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		buffer = buf,
		callback = function()
			state.buffer = nil
		end,
	})

	-- Enable cursorline for visual feedback
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		group = group,
		buffer = buf,
		callback = function()
			vim.wo.cursorline = true
		end,
	})

	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = group,
		buffer = buf,
		callback = function()
			vim.wo.cursorline = false
		end,
	})

	-- Re-render on window resize to update centering
	vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		buffer = buf,
		callback = function()
			M.render()
		end,
	})
end

-- Open book at cursor
function M.open_book_at_cursor()
	local book = M.get_book_at_cursor()
	if not book or not book.path then
		return
	end

	-- Open book
	local epub = require("ink.epub")
	local ui = require("ink.ui")

	local book_data, err = epub.open(book.path)
	if not book_data then
		vim.notify("Failed to open book: " .. (err or "unknown error"), vim.log.levels.ERROR)
		return
	end

	ui.open_book(book_data)
end

-- Next page
function M.next_page()
	local total_pages = math.ceil(#state.books / state.items_per_page)
	if state.current_page < total_pages then
		state.current_page = state.current_page + 1
		M.render()
	end
end

-- Previous page
function M.prev_page()
	if state.current_page > 1 then
		state.current_page = state.current_page - 1
		M.render()
	end
end

-- Toggle collection
function M.toggle_collection()
	if #state.collections == 0 then
		vim.notify("No collections available", vim.log.levels.INFO)
		return
	end

	-- Cycle: All Books -> Collection 1 -> Collection 2 -> ... -> All Books
	state.collection_index = state.collection_index + 1

	if state.collection_index > #state.collections then
		-- Back to All Books
		state.collection_index = 0
		state.current_collection = nil
	else
		-- Select collection
		state.current_collection = state.collections[state.collection_index].id
	end

	-- Reset to first page
	state.current_page = 1

	-- Reload and render
	M.load_data()
	M.render()
end

-- Show stats dashboard
function M.show_stats_dashboard()
	local stats_dashboard = require("ink.dashboard.stats_dashboard")
	stats_dashboard.show()
end

-- Create new collection
function M.create_collection()
	-- Prompt for collection name
	vim.ui.input({ prompt = "Collection name: " }, function(name)
		if not name or name == "" then
			return
		end

		local collections = require("ink.collections")

		-- Create collection
		local success, err = pcall(collections.create, name, "")

		if success then
			vim.notify("Collection '" .. name .. "' created", vim.log.levels.INFO)
			-- Invalidate cache and reload
			M.invalidate_cache()
			M.load_data(true)
			M.render()
		else
			vim.notify("Failed to create collection: " .. tostring(err), vim.log.levels.ERROR)
		end
	end)
end

-- Delete collection
function M.delete_collection()
	local collections_module = require("ink.collections")

	-- Get all collections
	if #state.collections == 0 then
		vim.notify("No collections available", vim.log.levels.WARN)
		return
	end

	-- Build list of collection names
	local collection_names = {}
	for _, coll in ipairs(state.collections) do
		table.insert(collection_names, coll.name)
	end

	-- Use vim.ui.select to choose collection to delete
	vim.ui.select(collection_names, {
		prompt = "Delete which collection:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		local collection = state.collections[idx]

		-- Confirm deletion
		vim.ui.input({
			prompt = string.format("Delete collection '%s'? (y/N): ", collection.name),
		}, function(input)
			if not input or (input:lower() ~= "y" and input:lower() ~= "yes") then
				vim.notify("Cancelled", vim.log.levels.INFO)
				return
			end

			local success, err = pcall(collections_module.delete, collection.id)

			if success then
				vim.notify("Collection '" .. collection.name .. "' deleted", vim.log.levels.INFO)

				-- If currently viewing deleted collection, reset to All Books
				if state.current_collection == collection.id then
					state.current_collection = nil
					state.collection_index = 0
					state.current_page = 1
				end

				-- Invalidate cache and reload
				M.invalidate_cache()
				M.load_data(true)
				M.render()
			else
				vim.notify("Failed to delete collection: " .. tostring(err), vim.log.levels.ERROR)
			end
		end)
	end)
end

-- Get book at cursor
-- @return book: table|nil
function M.get_book_at_cursor()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line_num = cursor[1]

	-- Books start at line 6
	if line_num < 6 then
		return nil
	end

	-- Calculate book offset
	local book_line_offset = line_num - 5

	-- Calculate absolute book index
	local start_idx = (state.current_page - 1) * state.items_per_page + 1
	local book_idx = start_idx + book_line_offset - 1

	if book_idx < 1 or book_idx > #state.books then
		return nil
	end

	return state.books[book_idx]
end

-- Add book to collection
function M.add_book_to_collection()
	local book = M.get_book_at_cursor()
	if not book then
		vim.notify("No book selected", vim.log.levels.WARN)
		return
	end

	local collections = require("ink.collections")

	-- Get all collections
	if #state.collections == 0 then
		vim.notify("No collections available. Create one with 'C'", vim.log.levels.WARN)
		return
	end

	-- Build list of collection names
	local collection_names = {}
	for _, coll in ipairs(state.collections) do
		table.insert(collection_names, coll.name)
	end

	-- Use vim.ui.select to choose collection
	vim.ui.select(collection_names, {
		prompt = "Add '" .. book.title .. "' to collection:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		local collection = state.collections[idx]
		local success, err = pcall(collections.add_book, collection.id, book.slug)

		if success then
			vim.notify("Added to '" .. collection.name .. "'", vim.log.levels.INFO)
			-- Invalidate cache and reload
			M.invalidate_cache()
			M.load_data(true)
			M.render()
		else
			vim.notify("Failed to add book: " .. tostring(err), vim.log.levels.ERROR)
		end
	end)
end

-- Remove book from collection
function M.remove_book_from_collection()
	local book = M.get_book_at_cursor()
	if not book then
		vim.notify("No book selected", vim.log.levels.WARN)
		return
	end

	local collections_module = require("ink.collections")

	-- Get collection IDs this book is in
	local collection_ids = collections_module.get_book_collections(book.slug) or {}

	if #collection_ids == 0 then
		vim.notify("Book is not in any collection", vim.log.levels.WARN)
		return
	end

	-- Get full collection objects
	local book_collections = {}
	for _, coll_id in ipairs(collection_ids) do
		local coll = collections_module.get(coll_id)
		if coll then
			table.insert(book_collections, coll)
		end
	end

	if #book_collections == 0 then
		vim.notify("Book is not in any collection", vim.log.levels.WARN)
		return
	end

	-- Function to confirm and remove from a collection
	local function confirm_and_remove(collection)
		vim.ui.input({
			prompt = string.format("Remove '%s' from '%s'? (y/N): ", book.title, collection.name),
		}, function(input)
			if not input or (input:lower() ~= "y" and input:lower() ~= "yes") then
				vim.notify("Cancelled", vim.log.levels.INFO)
				return
			end

			local success, err = pcall(collections_module.remove_book, collection.id, book.slug)

			if success then
				vim.notify("Removed from '" .. collection.name .. "'", vim.log.levels.INFO)
				-- Invalidate cache and reload
				M.invalidate_cache()
				M.load_data(true)
				M.render()
			else
				vim.notify("Failed to remove book: " .. tostring(err), vim.log.levels.ERROR)
			end
		end)
	end

	-- If only one collection, go straight to confirmation
	if #book_collections == 1 then
		confirm_and_remove(book_collections[1])
		return
	end

	-- Multiple collections - let user choose which one
	local collection_names = {}
	for _, coll in ipairs(book_collections) do
		table.insert(collection_names, coll.name)
	end

	vim.ui.select(collection_names, {
		prompt = "Remove from which collection:",
	}, function(choice, idx)
		if not choice or not idx then
			return
		end

		confirm_and_remove(book_collections[idx])
	end)
end

-- Cycle sort order
function M.cycle_sort()
	local sorts = { "last_opened", "title", "progress", "date_added" }
	local current_idx = 1

	-- Find current sort in list
	for i, sort in ipairs(sorts) do
		if state.sort_by == sort then
			current_idx = i
			break
		end
	end

	-- Move to next sort
	current_idx = current_idx + 1
	if current_idx > #sorts then
		current_idx = 1
	end

	state.sort_by = sorts[current_idx]
	state.current_page = 1

	-- Reload and render
	M.load_data()
	M.render()

	-- Notify user
	local sort_names = {
		last_opened = "Recently Opened",
		title = "Title (A-Z)",
		progress = "Progress",
		date_added = "Date Added"
	}
	vim.notify("Sort by: " .. sort_names[state.sort_by], vim.log.levels.INFO)
end

-- Search books by title
function M.search_books()
	vim.ui.input({
		prompt = "Search books (title): ",
		default = state.search_query or ""
	}, function(query)
		if query == nil then
			return -- User cancelled
		end

		if query == "" then
			state.search_query = nil
		else
			state.search_query = query
		end

		state.current_page = 1

		-- Reload and render
		M.load_data()
		M.render()

		if state.search_query then
			vim.notify("Found " .. #state.books .. " book(s)", vim.log.levels.INFO)
		else
			vim.notify("Search cleared", vim.log.levels.INFO)
		end
	end)
end

-- Clear all filters
function M.clear_all_filters()
	state.search_query = nil
	state.sort_by = "last_opened"
	state.current_page = 1
	M.load_data()
	M.render()
	vim.notify("All filters cleared", vim.log.levels.INFO)
end

-- Show book preview in floating window
function M.show_book_preview()
	local book = M.get_book_at_cursor()
	if not book then
		vim.notify("No book selected", vim.log.levels.WARN)
		return
	end

	-- Get additional data
	local user_highlights = require("ink.user_highlights")
	local bookmarks_module = require("ink.bookmarks")
	local collections = require("ink.collections")

	-- Get all highlights for this book (all chapters)
	local highlights_data_all = user_highlights.load(book.slug)
	local all_highlights = highlights_data_all.highlights or {}
	local highlights_count = #all_highlights
	local notes_count = 0
	for _, hl in ipairs(all_highlights) do
		if hl.note and hl.note ~= "" then
			notes_count = notes_count + 1
		end
	end

	local bookmarks = bookmarks_module.get_by_book(book.slug) or {}
	local collection_ids = collections.get_book_collections(book.slug) or {}

	-- Build preview content
	local lines = {}
	local max_width = 70

	-- Title
	table.insert(lines, "╔" .. string.rep("═", max_width - 2) .. "╗")
	local title = book.title or "Unknown"
	if vim.fn.strwidth(title) > max_width - 4 then
		title = title:sub(1, max_width - 7) .. "..."
	end
	local title_pad = math.floor((max_width - 2 - vim.fn.strwidth(title)) / 2)
	table.insert(lines, "║" .. string.rep(" ", title_pad) .. title .. string.rep(" ", max_width - 2 - title_pad - vim.fn.strwidth(title)) .. "║")
	table.insert(lines, "╠" .. string.rep("═", max_width - 2) .. "╣")

	-- Author
	local author = "by " .. (book.author or "Unknown")
	table.insert(lines, "║ " .. author .. string.rep(" ", max_width - 3 - vim.fn.strwidth(author)) .. "║")
	table.insert(lines, "║" .. string.rep(" ", max_width - 2) .. "║")

	-- Description (if available)
	if book.description and book.description ~= "" then
		local desc = book.description
		if vim.fn.strwidth(desc) > max_width - 6 then
			desc = desc:sub(1, max_width - 9) .. "..."
		end
		table.insert(lines, "║ " .. desc .. string.rep(" ", max_width - 3 - vim.fn.strwidth(desc)) .. "║")
		table.insert(lines, "║" .. string.rep(" ", max_width - 2) .. "║")
	end

	-- Progress
	local progress_text = "Progress:"
	if book.total_chapters and book.total_chapters > 0 then
		local current = book.chapter or 1
		local percent = math.floor((current / book.total_chapters) * 100)
		progress_text = progress_text .. string.format(" Chapter %d/%d (%d%%)", current, book.total_chapters, percent)

		-- Progress bar
		local bar_width = 40
		local filled = math.floor((percent / 100) * bar_width)
		local empty = bar_width - filled
		local bar = string.rep("█", filled) .. string.rep("░", empty)
		table.insert(lines, "║ " .. progress_text .. string.rep(" ", max_width - 3 - vim.fn.strwidth(progress_text)) .. "║")
		table.insert(lines, "║ " .. bar .. string.rep(" ", max_width - 3 - vim.fn.strwidth(bar)) .. "║")
	else
		table.insert(lines, "║ " .. progress_text .. " N/A" .. string.rep(" ", max_width - 7 - vim.fn.strwidth(progress_text)) .. "║")
	end
	table.insert(lines, "║" .. string.rep(" ", max_width - 2) .. "║")

	-- Last opened
	local text_utils = require("ink.dashboard.utils.text")
	local last_opened = "Last opened: " .. text_utils.format_date(book.last_opened)
	table.insert(lines, "║ " .. last_opened .. string.rep(" ", max_width - 3 - vim.fn.strwidth(last_opened)) .. "║")

	-- First opened (date added)
	if book.first_opened then
		local first_opened = "Added: " .. text_utils.format_date(book.first_opened)
		table.insert(lines, "║ " .. first_opened .. string.rep(" ", max_width - 3 - vim.fn.strwidth(first_opened)) .. "║")
	end

	table.insert(lines, "║" .. string.rep(" ", max_width - 2) .. "║")

	-- Collections
	if #collection_ids > 0 then
		local coll_line = "Collections: "
		local coll_names = {}
		for _, coll_id in ipairs(collection_ids) do
			local coll = collections.get(coll_id)
			if coll then
				table.insert(coll_names, coll.name)
			end
		end
		coll_line = coll_line .. table.concat(coll_names, ", ")
		if vim.fn.strwidth(coll_line) > max_width - 4 then
			coll_line = coll_line:sub(1, max_width - 7) .. "..."
		end
		table.insert(lines, "║ " .. coll_line .. string.rep(" ", max_width - 3 - vim.fn.strwidth(coll_line)) .. "║")
		table.insert(lines, "║" .. string.rep(" ", max_width - 2) .. "║")
	end

	-- Stats
	local stats_line = string.format("Highlights: %d  •  Notes: %d  •  Bookmarks: %d", highlights_count, notes_count, #bookmarks)
	table.insert(lines, "║ " .. stats_line .. string.rep(" ", max_width - 3 - vim.fn.strwidth(stats_line)) .. "║")

	-- Bottom border
	table.insert(lines, "╠" .. string.rep("═", max_width - 2) .. "╣")
	local actions = "[Enter] Open  [d] Delete  [q] Close"
	local actions_pad = math.floor((max_width - 2 - vim.fn.strwidth(actions)) / 2)
	table.insert(lines, "║" .. string.rep(" ", actions_pad) .. actions .. string.rep(" ", max_width - 2 - actions_pad - vim.fn.strwidth(actions)) .. "║")
	table.insert(lines, "╚" .. string.rep("═", max_width - 2) .. "╝")

	-- Create floating window
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")

	local width = max_width
	local height = #lines
	local win_width = vim.api.nvim_get_option("columns")
	local win_height = vim.api.nvim_get_option("lines")

	local row = math.floor((win_height - height) / 2)
	local col = math.floor((win_width - width) / 2)

	local opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "none",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)

	-- Keymaps for preview window
	local function close_preview()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	vim.keymap.set("n", "q", close_preview, { buffer = buf, noremap = true, silent = true })
	vim.keymap.set("n", "<Esc>", close_preview, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("n", "<CR>", function()
		close_preview()
		M.open_book_at_cursor()
	end, { buffer = buf, noremap = true, silent = true })

	vim.keymap.set("n", "d", function()
		close_preview()
		M.delete_book()
	end, { buffer = buf, noremap = true, silent = true })

	-- Auto-close on cursor leave
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		buffer = buf,
		once = true,
		callback = function()
			close_preview()
		end,
	})
end

-- Quick Actions

-- Delete book from library
function M.delete_book()
	local book = M.get_book_at_cursor()
	if not book then
		vim.notify("No book selected", vim.log.levels.WARN)
		return
	end

	-- Confirm deletion
	vim.ui.input({
		prompt = string.format("Delete '%s' from library? (y/N): ", book.title),
	}, function(input)
		if not input or (input:lower() ~= "y" and input:lower() ~= "yes") then
			vim.notify("Cancelled", vim.log.levels.INFO)
			return
		end

		local library = require("ink.library")
		local success, err = pcall(library.remove_book, book.slug)

		if success then
			vim.notify("Book deleted from library", vim.log.levels.INFO)
			M.invalidate_cache()
			M.load_data(true)
			M.render()
		else
			vim.notify("Failed to delete book: " .. tostring(err), vim.log.levels.ERROR)
		end
	end)
end

return M
