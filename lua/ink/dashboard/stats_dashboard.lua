-- lua/ink/dashboard/stats_dashboard.lua
-- Statistics-focused dashboard

local M = {}

local state = {
	buffer = nil,
	data = {},
	ns_id = vim.api.nvim_create_namespace("ink_stats_dashboard"),
}

-- Cache system to avoid reloading data too frequently
local cache = {
	data = nil,
	timestamp = 0,
	ttl = 60, -- 60 seconds
}

-- Helper to find buffer by name
local function find_buf_by_name(name)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			local buf_name = vim.api.nvim_buf_get_name(buf)
			if buf_name == name then
				return buf
			end
		end
	end
	return nil
end

-- Show stats dashboard
-- @param opts table|nil - Options: { in_new_tab = true/false }
function M.show(opts)
	opts = opts or {}
	local in_new_tab = opts.in_new_tab ~= false -- default true

	local buf_name = "ink://dashboard/stats"

	-- Delete existing buffer if it exists
	local existing_buf = find_buf_by_name(buf_name)
	if existing_buf then
		vim.api.nvim_buf_delete(existing_buf, { force = true })
	end

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, buf_name)

	-- Buffer options
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "swapfile", false)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "ink-dashboard")

	-- Open in new tab or current window
	local win
	if in_new_tab then
		vim.cmd("tabnew")
		win = vim.api.nvim_get_current_win()
	else
		win = vim.api.nvim_get_current_win()
	end
	vim.api.nvim_win_set_buf(win, buf)

	-- Store state
	state.buffer = buf

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
	cache.data = nil
	cache.timestamp = 0
end

-- Load statistics data
function M.load_data(force_reload)
	-- Check cache validity
	local now = os.time()
	local use_cache = not force_reload
		and cache.data
		and (now - cache.timestamp) < cache.ttl

	if use_cache then
		state.data = cache.data
		return
	end

	-- Load fresh data
	local library = require("ink.library")
	local sessions = require("ink.reading_sessions")
	local collections = require("ink.collections")

	-- Validation
	local books = library.get_books() or {}
	if #books == 0 then
		state.data = M.get_default_stats()
		cache.data = state.data
		cache.timestamp = now
		return
	end

	-- Reading statistics
	local total_books = #books
	local completed = 0
	local reading = 0
	local to_read = 0

	for _, book in ipairs(books) do
		if book.status == "completed" then
			completed = completed + 1
		elseif book.status == "reading" then
			reading = reading + 1
		elseif book.status == "to-read" then
			to_read = to_read + 1
		end
	end

	-- Time statistics (optimized - single call)
	local total_time = sessions.get_total_reading_time()
	local month_sessions = sessions.get_reading_by_day(30)  -- Get 30 days of data

	-- Calculate week and month time from hash table
	local week_time = 0
	local month_time = 0
	local today = os.time()
	local week_cutoff = os.date("%Y-%m-%d", today - (7 * 86400))
	local days_with_reading = 0

	for date, minutes in pairs(month_sessions) do
		month_time = month_time + minutes
		days_with_reading = days_with_reading + 1
		if date >= week_cutoff then
			week_time = week_time + minutes
		end
	end

	-- Calculate daily average (only count days with actual reading)
	local daily_avg = days_with_reading > 0 and (month_time / days_with_reading) or 0

	-- Progress statistics
	local total_chapters = 0
	local current_chapters = 0
	for _, book in ipairs(books) do
		if book.total_chapters and book.total_chapters > 0 then
			total_chapters = total_chapters + book.total_chapters
			current_chapters = current_chapters + (book.chapter or 1)
		end
	end
	local overall_completion = total_chapters > 0 and math.floor((current_chapters / total_chapters) * 100) or 0

	-- Streak calculation
	local current_streak, longest_streak = sessions.calculate_streak()

	-- Top 5 most read books
	local top_books = {}
	for _, book in ipairs(books) do
		local book_time = sessions.get_total_reading_time(book.slug)
		if book_time > 0 then
			table.insert(top_books, {
				title = book.title,
				author = book.author,
				time = book_time,
				slug = book.slug,
			})
		end
	end
	table.sort(top_books, function(a, b) return a.time > b.time end)
	-- Keep only top 5
	local top_5_books = {}
	for i = 1, math.min(5, #top_books) do
		table.insert(top_5_books, top_books[i])
	end

	-- Weekly reading graph (last 7 days for sparkline)
	local week_graph = {}
	for i = 6, 0, -1 do
		local day = os.date("%Y-%m-%d", today - (i * 86400))
		table.insert(week_graph, month_sessions[day] or 0)
	end

	-- Collections
	local all_collections = collections.get_all() or {}
	local collection_stats = {}
	for _, coll in ipairs(all_collections) do
		table.insert(collection_stats, {
			name = coll.name,
			count = #(coll.books or {}),
		})
	end
	-- Sort by count descending
	table.sort(collection_stats, function(a, b)
		return a.count > b.count
	end)

	state.data = {
		total_books = total_books,
		completed = completed,
		reading = reading,
		to_read = to_read,
		total_time = total_time,
		week_time = week_time,
		month_time = month_time,
		daily_avg = daily_avg,
		overall_completion = overall_completion,
		current_streak = current_streak,
		longest_streak = longest_streak,
		top_books = top_5_books,
		week_graph = week_graph,
		collections = collection_stats,
	}

	-- Update cache
	cache.data = state.data
	cache.timestamp = now
end

-- Create sparkline from data
-- @param data: number[] - Array of values
-- @return sparkline: string - Unicode sparkline
function M.create_sparkline(data)
	if not data or #data == 0 then
		return string.rep("▁", 7)
	end

	-- Find min and max
	local min_val = math.huge
	local max_val = -math.huge
	for _, val in ipairs(data) do
		if val < min_val then min_val = val end
		if val > max_val then max_val = val end
	end

	-- Handle all zeros or single value
	if max_val == 0 or max_val == min_val then
		return string.rep("▁", #data)
	end

	-- Unicode sparkline characters
	local chars = {"▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
	local range = max_val - min_val

	local sparkline = ""
	for _, val in ipairs(data) do
		local normalized = (val - min_val) / range
		local index = math.floor(normalized * (#chars - 1)) + 1
		sparkline = sparkline .. chars[index]
	end

	return sparkline
end

-- Get default stats (when no books)
function M.get_default_stats()
	return {
		total_books = 0,
		completed = 0,
		reading = 0,
		to_read = 0,
		total_time = 0,
		week_time = 0,
		month_time = 0,
		daily_avg = 0,
		overall_completion = 0,
		current_streak = 0,
		longest_streak = 0,
		top_books = {},
		week_graph = {0, 0, 0, 0, 0, 0, 0},
		collections = {},
	}
end

-- Render dashboard
function M.render()
	if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
		return
	end

	-- Clear previous extmarks
	vim.api.nvim_buf_clear_namespace(state.buffer, state.ns_id, 0, -1)

	local lines = {}
	local line_paddings = {} -- Track padding for each line
	local win_width = vim.api.nvim_win_get_width(0)
	local win_height = vim.api.nvim_win_get_height(0)

	-- Title
	local title = "Ink.Nvim"
	local title_padding = math.floor((win_width - #title) / 2)
	table.insert(lines, title)
	table.insert(line_paddings, title_padding)

	-- Subtitle
	local subtitle = "Statistics"
	local subtitle_padding = math.floor((win_width - #subtitle) / 2)
	table.insert(lines, subtitle)
	table.insert(line_paddings, subtitle_padding)
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	-- Calculate box width
	local box_width = math.min(win_width - 4, 120)
	local box_padding = math.floor((win_width - box_width) / 2)

	-- Reading Statistics box
	M.render_reading_stats(lines, line_paddings, box_width, box_padding)
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	-- Time Statistics box (with sparkline)
	M.render_time_stats(lines, line_paddings, box_width, box_padding)
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	-- Progress box (with colors)
	M.render_progress(lines, line_paddings, box_width, box_padding)
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	-- Streak box
	M.render_streak(lines, line_paddings, box_width, box_padding)
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	-- Top Books box
	M.render_top_books(lines, line_paddings, box_width, box_padding)
	table.insert(lines, "")
	table.insert(line_paddings, 0)

	-- Collections box
	M.render_collections(lines, line_paddings, box_width, box_padding)

	-- Help
	table.insert(lines, "")
	table.insert(line_paddings, 0)
	local help = "s library    r refresh    q quit"
	local help_padding = math.floor((win_width - vim.fn.strwidth(help)) / 2)
	table.insert(lines, help)
	table.insert(line_paddings, help_padding)

	-- Calculate vertical centering
	local content_height = #lines
	local vertical_padding = math.max(0, math.floor((win_height - content_height) / 2))

	-- Add empty lines at the top for vertical centering
	if vertical_padding > 0 then
		for i = 1, vertical_padding do
			table.insert(lines, 1, "")
			table.insert(line_paddings, 1, 0)
		end
	end

	-- Set buffer content
	vim.api.nvim_buf_set_option(state.buffer, "modifiable", true)
	vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(state.buffer, "modifiable", false)

	-- Apply extmarks for horizontal centering
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

	-- Apply syntax highlighting
	M.apply_highlights(vertical_padding, lines, title, subtitle)
end

-- Apply syntax highlighting to dashboard
-- @param vertical_offset: number - Vertical padding for centering
-- @param lines_table: table - All buffer lines
-- @param title: string - Title text
-- @param subtitle: string - Subtitle text
function M.apply_highlights(vertical_offset, lines_table, title, subtitle)
	-- Title line (line 0 after vertical offset)
	local title_line = vertical_offset
	local title_text = lines_table[title_line + 1]

	-- Find where title starts in the line (after padding spaces)
	local title_start = title_text:find(title, 1, true)
	if title_start then
		vim.api.nvim_buf_set_extmark(state.buffer, state.ns_id, title_line, title_start - 1, {
			end_col = title_start - 1 + #title,
			hl_group = "InkTitle",
			priority = 200,
		})
	end

	-- Subtitle line (line 1 after vertical offset)
	local subtitle_line = vertical_offset + 1
	local subtitle_text = lines_table[subtitle_line + 1]

	-- Find where subtitle starts in the line (after padding spaces)
	local subtitle_start = subtitle_text:find(subtitle, 1, true)
	if subtitle_start then
		vim.api.nvim_buf_set_extmark(state.buffer, state.ns_id, subtitle_line, subtitle_start - 1, {
			end_col = subtitle_start - 1 + #subtitle,
			hl_group = "InkItalic",
			priority = 200,
		})
	end
end

-- Render reading statistics box
function M.render_reading_stats(lines, line_paddings, box_width, box_padding)
	-- Top border
	table.insert(lines, "┌" .. string.rep("─", box_width - 2) .. "┐")
	table.insert(line_paddings, box_padding)

	-- Header
	table.insert(lines, "│READING STATISTICS" .. string.rep(" ", box_width - 2 - 18) .. "│")
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Stats in 4 columns
	local col_width = math.floor((box_width - 2) / 4)
	local stats = {
		{ value = tostring(state.data.total_books), label = "Total Books" },
		{ value = tostring(state.data.completed), label = "Completed" },
		{ value = tostring(state.data.reading), label = "In Progress" },
		{ value = tostring(state.data.to_read), label = "Not Started" },
	}

	-- Values line
	local values_line = "│"
	local total_width = 0
	for i, stat in ipairs(stats) do
		local current_col_width = col_width
		-- Last column gets remaining space to handle rounding
		if i == #stats then
			current_col_width = (box_width - 2) - total_width
		end
		local padding = math.floor((current_col_width - vim.fn.strwidth(stat.value)) / 2)
		values_line = values_line .. string.rep(" ", padding) .. stat.value .. string.rep(" ", current_col_width - padding - vim.fn.strwidth(stat.value))
		total_width = total_width + current_col_width
	end
	table.insert(lines, values_line .. "│")
	table.insert(line_paddings, box_padding)

	-- Labels line
	local labels_line = "│"
	total_width = 0
	for i, stat in ipairs(stats) do
		local current_col_width = col_width
		-- Last column gets remaining space to handle rounding
		if i == #stats then
			current_col_width = (box_width - 2) - total_width
		end
		local padding = math.floor((current_col_width - vim.fn.strwidth(stat.label)) / 2)
		labels_line = labels_line .. string.rep(" ", padding) .. stat.label .. string.rep(" ", current_col_width - padding - vim.fn.strwidth(stat.label))
		total_width = total_width + current_col_width
	end
	table.insert(lines, labels_line .. "│")
	table.insert(line_paddings, box_padding)

	-- Bottom border
	table.insert(lines, "└" .. string.rep("─", box_width - 2) .. "┘")
	table.insert(line_paddings, box_padding)
end

-- Render time statistics box
function M.render_time_stats(lines, line_paddings, box_width, box_padding)
	local text_utils = require("ink.dashboard.utils.text")

	-- Top border
	table.insert(lines, "┌" .. string.rep("─", box_width - 2) .. "┐")
	table.insert(line_paddings, box_padding)

	-- Header
	table.insert(lines, "│TIME STATISTICS" .. string.rep(" ", box_width - 2 - 15) .. "│")
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Stats in 4 columns
	local col_width = math.floor((box_width - 2) / 4)
	local stats = {
		{ value = text_utils.format_time(state.data.total_time), label = "Total Reading Time" },
		{ value = text_utils.format_time(state.data.week_time), label = "This Week" },
		{ value = text_utils.format_time(state.data.month_time), label = "This Month" },
		{ value = text_utils.format_time(state.data.daily_avg), label = "Daily Average" },
	}

	-- Values line
	local values_line = "│"
	local total_width = 0
	for i, stat in ipairs(stats) do
		local current_col_width = col_width
		-- Last column gets remaining space to handle rounding
		if i == #stats then
			current_col_width = (box_width - 2) - total_width
		end
		local padding = math.floor((current_col_width - vim.fn.strwidth(stat.value)) / 2)
		values_line = values_line .. string.rep(" ", padding) .. stat.value .. string.rep(" ", current_col_width - padding - vim.fn.strwidth(stat.value))
		total_width = total_width + current_col_width
	end
	table.insert(lines, values_line .. "│")
	table.insert(line_paddings, box_padding)

	-- Labels line
	local labels_line = "│"
	total_width = 0
	for i, stat in ipairs(stats) do
		local current_col_width = col_width
		-- Last column gets remaining space to handle rounding
		if i == #stats then
			current_col_width = (box_width - 2) - total_width
		end
		local padding = math.floor((current_col_width - vim.fn.strwidth(stat.label)) / 2)
		labels_line = labels_line .. string.rep(" ", padding) .. stat.label .. string.rep(" ", current_col_width - padding - vim.fn.strwidth(stat.label))
		total_width = total_width + current_col_width
	end
	table.insert(lines, labels_line .. "│")
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Weekly reading sparkline
	local sparkline = M.create_sparkline(state.data.week_graph)
	local sparkline_label = "Last 7 days: " .. sparkline
	local sparkline_padding = math.floor((box_width - 2 - vim.fn.strwidth(sparkline_label)) / 2)
	local sparkline_line = "│" .. string.rep(" ", sparkline_padding) .. sparkline_label .. string.rep(" ", box_width - 2 - sparkline_padding - vim.fn.strwidth(sparkline_label)) .. "│"
	table.insert(lines, sparkline_line)
	table.insert(line_paddings, box_padding)

	-- Bottom border
	table.insert(lines, "└" .. string.rep("─", box_width - 2) .. "┘")
	table.insert(line_paddings, box_padding)
end

-- Render progress box
function M.render_progress(lines, line_paddings, box_width, box_padding)
	-- Top border
	table.insert(lines, "┌" .. string.rep("─", box_width - 2) .. "┐")
	table.insert(line_paddings, box_padding)

	-- Header
	table.insert(lines, "│PROGRESS" .. string.rep(" ", box_width - 2 - 8) .. "│")
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Overall Completion
	local completion_text = "Overall Completion"
	local completion_line = "│" .. completion_text .. string.rep(" ", box_width - 2 - vim.fn.strwidth(completion_text)) .. "│"
	table.insert(lines, completion_line)
	table.insert(line_paddings, box_padding)

	-- Progress bar
	local percentage_text = state.data.overall_completion .. "%"
	local bar_width = box_width - 2 - 4 - vim.fn.strwidth(percentage_text) -- borders, padding, percentage
	local filled = math.floor((state.data.overall_completion / 100) * bar_width)
	local empty = bar_width - filled
	local bar = "│  " .. string.rep("█", filled) .. string.rep("░", empty) .. "  " .. percentage_text .. "│"
	table.insert(lines, bar)
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Pages Read placeholder
	local pages_text = "Pages Read"
	local pages_value = "N/A"
	local pages_line = "│" .. pages_text .. string.rep(" ", box_width - 2 - vim.fn.strwidth(pages_text) - vim.fn.strwidth(pages_value)) .. pages_value .. "│"
	table.insert(lines, pages_line)
	table.insert(line_paddings, box_padding)

	-- Bottom border
	table.insert(lines, "└" .. string.rep("─", box_width - 2) .. "┘")
	table.insert(line_paddings, box_padding)
end

-- Render streak box
function M.render_streak(lines, line_paddings, box_width, box_padding)
	-- Top border
	table.insert(lines, "┌" .. string.rep("─", box_width - 2) .. "┐")
	table.insert(line_paddings, box_padding)

	-- Header
	table.insert(lines, "│READING STREAK" .. string.rep(" ", box_width - 2 - 14) .. "│")
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Stats in 2 columns
	local col_width = math.floor((box_width - 2) / 2)
	local stats = {
		{ value = tostring(state.data.current_streak) .. " days", label = "Current Streak 🔥" },
		{ value = tostring(state.data.longest_streak) .. " days", label = "Longest Streak 🏆" },
	}

	-- Values line
	local values_line = "│"
	local total_width = 0
	for i, stat in ipairs(stats) do
		local current_col_width = col_width
		-- Last column gets remaining space to handle rounding
		if i == #stats then
			current_col_width = (box_width - 2) - total_width
		end
		local padding = math.floor((current_col_width - vim.fn.strwidth(stat.value)) / 2)
		values_line = values_line .. string.rep(" ", padding) .. stat.value .. string.rep(" ", current_col_width - padding - vim.fn.strwidth(stat.value))
		total_width = total_width + current_col_width
	end
	table.insert(lines, values_line .. "│")
	table.insert(line_paddings, box_padding)

	-- Labels line
	local labels_line = "│"
	total_width = 0
	for i, stat in ipairs(stats) do
		local current_col_width = col_width
		-- Last column gets remaining space to handle rounding
		if i == #stats then
			current_col_width = (box_width - 2) - total_width
		end
		local padding = math.floor((current_col_width - vim.fn.strwidth(stat.label)) / 2)
		labels_line = labels_line .. string.rep(" ", padding) .. stat.label .. string.rep(" ", current_col_width - padding - vim.fn.strwidth(stat.label))
		total_width = total_width + current_col_width
	end
	table.insert(lines, labels_line .. "│")
	table.insert(line_paddings, box_padding)

	-- Bottom border
	table.insert(lines, "└" .. string.rep("─", box_width - 2) .. "┘")
	table.insert(line_paddings, box_padding)
end

-- Render top books box
function M.render_top_books(lines, line_paddings, box_width, box_padding)
	local text_utils = require("ink.dashboard.utils.text")

	-- Top border
	table.insert(lines, "┌" .. string.rep("─", box_width - 2) .. "┐")
	table.insert(line_paddings, box_padding)

	-- Header
	table.insert(lines, "│TOP BOOKS" .. string.rep(" ", box_width - 2 - 9) .. "│")
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Top books (limit to 5)
	local max_books = 5
	for i = 1, math.min(max_books, #state.data.top_books) do
		local book = state.data.top_books[i]
		local rank = tostring(i) .. ". "
		local time_text = text_utils.format_time(book.time)
		local available_width = box_width - 2 - vim.fn.strwidth(rank) - vim.fn.strwidth(time_text) - 3

		-- Format title and author
		local display_text = book.title
		if book.author and book.author ~= "" then
			display_text = display_text .. " — " .. book.author
		end

		-- Truncate if too long
		if vim.fn.strwidth(display_text) > available_width then
			display_text = vim.fn.strcharpart(display_text, 0, available_width - 3) .. "..."
		end

		local spacing = box_width - 2 - vim.fn.strwidth(rank) - vim.fn.strwidth(display_text) - vim.fn.strwidth(time_text) - 2
		local line = "│ " .. rank .. display_text .. string.rep(" ", spacing) .. time_text .. " │"
		table.insert(lines, line)
		table.insert(line_paddings, box_padding)
	end

	-- Fill empty lines if less than max
	for i = #state.data.top_books + 1, max_books do
		table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
		table.insert(line_paddings, box_padding)
	end

	-- Bottom border
	table.insert(lines, "└" .. string.rep("─", box_width - 2) .. "┘")
	table.insert(line_paddings, box_padding)
end

-- Render collections box
function M.render_collections(lines, line_paddings, box_width, box_padding)
	-- Top border
	table.insert(lines, "┌" .. string.rep("─", box_width - 2) .. "┐")
	table.insert(line_paddings, box_padding)

	-- Header
	table.insert(lines, "│COLLECTIONS" .. string.rep(" ", box_width - 2 - 11) .. "│")
	table.insert(line_paddings, box_padding)

	-- Empty line
	table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)

	-- Collections (limit to 6)
	local max_collections = 6
	for i = 1, math.min(max_collections, #state.data.collections) do
		local coll = state.data.collections[i]
		local count_text = coll.count .. " books"
		local name_width = box_width - 2 - vim.fn.strwidth(count_text) - 4
		local name = coll.name
		if vim.fn.strwidth(name) > name_width then
			name = name:sub(1, name_width - 3) .. "..."
		end
		local spacing = box_width - 2 - vim.fn.strwidth(name) - vim.fn.strwidth(count_text) - 2
		local line = "│ " .. name .. string.rep(" ", spacing) .. count_text .. " │"
		table.insert(lines, line)
		table.insert(line_paddings, box_padding)
	end

	-- Fill empty lines if less than max
	for i = #state.data.collections + 1, max_collections do
		table.insert(lines, "│" .. string.rep(" ", box_width - 2) .. "│")
	table.insert(line_paddings, box_padding)
	end

	-- Bottom border
	table.insert(lines, "└" .. string.rep("─", box_width - 2) .. "┘")
	table.insert(line_paddings, box_padding)
end

-- Setup keymaps
function M.setup_keymaps(buf)
	local opts = { noremap = true, silent = true, buffer = buf }

	-- Toggle back to library
	vim.keymap.set("n", "s", function()
		local library_dashboard = require("ink.dashboard.library_dashboard")
		-- Don't open in new tab when toggling between dashboards
		library_dashboard.show({ in_new_tab = false })
	end, opts)

	-- Refresh
	vim.keymap.set("n", "r", function()
		M.invalidate_cache()
		M.load_data(true)
		M.render()
		vim.notify("Dashboard Reloaded", vim.log.levels.INFO)
	end, opts)

	-- Quit
	vim.keymap.set("n", "q", function()
		vim.api.nvim_buf_delete(buf, { force = true })
	end, opts)
end

-- Setup autocmds
function M.setup_autocmds(buf)
	local group = vim.api.nvim_create_augroup("InkStatsDashboard", { clear = false })

	vim.api.nvim_create_autocmd("BufDelete", {
		group = group,
		buffer = buf,
		callback = function()
			state.buffer = nil
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

return M
