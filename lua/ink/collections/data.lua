-- lua/ink/collections/data.lua
-- Persistence layer for collections

local M = {}

-- Cache
local cache = {
	collections = nil, -- Cached collections data
}

-- Get path to collections.json
local function get_collections_file_path()
	local data = require("ink.data")
	return data.get_data_dir() .. "/collections.json"
end

-- Load collections from disk
function M.load()
	local path = get_collections_file_path()
	local fs = require("ink.fs")

	if not fs.exists(path) then
		return {
			version = 1,
			collections = {},
		}
	end

	local content = fs.read_file(path)
	if not content or content == "" then
		return {
			version = 1,
			collections = {},
		}
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		-- Backup corrupted file
		vim.notify("Corrupted collections file detected, creating backup", vim.log.levels.WARN)
		os.rename(path, path .. ".corrupt")
		return {
			version = 1,
			collections = {},
		}
	end

	-- Ensure structure
	data.version = data.version or 1
	data.collections = data.collections or {}

	return data
end

-- Save collections to disk
function M.save(data)
	local path = get_collections_file_path()
	local fs = require("ink.fs")
	local ink_data = require("ink.data")

	-- Ensure directory exists
	local data_dir = ink_data.get_data_dir()
	fs.ensure_dir(data_dir)

	-- Backup before saving
	if fs.exists(path) then
		local backup_path = path .. ".backup"
		-- Only keep one backup (overwrite)
		os.rename(path, backup_path)
	end

	-- Encode to JSON
	local content = ink_data.json_encode(data)

	-- Write file
	local file = io.open(path, "w")
	if not file then
		vim.notify("Failed to save collections file: " .. path, vim.log.levels.ERROR)
		return false
	end

	file:write(content)
	file:close()

	-- Invalidate cache
	M.invalidate_cache()

	return true
end

-- Get cached collections or load from disk
function M.get_cached()
	if cache.collections then
		return cache.collections
	end

	cache.collections = M.load()
	return cache.collections
end

-- Invalidate cache
function M.invalidate_cache()
	cache.collections = nil
end

-- Generate ID from name
function M.generate_id(name)
	local id = name:lower()
	id = id:gsub("%s+", "-") -- Replace spaces with hyphens
	id = id:gsub("[^%w-]", "") -- Remove non-alphanumeric except hyphens
	return id
end

-- Check if ID exists
function M.id_exists(id)
	local data = M.get_cached()
	for _, coll in ipairs(data.collections) do
		if coll.id == id then
			return true
		end
	end
	return false
end

-- Make ID unique by adding suffix
function M.make_unique_id(id)
	if not M.id_exists(id) then
		return id
	end

	-- Add timestamp + random suffix to prevent collisions
	-- Random component ensures uniqueness even for rapid consecutive operations
	math.randomseed(os.time() + vim.loop.hrtime())
	local random_suffix = math.random(1000, 9999)
	return id .. "-" .. os.time() .. "-" .. random_suffix
end

return M
