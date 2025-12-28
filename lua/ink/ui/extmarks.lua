local context = require("ink.ui.context")
local user_highlights = require("ink.user_highlights")
local bookmarks_data = require("ink.bookmarks")
local util = require("ink.ui.util")

local M = {}

function M.apply_syntax_highlights(buf, highlights, ns_id, padding)
    padding = padding or 0
    if not highlights or #highlights == 0 then return end

    -- Get all lines once (batch read)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local all_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    -- Prepare extmarks in batch
    local extmarks_to_apply = {}

    for _, hl in ipairs(highlights) do
        local line_idx = hl[1] - 1
        local start_col = hl[2]
        local end_col = hl[3]

        if line_idx >= 0 and line_idx < line_count then
            local line_length = #all_lines[line_idx + 1]
            start_col = math.min(start_col, line_length)
            end_col = math.min(end_col, line_length)

            if start_col < end_col then
                table.insert(extmarks_to_apply, {
                    line_idx = line_idx,
                    col = start_col,
                    opts = {
                        end_col = end_col,
                        hl_group = hl[4],
                        priority = 1000,
                        hl_mode = "combine"
                    }
                })
            end
        end
    end

    -- Apply all extmarks (still sequential but with pre-validated data)
    for _, mark in ipairs(extmarks_to_apply) do
        vim.api.nvim_buf_set_extmark(buf, ns_id, mark.line_idx, mark.col, mark.opts)
    end
end

function M.apply_user_highlights(buf, chapter_highlights, ns_id, lines)
    for _, hl in ipairs(chapter_highlights) do
        local start_line, start_col, end_line, end_col = util.find_text_position(
            lines, hl.text, hl.context_before, hl.context_after
        )
        if start_line then
            hl._start_line = start_line
            hl._start_col = start_col
            hl._end_line = end_line
            hl._end_col = end_col
            local hl_group = "InkUserHighlight_" .. hl.color
            vim.api.nvim_buf_set_extmark(buf, ns_id, start_line - 1, start_col, {
                end_line = end_line - 1, end_col = end_col, hl_group = hl_group, priority = 2000
            })
        end
    end
end

function M.apply_note_indicators(buf, chapter_highlights, note_display_mode, padding, max_width, ns_id)
    if note_display_mode == "off" then return end

    local notes_by_line = {}
    for _, hl in ipairs(chapter_highlights) do
        if hl.note and hl.note ~= "" and hl._end_line then
            local end_line = hl._end_line
            if not notes_by_line[end_line] then notes_by_line[end_line] = {} end
            table.insert(notes_by_line[end_line], { hl = hl, end_col = hl._end_col })
        end
    end

    for line, notes in pairs(notes_by_line) do
        table.sort(notes, function(a, b) return a.end_col < b.end_col end)
    end

    for line, notes in pairs(notes_by_line) do
        local line_idx = line - 1
        local line_count = vim.api.nvim_buf_line_count(buf)
        if line_idx >= 0 and line_idx < line_count then
            if note_display_mode == "indicator" then
                for _, note_info in ipairs(notes) do
                    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, note_info.end_col, {
                        virt_text = { { "●", "InkNoteIndicator" } }, virt_text_pos = "inline", priority = 3000
                    })
                end
            elseif note_display_mode == "expanded" then
                for _, note_info in ipairs(notes) do
                    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, note_info.end_col, {
                        virt_text = { { "●", "InkNoteIndicator" } }, virt_text_pos = "inline", priority = 3000
                    })
                end
                local virt_lines = {}
                for i, note_info in ipairs(notes) do
                    local bars = string.rep("│", i)
                    local note_text = note_info.hl.note:gsub("\n", " ")
                    local max_note_len = max_width - #bars - 2
                    if #note_text > max_note_len then note_text = note_text:sub(1, max_note_len - 3) .. "..." end
                    local pad = string.rep(" ", padding)
                    table.insert(virt_lines, { { pad .. bars .. " " .. note_text, "InkNoteText" } })
                end
                if #virt_lines > 0 then
                    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
                        virt_lines = virt_lines, virt_lines_above = false, priority = 3000
                    })
                end
            end
        end
    end
end

function M.apply_bookmarks(buf, chapter_bookmarks, padding, bookmark_icon, ns_id, lines, max_width)
    -- Group bookmarks by line
    local bookmarks_by_line = {}

    for _, bm in ipairs(chapter_bookmarks) do
        local line_idx = nil

        -- New bookmarks use text-matching for position independence
        if bm.paragraph_text then
            local start_line = util.find_text_position(
                lines,
                bm.paragraph_text,
                bm.context_before,
                bm.context_after
            )
            if start_line then
                line_idx = start_line - 1
                bm._line_idx = start_line  -- Cache for navigation
            end
        -- Legacy bookmarks use line-based positioning
        elseif bm.paragraph_line then
            line_idx = bm.paragraph_line - 1
            bm._line_idx = bm.paragraph_line
        end

        if line_idx and line_idx >= 0 and line_idx < #lines then
            if not bookmarks_by_line[line_idx] then
                bookmarks_by_line[line_idx] = {}
            end
            table.insert(bookmarks_by_line[line_idx], bm)
        end
    end

    -- Render bookmarks (multiple per line if needed)
    for line_idx, bms in pairs(bookmarks_by_line) do
        local pad = string.rep(" ", padding)

        -- If single bookmark, use simple format
        if #bms == 1 then
            vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
                virt_lines = { { { pad .. bookmark_icon .. " " .. bms[1].name, "InkBookmark" } } },
                virt_lines_above = true,
                priority = 4000,
            })
        else
            -- Multiple bookmarks: join with " | " separator
            max_width = max_width or 120
            local available_width = max_width - 10  -- Reserve some margin
            local separator = " | "
            local prefix = bookmark_icon .. " "

            -- Calculate how much space each bookmark can use
            local separator_total = vim.fn.strwidth(separator) * (#bms - 1)
            local prefix_width = vim.fn.strwidth(prefix)
            local space_for_names = available_width - prefix_width - separator_total
            local max_name_width = math.floor(space_for_names / #bms)

            -- Ensure minimum width of 15 chars per bookmark
            if max_name_width < 15 then
                max_name_width = 15
            end

            -- Build bookmark text with truncation
            local bookmark_text = prefix
            for i, bm in ipairs(bms) do
                local name = bm.name
                local name_width = vim.fn.strwidth(name)

                -- Truncate if needed
                if name_width > max_name_width then
                    -- Truncate to fit with "..." (3 chars)
                    local target_width = max_name_width - 3
                    local truncated = ""
                    local current_width = 0

                    for j = 1, vim.fn.strchars(name) do
                        local char = vim.fn.strcharpart(name, j - 1, 1)
                        local char_width = vim.fn.strwidth(char)
                        if current_width + char_width > target_width then
                            break
                        end
                        truncated = truncated .. char
                        current_width = current_width + char_width
                    end

                    name = truncated .. "..."
                end

                bookmark_text = bookmark_text .. name
                if i < #bms then
                    bookmark_text = bookmark_text .. separator
                end
            end

            vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
                virt_lines = { { { pad .. bookmark_text, "InkBookmark" } } },
                virt_lines_above = true,
                priority = 4000,
            })
        end
    end
end

-- Helper: Resolve note conflicts by separating left/right margins
local function resolve_note_conflicts(notes)
    -- Separate notes by side (left/right)
    local left_notes = {}
    local right_notes = {}

    for _, note_info in ipairs(notes) do
        if note_info.is_left then
            table.insert(left_notes, note_info)
        else
            table.insert(right_notes, note_info)
        end
    end

    -- Sort each side by start line
    table.sort(left_notes, function(a, b) return a.start_line < b.start_line end)
    table.sort(right_notes, function(a, b) return a.start_line < b.start_line end)

    -- Resolve conflicts on left side
    local last_left_end = -1
    for _, note_info in ipairs(left_notes) do
        local display_line = note_info.start_line

        -- Add 1 line gap between stacked notes
        if display_line <= last_left_end then
            display_line = last_left_end + 2
        end

        note_info.display_line = display_line
        last_left_end = display_line + note_info.lines_count - 1
    end

    -- Resolve conflicts on right side
    local last_right_end = -1
    for _, note_info in ipairs(right_notes) do
        local display_line = note_info.start_line

        -- Add 1 line gap between stacked notes
        if display_line <= last_right_end then
            display_line = last_right_end + 2
        end

        note_info.display_line = display_line
        last_right_end = display_line + note_info.lines_count - 1
    end

    -- Merge back (order doesn't matter)
    local adjusted = {}
    for _, note in ipairs(left_notes) do
        table.insert(adjusted, note)
    end
    for _, note in ipairs(right_notes) do
        table.insert(adjusted, note)
    end

    return adjusted
end

-- Helper: Apply a single margin note with numeric indicator
local function apply_single_margin_note(buf, note_info, margin_width, ns_id)
    local hl = note_info.hl
    local is_left = note_info.is_left
    local note_column = note_info.note_column
    local wrapped_lines = note_info.wrapped_lines
    local display_line = note_info.display_line
    local note_number = note_info.note_number

    -- Numeric indicator on the highlight line (at end of highlight)
    local indicator = "[^" .. note_number .. "]"
    vim.api.nvim_buf_set_extmark(buf, ns_id, hl._end_line - 1, hl._end_col, {
        virt_text = {{indicator, "InkNoteIndicator"}},
        virt_text_pos = "inline",
        priority = 3000
    })

    -- Note text lines in margin
    for i, line_text in ipairs(wrapped_lines) do
        -- First line uses display_line (adjusted for conflicts), continuation lines flow below
        local line_idx = display_line - 1 + (i - 1)

        -- Add note number prefix on first line, indent continuation lines
        local prefixed_text
        if i == 1 then
            prefixed_text = indicator .. " " .. line_text
        else
            -- Indent continuation lines to align with text after number
            prefixed_text = "    " .. line_text
        end

        -- Format text based on side
        local virt_text
        local text_column = note_column
        local line_width = vim.fn.strwidth(prefixed_text)

        if is_left then
            -- Left: align to the right (close to content)
            local padding_needed = margin_width - line_width
            if padding_needed > 0 then
                local pad = string.rep(" ", padding_needed)
                virt_text = {{pad .. prefixed_text, "InkNoteText"}}
            else
                virt_text = {{prefixed_text, "InkNoteText"}}
            end
        else
            -- Right: left-aligned (natural for reading)
            virt_text = {{prefixed_text, "InkNoteText"}}
        end

        vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
            virt_text = virt_text,
            virt_text_win_col = text_column,
            priority = 2900
        })
    end
end

-- Main function: Apply margin notes using window columns
function M.apply_margin_notes(buf, highlights, padding, max_width, win_width, ns_id, notify_on_fail)
    -- Require Neovim 0.10+
    if vim.fn.has('nvim-0.10') == 0 then
        return false  -- fallback to expanded
    end

    local margin_width = context.config.margin_note_width or 35

    -- Calculate spacing proportional to available padding
    -- More padding (smaller max_width) = more spacing between text and notes
    -- Formula: 4 chars base + (padding / 40) adaptive spacing
    -- Examples (1366px screen):
    --   max_width=120, padding=623 → spacing = 4 + 15 = 19 chars
    --   max_width=100, padding=633 → spacing = 4 + 15 = 19 chars
    --   max_width=80,  padding=643 → spacing = 4 + 16 = 20 chars
    -- Limits: min 4 chars (tight), max 20 chars (comfortable)
    local spacing = math.max(4, math.min(20, 4 + math.floor(padding / 40)))

    -- Check if there's enough margin space for notes + spacing
    -- Need at least: margin_width + spacing
    local min_space_required = margin_width + spacing
    if padding < min_space_required then
        -- Only notify if user explicitly toggled to margin mode
        if notify_on_fail then
            vim.notify("Not enough space. Fallback to expanded mode", vim.log.levels.INFO)
        end
        return false  -- fallback to expanded
    end

    local notes_with_positions = {}

    -- Phase 1: Collect notes and calculate positions
    for _, hl in ipairs(highlights) do
        if hl.note and hl.note ~= "" and hl._start_line then
            local highlight_col = hl._start_col or 0
            local line_center = max_width / 2
            local is_left = highlight_col < line_center

            -- Calculate note column with proportional spacing
            local note_column
            if is_left then
                -- Left margin: padding - margin_width - spacing
                -- Ensure note doesn't go off-screen (column >= 0)
                note_column = math.max(0, padding - margin_width - spacing)
            else
                -- Right margin: padding + max_width + spacing
                -- Ensure note doesn't exceed window width
                local max_right_col = win_width - margin_width
                note_column = math.min(padding + max_width + spacing, max_right_col)
            end

            -- Word wrap the note (reserve 4 chars for "(N) " prefix on first line)
            local text_width = margin_width - 4
            local wrapped_lines = util.wrap_note_text(hl.note, text_width)

            -- Limit to 10 lines max
            local MAX_NOTE_LINES = 10
            if #wrapped_lines > MAX_NOTE_LINES then
                wrapped_lines = vim.list_slice(wrapped_lines, 1, MAX_NOTE_LINES)
                -- Add "..." on a separate line to avoid text overlap
                table.insert(wrapped_lines, "...")
            end

            table.insert(notes_with_positions, {
                hl = hl,
                is_left = is_left,
                note_column = note_column,
                wrapped_lines = wrapped_lines,
                start_line = hl._start_line,
                lines_count = #wrapped_lines
            })
        end
    end

    -- Phase 2: Sort by line order and assign sequential numbers
    table.sort(notes_with_positions, function(a, b)
        if a.start_line == b.start_line then
            -- Same line: left side first, then by column
            if a.is_left ~= b.is_left then
                return a.is_left
            end
            return (a.hl._start_col or 0) < (b.hl._start_col or 0)
        end
        return a.start_line < b.start_line
    end)

    -- Assign sequential note numbers
    for i, note_info in ipairs(notes_with_positions) do
        note_info.note_number = i
    end

    -- Phase 3: Conflict Detection & Adjustment
    notes_with_positions = resolve_note_conflicts(notes_with_positions)

    -- Phase 4: Apply extmarks
    for _, note_info in ipairs(notes_with_positions) do
        apply_single_margin_note(buf, note_info, margin_width, ns_id)
    end

    return true
end

return M
