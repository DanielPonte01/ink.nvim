-- lua/ink/library/scanning.lua
-- Directory scanning for EPUB and Markdown files

local M = {}

local fs = require("ink.fs")
local data = require("ink.library.data")

-- Validate directory path for safe characters
local function is_safe_path(path)
	-- Path should not contain shell metacharacters or suspicious patterns
	-- Allow: alphanumeric, /, -, _, ., ~, space
	if path:match("[;&|`$<>%(%){}%[%]!]") then
		return false
	end
	return true
end

-- Scan directory for EPUB and Markdown files (async)
function M.scan_directory(directory, callback)
	-- Expand and normalize directory path
	directory = vim.fn.fnamemodify(vim.fn.expand(directory), ":p")

	-- Validate path for security
	if not is_safe_path(directory) then
		if callback then
			callback(nil, "Invalid directory path: contains unsafe characters")
		end
		return
	end

	if not fs.exists(directory) then
		if callback then
			callback(nil, "Directory not found: " .. directory)
		end
		return
	end

	-- Find all files recursively using vim.loop (async)
	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)
	local files = {}
	local buffer = ""

	local handle = vim.loop.spawn("find", {
		args = { directory, "-type", "f", "(", "-name", "*.epub", "-o", "-name", "*.md", "-o", "-name", "*.markdown", ")" },
		stdio = { nil, stdout, stderr },
	}, function(code, signal)
		-- Process completed
		stdout:close()
		stderr:close()
	end)

	if not handle then
		if callback then
			callback(nil, "Failed to scan directory")
		end
		return
	end

	-- Read stdout (file paths)
	stdout:read_start(function(err, file_data)
		if err then
			if callback then
				vim.schedule(function()
					callback(nil, "Error reading find output: " .. err)
				end)
			end
			return
		end

		if file_data then
			buffer = buffer .. file_data
			-- Process complete lines
			for line in buffer:gmatch("([^\n]*)\n") do
				if line ~= "" then
					table.insert(files, line)
				end
			end
			-- Keep incomplete line in buffer
			buffer = buffer:match("[^\n]*$") or ""
		else
			-- EOF - process remaining buffer
			if buffer ~= "" then
				table.insert(files, buffer)
			end

			-- Now process all found files
			vim.schedule(function()
				M.process_files(files, callback)
			end)
		end
	end)

	-- Read stderr (ignore)
	stderr:read_start(function(err, stderr_data)
		-- Ignore stderr
	end)
end

-- Process files one by one with progress updates
function M.process_files(files, callback)
	local epub = require("ink.epub")
	local markdown = require("ink.markdown")
	local added = 0
	local skipped = 0
	local errors = {}
	local total = #files

	if total == 0 then
		if callback then
			callback({
				total = 0,
				added = 0,
				skipped = 0,
				errors = {},
			})
		end
		return
	end

	local current_idx = 0

	local function process_next()
		current_idx = current_idx + 1

		if current_idx > total then
			-- All done
			if callback then
				callback({
					total = total,
					added = added,
					skipped = skipped,
					errors = errors,
				})
			end
			return
		end

		local file_path = files[current_idx]
		local file_type = "unknown"

		-- Detect file type
		if file_path:match("%.epub$") then
			file_type = "EPUB"
		elseif file_path:match("%.md$") or file_path:match("%.markdown$") then
			file_type = "Markdown"
		end

		-- Show progress
		vim.schedule(function()
			vim.notify(
				string.format(
					"Processing %s %d/%d: %s",
					file_type,
					current_idx,
					total,
					vim.fn.fnamemodify(file_path, ":t")
				),
				vim.log.levels.INFO
			)
		end)

		-- Process this file
		local ok, parsed_data
		if file_type == "EPUB" then
			ok, parsed_data = pcall(epub.open, file_path, { skip_toc_generation = true })
		elseif file_type == "Markdown" then
			ok, parsed_data = pcall(markdown.open, file_path)
		else
			ok = false
			parsed_data = "Unsupported file type"
		end

		vim.schedule(function()
			if ok then
				local book_info = {
					slug = parsed_data.slug,
					title = parsed_data.title,
					author = parsed_data.author,
					language = parsed_data.language,
					date = parsed_data.date,
					description = parsed_data.description,
					path = parsed_data.path,
					format = parsed_data.format or "epub",
					total_chapters = #parsed_data.spine,
				}

				-- Check if book already exists
				local library = data.load()
				local exists = false
				for _, book in ipairs(library.books) do
					if book.slug == book_info.slug or book.path == book_info.path then
						exists = true
						break
					end
				end

				if not exists then
					-- Lazy load core to avoid circular dependency
					local core = require("ink.library.core")
					core.add_book(book_info)
					added = added + 1
				else
					skipped = skipped + 1
				end
			else
				table.insert(errors, { path = file_path, error = tostring(parsed_data) })
			end

			-- Process next file after small delay
			vim.defer_fn(process_next, 10)
		end)
	end

	-- Start processing
	process_next()
end

return M
