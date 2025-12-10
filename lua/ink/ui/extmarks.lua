local context = require("ink.ui.context")
local user_highlights = require("ink.user_highlights")
local bookmarks_data = require("ink.bookmarks")
local util = require("ink.ui.util")

local M = {}

function M.apply_syntax_highlights(buf, highlights, ns_id, padding)
    padding = padding or 0
    for _, hl in ipairs(highlights or {}) do
        local line_idx = hl[1] - 1
        local start_col = hl[2]
        local end_col = hl[3]
        if line_idx >= 0 then
            local line_count = vim.api.nvim_buf_line_count(buf)
            if line_idx < line_count then
                local line_length = #vim.api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)[1]
                start_col = math.min(start_col, line_length)
                end_col = math.min(end_col, line_length)
                if start_col < end_col then
                    vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, start_col, {
                        end_col = end_col, hl_group = hl[4], priority = 1000, hl_mode = "combine"
                    })
                end
            end
        end
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

function M.apply_bookmarks(buf, chapter_bookmarks, padding, bookmark_icon, ns_id, lines)
    for _, bm in ipairs(chapter_bookmarks) do
        local line_idx = bm.paragraph_line - 1
        if line_idx >= 0 and line_idx < #lines then
            local pad = string.rep(" ", padding)
            vim.api.nvim_buf_set_extmark(buf, ns_id, line_idx, 0, {
                virt_lines = { { { pad .. bookmark_icon .. " " .. bm.name, "InkBookmark" } } },
                virt_lines_above = true,
                priority = 4000,
            })
        end
    end
end

return M
