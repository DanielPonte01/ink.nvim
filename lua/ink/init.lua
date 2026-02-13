local epub = require("ink.epub")
local markdown = require("ink.markdown")
local web = require("ink.web")
local ui = require("ink.ui")

local M = {}

local default_config = {
    -- Display settings
    focused_mode = true,           -- Hide distractions (statusline, etc.) when reading
    image_open = true,             -- Allow opening images in external viewer
    image_viewer = "nsxiv",      -- Image viewer: "default", "feh", "sxiv", "imv", "eog", "gwenview", etc.
    justify_text = false,          -- Enable text justification (adds spaces between words, affects copying)
    max_width = 120,               -- Maximum text width in columns
    width_step = 10,               -- Width change amount per keypress (+/-)
    adaptive_width = true,         -- Auto-adjust width based on window size
    adaptive_width_margin = 0.8,   -- Use 80% of window width (0.1-1.0, maintains margins on sides)

    -- Navigation and interaction keymaps
    keymaps = {
        next_chapter = "]c",
        prev_chapter = "[c",
        toggle_toc = "<leader>t",
        toggle_floating_toc = "<leader>T", -- Experimental floating TOC
        activate = "<CR>",                  -- Preview/open footnote, link, image, or TOC item
        jump_to_link = "g<CR>",             -- Jump directly to link target
        search_toc = "<leader>pit",
        search_content = "<leader>pif",
        search_mode_toggle = "<C-f>",       -- Switch between TOC and content search in Telescope
        width_increase = "<leader>+",
        width_decrease = "<leader>-",
        width_reset = "<leader>=",          -- Reset to adaptive width
        toggle_justify = "<leader>jt",
        library = "<leader>eL",
        last_book = "<leader>el",
        dashboard = "<leader>ed",
        related_resources = "<leader>er",   -- List related books
    },
    -- Highlight colors (add custom colors: purple, orange, pink, etc.)
    highlight_colors = {
        yellow = { bg = "#E8C89F", fg = "#000000" },
        green = { bg = "#8BB894", fg = "#000000" },
        red = { bg = "#D97B73", fg = "#000000" },
        blue = { bg = "#7BA3D0", fg = "#000000" },
        none = { bg = "NONE", fg = "NONE" },
    },

    -- Highlight keymaps (in visual mode)
    highlight_keymaps = {
        yellow = "<leader>hy",
        green = "<leader>hg",
        red = "<leader>hr",
        blue = "<leader>hb",
        remove = "<leader>hd",
    },

    -- Change highlight color (preserves notes)
    highlight_change_color_keymaps = {
        yellow = "<leader>hcy",
        green = "<leader>hcg",
        red = "<leader>hcr",
        blue = "<leader>hcb",
    },

    -- Notes keymaps
    note_keymaps = {
        add = "<leader>na",           -- Add/edit note on highlight
        remove = "<leader>nd",
        toggle_display = "<leader>nt", -- Cycle: off → indicator → margin → expanded
    },
    note_display_mode = "margin",      -- Default display mode: "off" | "indicator" | "margin" | "expanded"
    margin_note_width = 35,            -- Max width of margin notes (chars)
    margin_min_space = 30,             -- Min margin space required for margin mode (chars)
    notes_list_keymaps = {
        list_all = "<leader>nla",      -- List notes from all books
        list_book = "<leader>nlb",
    },

    -- Bookmarks keymaps
    bookmark_keymaps = {
        add = "<leader>ba",
        edit = "<leader>be",
        remove = "<leader>bd",
        next = "<leader>bn",           -- Navigate across chapters
        prev = "<leader>bp",
        list_all = "<leader>bl",       -- Global bookmarks list
        list_book = "<leader>bb",      -- Current book bookmarks
    },
    bookmark_icon = "📑",

    -- Export keymaps
    export_keymaps = {
        current_book = "<leader>ex",
    },
    export_defaults = {
        format = "markdown",       -- "markdown" | "json"
        include_bookmarks = false, -- Include bookmarks in export
        include_context = false,   -- Include surrounding text for highlights
        include_glossary = false,  -- Include glossary terms and relationships
        export_dir = "~/Documents",
    },

    -- Typography settings
    typography = {
        line_spacing = 1,      -- Lines between text lines (1 = normal, 2 = double space)
        paragraph_spacing = 1, -- Lines between paragraphs
        indent_size = 4,       -- Indent for blockquotes, code blocks, definitions
        list_indent = 2,       -- Indent for nested lists
    },
    typography_keymaps = {
        line_spacing_increase = "<leader>l+",
        line_spacing_decrease = "<leader>l-",
        line_spacing_reset = "<leader>l=",
        paragraph_spacing_increase = "<leader>p+",
        paragraph_spacing_decrease = "<leader>p-",
        paragraph_spacing_reset = "<leader>p=",
    },

    -- Reading session tracking
    tracking = {
        enabled = true,           -- Track reading time and sessions
        auto_save_interval = 300, -- Save interval in seconds (5 min)
        cleanup_after_days = 365, -- Clean old sessions (0 = never)
        grace_period = 1,         -- Days of grace for streak continuation
    },

    -- Glossary term types (customize icons and colors)
    glossary_types = {
        character = { icon = "👤", color = "InkGlossaryCharacter" },
        place = { icon = "📍", color = "InkGlossaryPlace" },
        concept = { icon = "💡", color = "InkGlossaryConcept" },
        organization = { icon = "🏛️", color = "InkGlossaryOrg" },
        object = { icon = "⚔️", color = "InkGlossaryObject" },
        event = { icon = "⚡", color = "InkGlossaryEvent" },
        foreign_word = { icon = "🌐", color = "InkGlossaryForeign" },
        other = { icon = "📝", color = "InkGlossary" }
    },
    glossary_visible = true, -- Show glossary terms underlined in text
    glossary_keymaps = {
        add = "<leader>ga",
        edit = "<leader>ge",
        remove = "<leader>gd",
        preview = "<leader>gp",        -- Show definition in floating window
        browser = "<leader>gl",        -- Browse all entries with Telescope
        show_related = "<leader>gg",   -- Show related terms (relationships)
        show_graph = "<leader>gG",     -- Visualize term relationships (ASCII/HTML)
        toggle_display = "<leader>gt", -- Toggle term underlining on/off
    },

    -- TOC configuration
    force_content_toc = false, -- Build TOC from content headings instead of EPUB metadata

    -- Padnotes configuration (chapter-specific markdown notes)
    padnotes = {
        enabled = true,
        path = "default",         -- "default" or custom with {slug}, {author}, {title} placeholders
        auto_save_interval = 120, -- Auto-save interval in seconds
        template = "default",     -- Custom template (future feature)
        position = "right",       -- "right" | "left" | "top" | "bottom"
        size = 0.5,               -- < 1: percentage (0.5 = 50%), >= 1: absolute columns/lines
    },
    padnotes_keymaps = {
        toggle = "<leader>pa",   -- Smart toggle: create/open/close/switch chapters
        open = "<leader>po",
        close = "<leader>pc",
        list_all = "<leader>pl", -- Browse all padnotes with Telescope
    },

    -- Related resources (link books together)
    related_resources = {
        position = "right", -- Where to open related book
        show_toc = false,   -- Show TOC when opening (false to avoid clutter)
    },
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", default_config, opts or {})
    ui.setup(M.config)

    -- Setup reading sessions tracking
    local reading_sessions = require("ink.reading_sessions")
    reading_sessions.setup(M.config.tracking)

    -- Run directory migration (async, non-blocking)
    vim.schedule(function()
        local migration = require("ink.data.directory_migration")
        migration.migrate()
    end)

    -- Function to define highlights
    local function define_highlights()
        vim.cmd([[
      highlight default link InkTitle Title
      highlight default link InkH1 Title
      highlight default link InkH2 Constant
      highlight default link InkH3 Identifier
      highlight default link InkH4 Statement
      highlight default link InkH5 PreProc
      highlight default link InkH6 Type
      highlight default link InkStatement Statement
      highlight default link InkComment Comment
      highlight default link InkSpecial Special
      highlight default link InkListItem Special
      highlight default link InkHorizontalRule Comment
      highlight default link InkCode String
      highlight default link InkHighlight Search
      highlight! InkBold cterm=bold gui=bold
      highlight! InkItalic cterm=italic gui=italic
      highlight! InkUnderlined cterm=underline gui=underline
      highlight! InkStrikethrough cterm=strikethrough gui=strikethrough
      highlight default link InkNoteIndicator DiagnosticInfo
      highlight default link InkNoteText Comment
      highlight default link InkBookmark DiagnosticHint
      highlight default link InkGlossaryUnderline Underlined
      highlight default link InkGlossary DiagnosticInfo
      highlight default link InkGlossaryCharacter DiagnosticInfo
      highlight default link InkGlossaryPlace DiagnosticWarn
      highlight default link InkGlossaryConcept DiagnosticHint
      highlight default link InkGlossaryOrg Function
      highlight default link InkGlossaryObject Constant
      highlight default link InkGlossaryEvent Special
      highlight default link InkGlossaryForeign String
      highlight default link InkGlossaryAlias Comment
    ]])

        -- Define user highlight colors
        for color_name, color_def in pairs(M.config.highlight_colors) do
            local hl_group = "InkUserHighlight_" .. color_name
            vim.api.nvim_set_hl(0, hl_group, {
                bg = color_def.bg,
                fg = color_def.fg
            })
        end
    end

    -- Define highlights initially
    define_highlights()

    -- Re-define highlights after colorscheme changes
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("InkHighlights", { clear = true }),
        callback = function()
            define_highlights()
        end
    })

    -- Create Command
    vim.api.nvim_create_user_command("InkOpen", function(args)
        local path = args.args
        if path == "" then
            vim.notify("Please provide a file path (EPUB or Markdown)", vim.log.levels.ERROR)
            return
        end

        -- Expand path
        path = vim.fn.expand(path)

        -- Detect file format and open accordingly
        local ok, data
        if path:match("^https?://") then
            -- Web page URL (any website)
            ok, data = pcall(web.open, path)
            if not ok then
                vim.notify("Failed to open web page: " .. data, vim.log.levels.ERROR)
                return
            end
        elseif path:match("%.epub$") then
            ok, data = pcall(epub.open, path, { force_content_toc = M.config.force_content_toc })
            if not ok then
                vim.notify("Failed to open EPUB: " .. data, vim.log.levels.ERROR)
                return
            end
        elseif path:match("%.md$") or path:match("%.markdown$") then
            ok, data = pcall(markdown.open, path)
            if not ok then
                vim.notify("Failed to open Markdown: " .. data, vim.log.levels.ERROR)
                return
            end
        else
            vim.notify("Unsupported file format. Please use .epub, .md files, or URLs", vim.log.levels.ERROR)
            return
        end

        ui.open_book(data)
    end, {
        nargs = 1,
        complete = "file"
    })

    -- Create Library command
    vim.api.nvim_create_user_command("InkLibrary", function()
        ui.show_library()
    end, {})

    -- Create Library filtered commands (disabled but kept for future use)
    -- vim.api.nvim_create_user_command("InkListEpubs", function()
    --     local library_view = require("ink.ui.library_view")
    --     library_view.show_library_by_format("epub")
    -- end, {})

    -- vim.api.nvim_create_user_command("InkListMarkdown", function()
    --     local library_view = require("ink.ui.library_view")
    --     library_view.show_library_by_format("markdown")
    -- end, {})

    -- vim.api.nvim_create_user_command("InkListWeb", function()
    --     local library_view = require("ink.ui.library_view")
    --     library_view.show_library_by_format("web")
    -- end, {})

    -- Create Last Book command
    vim.api.nvim_create_user_command("InkLast", function()
        ui.open_last_book()
    end, {})

    -- Create Edit Library command (opens library.json for manual editing)
    vim.api.nvim_create_user_command("InkEditLibrary", function()
        local library_path = vim.fn.stdpath("data") .. "/ink.nvim/library.json"
        vim.cmd("edit " .. library_path)
    end, {})

    -- Create Add Library command (scans directory for EPUBs and adds them to library)
    vim.api.nvim_create_user_command("InkAddLibrary", function(args)
        local library = require("ink.library")
        local directory = args.args
        if directory == "" then
            directory = vim.fn.getcwd()
        end

        vim.notify("Scanning for EPUB files in " .. directory .. "...", vim.log.levels.INFO)

        -- Use async version with callback
        library.scan_directory(directory, function(result, err)
            if not result then
                vim.notify("Error: " .. err, vim.log.levels.ERROR)
                return
            end

            local message = string.format(
                "Scan complete:\n- Total EPUBs found: %d\n- Added to library: %d\n- Already in library: %d",
                result.total,
                result.added,
                result.skipped
            )

            if #result.errors > 0 then
                message = message .. "\n- Failed to parse: " .. #result.errors
                for i, error_info in ipairs(result.errors) do
                    if i <= 3 then
                        message = message .. "\n  * " .. vim.fn.fnamemodify(error_info.path, ":t")
                    end
                end
                if #result.errors > 3 then
                    message = message .. "\n  ... and " .. (#result.errors - 3) .. " more"
                end
            end

            vim.notify(message, vim.log.levels.INFO)
        end)
    end, {
        nargs = "?",
        complete = "dir"
    })

    -- Create Bookmarks commands
    vim.api.nvim_create_user_command("InkBookmarks", function()
        ui.show_all_bookmarks()
    end, {})

    vim.api.nvim_create_user_command("InkBookmarksBook", function()
        ui.show_book_bookmarks()
    end, {})

    -- Create Notes commands
    vim.api.nvim_create_user_command("InkNotes", function()
        local notes = require("ink.notes")
        notes.show_all_notes()
    end, {})

    vim.api.nvim_create_user_command("InkNotesBook", function()
        local notes = require("ink.notes")
        notes.show_book_notes()
    end, {})

    -- Create Floating TOC command (experimental)
    vim.api.nvim_create_user_command("InkTocFloat", function()
        local floating_toc = require("ink.ui.floating_toc")
        floating_toc.toggle_floating_toc()
    end, {})

    -- Create Rebuild TOC command
    vim.api.nvim_create_user_command("InkRebuildTOC", function()
        local context = require("ink.ui.context")
        local ctx = context.current()

        if not ctx or not ctx.data then
            vim.notify("No book is currently open", vim.log.levels.ERROR)
            return
        end

        -- Clear TOC cache
        local toc_cache = require("ink.toc_cache")
        toc_cache.clear(ctx.data.slug)

        -- Rebuild TOC from content
        local content_toc = epub.build_toc_from_content(ctx.data.spine, ctx.data.base_dir, ctx.data.class_styles)

        if #content_toc > 0 then
            ctx.data.toc = content_toc
            toc_cache.save(ctx.data.slug, content_toc)

            -- Re-render TOC if it's open
            if ctx.toc_win and vim.api.nvim_win_is_valid(ctx.toc_win) then
                local toc = require("ink.ui.toc")
                toc.render_toc(ctx)
            end

            vim.notify(string.format("TOC rebuilt with %d entries from content headings", #content_toc),
                vim.log.levels.INFO)
        else
            vim.notify("No headings found in content to build TOC", vim.log.levels.WARN)
        end
    end, {})

    -- Create Glossary commands
    vim.api.nvim_create_user_command("InkGlossary", function()
        local glossary_ui = require("ink.glossary.ui")
        local context = require("ink.ui.context")
        local ctx = context.current()
        if ctx and ctx.data then
            glossary_ui.show_glossary_browser(ctx.data.slug)
        else
            vim.notify("No book is currently open", vim.log.levels.WARN)
        end
    end, {})

    vim.api.nvim_create_user_command("InkGlossaryFloating", function()
        local glossary_ui = require("ink.glossary.ui")
        local context = require("ink.ui.context")
        local ctx = context.current()
        if ctx and ctx.data then
            glossary_ui.show_glossary_browser(ctx.data.slug, true) -- Force floating
        else
            vim.notify("No book is currently open", vim.log.levels.WARN)
        end
    end, {})

    vim.api.nvim_create_user_command("InkGlossaryAdd", function(args)
        local glossary_ui = require("ink.glossary.ui")
        local context = require("ink.ui.context")
        local ctx = context.current()
        if ctx and ctx.data then
            local term = args.args ~= "" and args.args or nil
            glossary_ui.show_add_entry_modal(ctx.data.slug, term, function(entry)
                if entry then
                    vim.notify("Glossary entry '" .. entry.term .. "' added", vim.log.levels.INFO)
                    -- Re-render to show new glossary marks
                    local render = require("ink.ui.render")
                    render.invalidate_glossary_cache(ctx)
                    local cursor = vim.api.nvim_win_get_cursor(ctx.content_win)
                    render.render_chapter(ctx.current_chapter_idx, cursor[1], ctx)
                end
            end)
        else
            vim.notify("No book is currently open", vim.log.levels.WARN)
        end
    end, { nargs = "?" })

    -- Glossary graph commands
    vim.api.nvim_create_user_command("InkGlossaryGraph", function()
        local glossary_ui = require("ink.glossary.ui")
        local context = require("ink.ui.context")
        local ctx = context.current()
        if ctx and ctx.data then
            glossary_ui.show_full_graph(ctx.data.slug)
        else
            vim.notify("No book is currently open", vim.log.levels.WARN)
        end
    end, {})

    -- Create Export command
    vim.api.nvim_create_user_command("InkExport", function()
        local export_ui = require("ink.export.ui")
        export_ui.show_export_dialog()
    end, {})

    -- Web content specific commands
    vim.api.nvim_create_user_command("InkWebToggleVersion", function()
        local context = require("ink.ui.context")
        local ctx = context.current()

        if not ctx or not ctx.data or ctx.data.format ~= "web" then
            vim.notify("This command only works with web content", vim.log.levels.ERROR)
            return
        end

        local new_version_name = web.toggle_version(ctx.data.slug)

        -- Reload the book with new version
        local ok, data = pcall(web.open, ctx.data.url)
        if ok then
            ui.open_book(data)
            vim.notify("Versão alterada para: " .. new_version_name, vim.log.levels.INFO)
        else
            vim.notify("Failed to reload page: " .. data, vim.log.levels.ERROR)
        end
    end, {})

    vim.api.nvim_create_user_command("InkWebChangelog", function()
        local context = require("ink.ui.context")
        local ctx = context.current()

        if not ctx or not ctx.data or ctx.data.format ~= "web" then
            vim.notify("This command only works with web content", vim.log.levels.ERROR)
            return
        end

        local changelog_text = web.get_changelog(ctx.data.slug)

        -- Show in a new buffer
        vim.cmd("new")
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(changelog_text, "\n"))
        vim.bo[buf].filetype = "markdown"
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.api.nvim_buf_set_name(buf, "Web Changelog")
    end, {})

    vim.api.nvim_create_user_command("InkWebCheckUpdates", function()
        local context = require("ink.ui.context")
        local ctx = context.current()

        if not ctx or not ctx.data or ctx.data.format ~= "web" then
            vim.notify("This command only works with web content", vim.log.levels.ERROR)
            return
        end

        vim.notify("Verificando atualizações...", vim.log.levels.INFO)

        local has_update, message = web.check_updates(ctx.data.slug, ctx.data.url)

        if has_update == nil then
            vim.notify("Erro ao verificar atualizações: " .. message, vim.log.levels.ERROR)
        elseif has_update then
            vim.notify(message .. ". Use :InkOpen " .. ctx.data.url .. " para recarregar.", vim.log.levels.WARN)
        else
            vim.notify(message, vim.log.levels.INFO)
        end
    end, {})

    vim.api.nvim_create_user_command("InkWebUpdateSafe", function()
        local context = require("ink.ui.context")
        local ctx = context.current()

        if not ctx or not ctx.data or ctx.data.format ~= "web" then
            vim.notify("This command only works with web content", vim.log.levels.ERROR)
            return
        end

        local fs = require("ink.fs")
        local data_module = require("ink.data")

        -- Check if highlights exist and backup if needed
        local highlights_path = data_module.get_book_dir(ctx.data.slug) .. "/highlights.json"
        local has_highlights = false

        if fs.exists(highlights_path) then
            local content = fs.read_file(highlights_path)
            if content then
                local ok, hl_data = pcall(vim.json.decode, content)
                if ok and hl_data and hl_data.highlights and #hl_data.highlights > 0 then
                    has_highlights = true

                    -- Create backup
                    local backup_path = highlights_path .. ".before-update." .. os.time()
                    local backup_ok, backup_err = fs.copy_file(highlights_path, backup_path)

                    if backup_ok then
                        vim.notify(
                            string.format(
                                "Backup de %d highlight(s) criado: %s",
                                #hl_data.highlights,
                                vim.fn.fnamemodify(backup_path, ":t")
                            ),
                            vim.log.levels.INFO
                        )
                    else
                        vim.notify(
                            "Erro ao criar backup: " .. tostring(backup_err),
                            vim.log.levels.ERROR
                        )
                        return
                    end
                end
            end
        end

        -- Now proceed with the update
        vim.notify("Atualizando página...", vim.log.levels.INFO)
        local ok, data_or_err = pcall(web.open, ctx.data.url, { force_download = true })

        if ok then
            ui.open_book(data_or_err)
            if has_highlights then
                vim.notify(
                    "Página atualizada. Verifique se seus highlights estão alinhados corretamente.",
                    vim.log.levels.WARN
                )
            else
                vim.notify("Página atualizada com sucesso.", vim.log.levels.INFO)
            end
        else
            vim.notify("Erro ao atualizar página: " .. tostring(data_or_err), vim.log.levels.ERROR)
        end
    end, {})

    -- Create Dashboard command
    vim.api.nvim_create_user_command("InkDashboard", function(args)
        local dashboard = require("ink.dashboard")
        local dashboard_type = args.args ~= "" and args.args or "library"
        dashboard.show(dashboard_type)
    end, {
        nargs = "?",
        complete = function()
            return { "library", "stats" }
        end,
    })

    -- Create Reset Statistics command
    vim.api.nvim_create_user_command("InkResetStats", function(args)
        local force = args.bang

        if force then
            -- Force reset without confirmation
            local sessions = require("ink.reading_sessions")
            sessions.reset_all_statistics()
            vim.notify("All reading statistics have been reset", vim.log.levels.WARN)
        else
            -- Ask for confirmation
            local confirm = vim.fn.input("Reset all reading statistics? This cannot be undone. (y/N): ")
            if confirm:lower() == "y" or confirm:lower() == "yes" then
                local sessions = require("ink.reading_sessions")
                sessions.reset_all_statistics()
                vim.notify("All reading statistics have been reset", vim.log.levels.WARN)
            else
                vim.notify("Reset cancelled", vim.log.levels.INFO)
            end
        end
    end, {
        bang = true,
        desc = "Reset all reading statistics (use ! to skip confirmation)"
    })

    -- Create Health Check command
    vim.api.nvim_create_user_command("InkHealth", function()
        local health = require("ink.health")
        health.check()
    end, {
        desc = "Run health check diagnostics for ink.nvim"
    })

    -- Create Cache management commands
    vim.api.nvim_create_user_command("InkClearCache", function(args)
        local arg = args.args

        if arg == "" then
            -- No argument: show interactive UI
            local cache_ui = require("ink.ui.cache")
            cache_ui.show_clear_cache_ui()
        elseif arg == "--all" then
            -- --all flag: clear all cache with confirmation
            local cache_ui = require("ink.ui.cache")
            cache_ui.clear_all_cache()
        else
            -- Specific slug provided
            local success, message = epub.clear_cache(arg)
            if success then
                vim.notify(message, vim.log.levels.INFO)
            else
                vim.notify(message, vim.log.levels.ERROR)
            end
        end
    end, {
        nargs = "?",
        desc = "Clear EPUB cache (interactive, --all, or specific slug)"
    })

    -- Create Clear Search Index command
    vim.api.nvim_create_user_command("InkClearSearchIndex", function(args)
        local context = require("ink.ui.context")
        local search_index = require("ink.ui.search_index")

        local slug = args.args

        if slug == "" then
            -- Clear for current book
            local ctx = context.current()
            if not ctx or not ctx.data then
                vim.notify("No book currently open", vim.log.levels.WARN)
                return
            end

            slug = ctx.data.slug
            ctx.search_index = nil -- Clear in-memory cache too
        end

        search_index.clear_cached_index(slug)
        vim.notify(string.format("Search index cleared for: %s", slug), vim.log.levels.INFO)
    end, {
        nargs = "?",
        desc = "Clear search index cache for current book or specified slug"
    })

    vim.api.nvim_create_user_command("InkCacheInfo", function()
        local info = epub.get_cache_info()
        if info.exists then
            vim.notify(
                string.format("EPUB Cache: %d books cached\nLocation: %s", info.total_books, info.path),
                vim.log.levels.INFO
            )
        else
            vim.notify("No cache directory found", vim.log.levels.INFO)
        end
    end, {})

    vim.api.nvim_create_user_command("InkAddRelated", function()
        local ui = require("ink.ui")
        ui.add_related_resource()
    end, {
        desc = "Add a related resource to the current book via telescope picker"
    })

    vim.api.nvim_create_user_command("InkRemoveRelated", function(args)
        local context = require("ink.ui.context")
        local related = require("ink.data.related")

        local ctx = context.current()
        if not ctx or not ctx.data then
            vim.notify("No book currently open", vim.log.levels.WARN)
            return
        end

        local book_slug = ctx.data.slug
        local related_slug = args.args

        if related_slug == "" then
            vim.notify("Usage: InkRemoveRelated <slug>", vim.log.levels.WARN)
            return
        end

        local success = related.remove_related(book_slug, related_slug)

        if success then
            vim.notify("Related resource removed", vim.log.levels.INFO)
        else
            vim.notify("Failed to remove related resource", vim.log.levels.WARN)
        end
    end, {
        nargs = 1,
        desc = "Remove a related resource from the current book"
    })

    vim.api.nvim_create_user_command("InkListRelated", function()
        local ui = require("ink.ui")
        ui.show_related_resources()
    end, {
        desc = "Show related resources for the current book in telescope"
    })

    -- Create Clean Orphan References command
    vim.api.nvim_create_user_command("InkCleanupRelated", function(args)
        local force = args.bang
        local related = require("ink.data.related")

        -- First check if there are orphans
        local orphans = related.get_orphan_references()

        if #orphans == 0 then
            vim.notify("No orphan references found. All related resources are valid.", vim.log.levels.INFO)
            return
        end

        -- Show what will be cleaned
        vim.notify(string.format("Found %d orphan reference(s) to deleted books", #orphans), vim.log.levels.WARN)

        if not force then
            -- Ask for confirmation
            local confirm = vim.fn.input(string.format(
                "Clean up %d orphan reference(s)? This will remove references to deleted books. (y/N): ",
                #orphans
            ))

            if confirm:lower() ~= "y" and confirm:lower() ~= "yes" then
                vim.notify("Cleanup cancelled", vim.log.levels.INFO)
                return
            end
        end

        -- Perform cleanup
        local cleaned_count, cleaned_slugs = related.cleanup_orphans()

        if cleaned_count > 0 or #cleaned_slugs > 0 then
            vim.notify(
                string.format("Cleanup complete: removed %d orphan entries and references to %d deleted books",
                    cleaned_count, #cleaned_slugs),
                vim.log.levels.INFO
            )
        else
            vim.notify("Cleanup complete: no changes needed", vim.log.levels.INFO)
        end
    end, {
        bang = true,
        desc = "Clean up orphan references in related.json (use ! to skip confirmation)"
    })

    -- Global keymaps for library features
    local keymaps = M.config.keymaps
    local opts = { noremap = true, silent = true }

    if keymaps.library then
        vim.api.nvim_set_keymap("n", keymaps.library, ":InkLibrary<CR>", opts)
    end

    if keymaps.last_book then
        vim.api.nvim_set_keymap("n", keymaps.last_book, ":InkLast<CR>", opts)
    end

    -- Global keymaps for bookmarks
    local bookmark_keymaps = M.config.bookmark_keymaps
    if bookmark_keymaps.list_all then
        vim.api.nvim_set_keymap("n", bookmark_keymaps.list_all, ":InkBookmarks<CR>", opts)
    end
    if bookmark_keymaps.list_book then
        vim.api.nvim_set_keymap("n", bookmark_keymaps.list_book, ":InkBookmarksBook<CR>", opts)
    end

    -- Global keymaps for notes
    local notes_list_keymaps = M.config.notes_list_keymaps
    if notes_list_keymaps.list_all then
        vim.api.nvim_set_keymap("n", notes_list_keymaps.list_all, ":InkNotes<CR>", opts)
    end
    if notes_list_keymaps.list_book then
        vim.api.nvim_set_keymap("n", notes_list_keymaps.list_book, ":InkNotesBook<CR>", opts)
    end

    -- Global keymaps for export
    local export_keymaps = M.config.export_keymaps
    if export_keymaps.current_book then
        vim.api.nvim_set_keymap("n", export_keymaps.current_book, ":InkExport<CR>", opts)
    end

    -- Global keymap for dashboard
    if keymaps.dashboard then
        vim.api.nvim_set_keymap("n", keymaps.dashboard, ":InkDashboard<CR>", opts)
    end

    -- Setup padnotes
    if M.config.padnotes and M.config.padnotes.enabled then
        local padnotes = require("ink.padnotes")
        padnotes.setup(M.config.padnotes)

        local pk = M.config.padnotes_keymaps
        if pk.toggle then
            vim.keymap.set("n", pk.toggle, function() padnotes.toggle() end,
                { noremap = true, silent = true, desc = "Toggle padnote" })
        end
        if pk.open then
            vim.keymap.set("n", pk.open, function() padnotes.open() end,
                { noremap = true, silent = true, desc = "Open padnote" })
        end
        if pk.close then
            vim.keymap.set("n", pk.close, function() padnotes.close(true) end,
                { noremap = true, silent = true, desc = "Close padnote" })
        end
        if pk.list_all then
            vim.keymap.set("n", pk.list_all, function() padnotes.list_all() end,
                { noremap = true, silent = true, desc = "List all padnotes" })
        end
     end

    -- Global keymap for linked resources
    if keymaps.related_resources then
        vim.api.nvim_set_keymap("n", keymaps.related_resources, ":InkListRelated<CR>", opts)
    end

    -- Setup automatic tracking
    if M.config.tracking and M.config.tracking.enabled then
        require("ink.tracking").setup(M.config)
    end
end

return M
