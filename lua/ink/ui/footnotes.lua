local context = require("ink.ui.context")

local M = {}

function M.show_footnote_preview(anchor_id, ctx)
    ctx = ctx or context.current()
    if not ctx then return false end
    local anchor_line = ctx.anchors[anchor_id]
    if not anchor_line then
        vim.notify("Footnote not found: " .. anchor_id, vim.log.levels.WARN)
        return false
    end

    local total_lines = vim.api.nvim_buf_line_count(ctx.content_buf)
    local max_preview_lines = 15
    local end_line = math.min(anchor_line + max_preview_lines - 1, total_lines)
    local lines = vim.api.nvim_buf_get_lines(ctx.content_buf, anchor_line - 1, end_line, false)

    while #lines > 0 and lines[1]:match("^%s*$") do table.remove(lines, 1) end
    while #lines > 0 and lines[#lines]:match("^%s*$") do table.remove(lines) end

    local footnote_lines = {}
    local found_content = false
    for _, line in ipairs(lines) do
        if not found_content and line:match("^%s*$") then goto continue end
        found_content = true
        if found_content and line:match("^%s*$") then break end
        table.insert(footnote_lines, line:match("^%s*(.-)%s*$"))
        ::continue::
    end

    if #footnote_lines == 0 then
        vim.notify("Empty footnote", vim.log.levels.WARN)
        return false
    end

    local max_width = 60
    local width = 0
    for _, line in ipairs(footnote_lines) do width = math.max(width, #line) end
    width = math.min(width + 2, max_width)

    local wrapped_lines = {}
    for _, line in ipairs(footnote_lines) do
        if #line > width - 2 then
            local current = ""
            for word in line:gmatch("%S+") do
                if #current + #word + 1 > width - 2 then
                    if #current > 0 then table.insert(wrapped_lines, current) end
                    current = word
                else
                    if current == "" then current = word else current = current .. " " .. word end
                end
            end
            if #current > 0 then table.insert(wrapped_lines, current) end
        else
            table.insert(wrapped_lines, line)
        end
    end

    local height = math.min(#wrapped_lines, 10)
    local float_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, wrapped_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })

    local float_win = vim.api.nvim_open_win(float_buf, false, {
        relative = "cursor",
        row = 1,
        col = 0,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Footnote ",
        title_pos = "center",
    })
    vim.api.nvim_set_option_value("winblend", 0, { win = float_win })
    vim.api.nvim_set_option_value("winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = float_win })

    local function close_float()
        if vim.api.nvim_win_is_valid(float_win) then vim.api.nvim_win_close(float_win, true) end
        pcall(vim.keymap.del, "n", "q", { buffer = ctx.content_buf })
        pcall(vim.keymap.del, "n", "<Esc>", { buffer = ctx.content_buf })
    end

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufLeave", "InsertEnter" }, {
        callback = function()
            close_float(); return true
        end, buffer = ctx.content_buf,
    })
    vim.keymap.set("n", "q", close_float, { buffer = ctx.content_buf })
    vim.keymap.set("n", "<Esc>", close_float, { buffer = ctx.content_buf })
    return true
end

return M
