-- lua/ink/ui/search_index.lua
-- Responsabilidade: Construção de índice de busca com cache persistente

local context = require("ink.ui.context")
local render = require("ink.ui.render")

local M = {}

-- Get path to persistent search index cache
local function get_index_cache_path(slug)
	local cache_dir = vim.fn.stdpath("data") .. "/ink.nvim/cache/" .. slug
	local fs = require("ink.fs")
	fs.ensure_dir(cache_dir)
	return cache_dir .. "/search_index.json"
end

-- Load search index from disk cache
function M.load_cached_index(slug, total_chapters)
	local path = get_index_cache_path(slug)
	local fs = require("ink.fs")

	if not fs.exists(path) then
		return nil
	end

	local content = fs.read_file(path)
	if not content or content == "" then
		return nil
	end

	local ok, cached = pcall(vim.json.decode, content)
	if not ok or not cached then
		-- Corrupted cache, delete it
		os.remove(path)
		return nil
	end

	-- Validate cache
	if cached.version ~= 2 or cached.total_chapters ~= total_chapters then
		-- Cache is invalid (different version or chapter count)
		-- Delete old cache file
		os.remove(path)
		return nil
	end

	return cached.entries
end

-- Save search index to disk cache
function M.save_index_to_cache(slug, entries, total_chapters)
	local path = get_index_cache_path(slug)
	-- Cache directory is ensured in get_index_cache_path()

	-- Create cache data
	local cache_data = {
		version = 2,  -- Version 2: uses parsed chapters (line numbers match rendered output)
		created_at = os.time(),
		total_chapters = total_chapters,
		total_entries = #entries,
		entries = entries,
	}

	-- Write to file
	local json_content = data.json_encode(cache_data)
	local file = io.open(path, "w")
	if not file then
		return false
	end

	file:write(json_content)
	file:close()

	return true
end

-- Clear cached index
function M.clear_cached_index(slug)
	local path = get_index_cache_path(slug)
	local fs = require("ink.fs")

	if fs.exists(path) then
		os.remove(path)
	end
end

-- Helper to get chapter name from TOC
function M.get_chapter_name(chapter_idx, ctx)
  local chapter = ctx.data.spine[chapter_idx]
  if not chapter then return "Chapter " .. chapter_idx end

  local chapter_href = chapter.href
  for _, toc_item in ipairs(ctx.data.toc) do
    local toc_href = toc_item.href:match("^([^#]+)") or toc_item.href
    if toc_href == chapter_href then
      -- Truncate name if too long
      local name = toc_item.label
      if #name > 20 then
        name = name:sub(1, 17) .. "..."
      end
      return name
    end
  end

  return "Ch. " .. chapter_idx
end

-- Build search index asynchronously for large books (uses parsed chapters for accuracy)
function M.build_search_index_async(ctx, callback, progress_callback)
  local entries = {}
  local chapter_idx = 1
  local total = #ctx.data.spine

  vim.notify("Building search index...", vim.log.levels.INFO)

  local function process_next()
    if chapter_idx > total then
      -- Save to cache
      M.save_index_to_cache(ctx.data.slug, entries, total)
      vim.notify(string.format("Indexed %d lines from %d chapters", #entries, total), vim.log.levels.INFO)
      callback(entries)
      return
    end

    -- Report progress
    if progress_callback then
      progress_callback(chapter_idx, total)
    end

    -- Get parsed chapter (uses cache if available)
    local parsed = render.get_parsed_chapter(chapter_idx, ctx)
    if parsed and parsed.lines then
      local chapter_name = M.get_chapter_name(chapter_idx, ctx)

      -- Index each line from parsed chapter
      for line_num, line_text in ipairs(parsed.lines) do
        local trimmed = line_text:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
          local display_text = trimmed
          if #display_text > 60 then
            display_text = display_text:sub(1, 57) .. "..."
          end

          table.insert(entries, {
            display = string.format("[%d] %s: %s", chapter_idx, chapter_name, display_text),
            text = trimmed,
            chapter_idx = chapter_idx,
            chapter_name = chapter_name,
            line_num = line_num,
          })
        end
      end
    end

    chapter_idx = chapter_idx + 1
    vim.schedule(process_next)  -- Yield to not block UI
  end

  process_next()
end

-- Build search index from all chapters (synchronous, uses parsed chapters)
function M.build_search_index(ctx)
  local entries = {}
  local total_chapters = #ctx.data.spine

  -- Show progress for large books
  local large_book = total_chapters > 20
  if large_book then
    vim.notify("Building search index...", vim.log.levels.INFO)
  end

  for chapter_idx = 1, total_chapters do
    -- Get parsed chapter (uses cache if available)
    local parsed = render.get_parsed_chapter(chapter_idx, ctx)
    if parsed and parsed.lines then
      local chapter_name = M.get_chapter_name(chapter_idx, ctx)

      -- Index each line from parsed chapter
      for line_num, line_text in ipairs(parsed.lines) do
        -- Ignore empty lines or only spaces
        local trimmed = line_text:match("^%s*(.-)%s*$")
        if trimmed and #trimmed > 0 then
          -- Create context for display (truncate if too long)
          local display_text = trimmed
          if #display_text > 60 then
            display_text = display_text:sub(1, 57) .. "..."
          end

          table.insert(entries, {
            display = string.format("[%d] %s: %s", chapter_idx, chapter_name, display_text),
            text = trimmed,  -- Full text for search
            chapter_idx = chapter_idx,
            chapter_name = chapter_name,
            line_num = line_num,
          })
        end
      end
    end
  end

  if large_book then
    vim.notify(string.format("Indexed %d lines from %d chapters", #entries, total_chapters), vim.log.levels.INFO)
  end

  -- Save to cache
  M.save_index_to_cache(ctx.data.slug, entries, total_chapters)

  return entries
end

-- Get or build search index with persistent caching
function M.get_or_build_index(ctx, callback)
  -- Return in-memory cached index if exists
  if ctx.search_index then
    if callback then
      callback(ctx.search_index)
    else
      return ctx.search_index
    end
    return
  end

  local total_chapters = #ctx.data.spine
  local slug = ctx.data.slug

  -- Try to load from persistent cache
  local cached_index = M.load_cached_index(slug, total_chapters)
  if cached_index then
    ctx.search_index = cached_index
    vim.notify("Search index loaded from cache", vim.log.levels.INFO)
    if callback then
      callback(cached_index)
    else
      return cached_index
    end
    return
  end

  -- No cache found, need to build
  local use_async = total_chapters > 50  -- Use async for books with more than 50 chapters

  if use_async and callback then
    -- Build asynchronously with progress
    M.build_search_index_async(ctx, function(entries)
      ctx.search_index = entries
      callback(entries)
    end, function(current, total)
      -- Progress callback (can be used for UI updates)
      if current % 10 == 0 then
        vim.notify(string.format("Indexing... %d/%d chapters", current, total), vim.log.levels.INFO)
      end
    end)
  else
    -- Build synchronously
    ctx.search_index = M.build_search_index(ctx)
    if callback then
      callback(ctx.search_index)
    else
      return ctx.search_index
    end
  end
end

-- Get indexing status
function M.get_index_status(ctx)
  if ctx.search_index then
    return "ready"
  end

  local slug = ctx.data.slug
  local total_chapters = #ctx.data.spine
  local cached_index = M.load_cached_index(slug, total_chapters)

  if cached_index then
    return "cached"
  end

  return "none"
end

return M
